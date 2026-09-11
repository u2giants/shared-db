import test from 'node:test'
import assert from 'node:assert/strict'
import { canonicalJson } from './evidence-bundle.mjs'
import {
  OrchestratorSnapshotError,
  buildOrchestratorSnapshot,
  transitionNotification,
  verifyOrchestratorSnapshot,
  publishSnapshotTransition,
  agentCheckInNotification,
  publishAgentCheckIn,
} from './orchestrator-snapshot.mjs'

const input = () => ({
  marker: { issue: 2758, status: 'active', route_id: 'local_owner' },
  claims: [{ issue: 20, writes: ['core.b'] }, { issue: 10, writes: ['core.a'] }],
  pull_requests: [{ number: 2, head: 'b'.repeat(40) }],
  reviewer_leases: [],
  stage_locks: [{ stage: 'merge', holder: null }],
  outcome_events: [{ event_id: 'event-1', work_issue: 10 }],
  eligible_queue: [{ issue: 30, priority: 5 }],
})

test('publishing is edge-triggered and unchanged state emits no check-in',()=>{
  const first=buildOrchestratorSnapshot(input()),published=[]
  const writer=(row)=>{published.push(row);return{status:'created',event_id:row.notification.event_id}}
  const same=publishSnapshotTransition(input(),{previousSnapshot:first,publish:writer})
  assert.equal(same.notification,null);assert.equal(published.length,0)
  const changed=input();changed.eligible_queue.push({issue:32,priority:1})
  publishSnapshotTransition(changed,{previousSnapshot:first,publish:writer})
  assert.equal(published.length,1);assert.equal(published[0].notification.event_type,'orchestrator_state_changed')
})

test('agents suppress progress chatter and report one terminal fact',()=>{
  for(const status of ['intermediate','unchanged','working','waiting'])assert.equal(agentCheckInNotification({status}),null)
  const completed=agentCheckInNotification({status:'completed',issue:7,evidence_id:'artifact:7'})
  assert.equal(completed.event_type,'agent_completed');assert.match(completed.event_id,/^[0-9a-f]{64}$/)
  assert.throws(()=>agentCheckInNotification({status:'blocked',issue:7,evidence_id:''}),/durable evidence/)
})

test('snapshot and terminal check-in retries converge to one immutable event',()=>{
  const stored=new Map(),compareCreate=(event)=>{const value=event.notification??event,key=value.event_id,prior=stored.get(key);if(prior&&canonicalJson(prior)!==canonicalJson(value))throw new Error('collision');if(prior)return{status:'existing',event_id:key};stored.set(key,value);return{status:'created',event_id:key}}
  const first=buildOrchestratorSnapshot(input()),changed=input();changed.claims.push({issue:99,writes:['core.z']})
  const one=publishSnapshotTransition(changed,{previousSnapshot:first,publish:compareCreate}),two=publishSnapshotTransition(changed,{previousSnapshot:first,publish:compareCreate})
  assert.equal(one.notification.event_id,two.notification.event_id);assert.equal(stored.size,1)
  const check={status:'blocked',issue:99,evidence_id:'artifact:block-99'}
  publishAgentCheckIn(check,{publish:compareCreate});publishAgentCheckIn(check,{publish:compareCreate})
  assert.equal(stored.size,2)
  assert.throws(()=>publishAgentCheckIn(check,{publish:()=>({status:'created',event_id:'wrong'})}),/acknowledgement/)
})

test('snapshot is deterministic despite collection order and capture time', () => {
  const first = buildOrchestratorSnapshot(input(), { capturedAt: '2026-09-11T17:00:00Z' })
  const reordered = input()
  reordered.claims.reverse()
  const second = buildOrchestratorSnapshot(reordered, { capturedAt: '2026-09-11T17:01:00Z' })
  assert.equal(first.snapshot_id, second.snapshot_id)
  assert.notEqual(first.captured_at, second.captured_at)
})

test('successor accepts one exact fresh snapshot', () => {
  const snapshot = buildOrchestratorSnapshot(input(), { capturedAt: '2026-09-11T17:00:00Z' })
  assert.deepEqual(verifyOrchestratorSnapshot(snapshot, input()), {
    status: 'CURRENT', snapshot_id: snapshot.snapshot_id,
  })
})

test('changed live input refuses as stale', () => {
  const snapshot = buildOrchestratorSnapshot(input())
  const changed = input()
  changed.pull_requests[0].head = 'c'.repeat(40)
  assert.throws(() => verifyOrchestratorSnapshot(snapshot, changed), /snapshot is stale/)
})

test('tampered snapshot refuses even when current input matches the original', () => {
  const snapshot = buildOrchestratorSnapshot(input())
  snapshot.state.claims[0].issue = 999
  assert.throws(() => verifyOrchestratorSnapshot(snapshot, input()), /snapshot seal is invalid/)
})

test('unchanged state produces no notification and a transition wakes once', () => {
  const first = buildOrchestratorSnapshot(input())
  const same = buildOrchestratorSnapshot(input())
  assert.equal(transitionNotification(first, same), null)
  const changed = input()
  changed.eligible_queue.push({ issue: 31, priority: 4 })
  const next = buildOrchestratorSnapshot(changed)
  const notification=transitionNotification(first,next)
  assert.equal(notification.event_type,'orchestrator_state_changed')
  assert.equal(notification.previous_snapshot_id,first.snapshot_id)
  assert.equal(notification.snapshot_id,next.snapshot_id)
  assert.match(notification.event_id,/^[0-9a-f]{64}$/)
})

test('unroutable marker and unreadable collections fail closed', () => {
  const missingRoute = input()
  missingRoute.marker.route_id = ''
  assert.throws(() => buildOrchestratorSnapshot(missingRoute), OrchestratorSnapshotError)
  const missingClaims = input()
  delete missingClaims.claims
  assert.throws(() => buildOrchestratorSnapshot(missingClaims), /claims must be an array/)
})
