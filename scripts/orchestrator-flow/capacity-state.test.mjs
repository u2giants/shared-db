import assert from 'node:assert/strict'
import test from 'node:test'
import {
  MAX_AUTHOR_LANES, WORKTREE_STATES, assertLaneAvailable, buildDynamicQueues, claimBody,
  main, parseAuthorLease, relinquishAuthorLease, resumeAuthorLease,
} from '../manage-migration-author-lanes.mjs'
import { readFileSync } from 'node:fs'

const NOW=new Date('2026-08-28T12:00:00Z')
const body=(number,{capacityState='active',blockedOn=null,worktreeState=capacityState==='relinquished'?'clean':null,recoveryArtifact=null,expiresAt=new Date('2026-08-29T00:00:00Z')}={})=>claimBody({
  version:`20260828${String(number).padStart(6,'0')}`,
  objects:[`table test.t_${number}`],owner:`owner-${number}`,branch:`branch-${number}`,
  worktree:`C:/work/${number}`,expiresAt,capacityState,blockedOn,worktreeState,recoveryArtifact,
})

test('lease parser accepts the complete relinquishment tuple and rejects contradictory authority',()=>{
  for(const worktreeState of WORKTREE_STATES){
    const lease=parseAuthorLease(body(1,{capacityState:'relinquished',blockedOn:'issue:#900',worktreeState,recoveryArtifact:'artifact:'+'a'.repeat(40)}),NOW)
    assert.equal(lease.worktreeState,worktreeState)
    assert.equal(lease.recoveryArtifact,'artifact:'+'a'.repeat(40))
  }
  assert.throws(()=>body(1,{capacityState:'expired-unconfirmed'}),/capacityState must be one of/)
  assert.throws(()=>body(1,{capacityState:'relinquished',blockedOn:'issue:#900',worktreeState:null}),/requires worktreeState/)
  assert.throws(()=>body(1,{worktreeState:'clean'}),/only for relinquished/)
  assert.throws(()=>body(1,{recoveryArtifact:'artifact:'+'a'.repeat(40)}),/only for relinquished/)
  assert.throws(()=>body(1,{capacityState:'relinquished',blockedOn:'issue:#900',worktreeState:'unknown'}),/requires worktreeState/)
  assert.throws(()=>body(1,{capacityState:'relinquished',blockedOn:'issue:#900',recoveryArtifact:'artifact:mutable',worktreeState:'clean'}),/immutable-url-or-hash/)
  const active=body(1)
  for(const line of [
    'capacity_state: expired-unconfirmed',
    'worktree_state: clean',
    'recovery: artifact:'+'a'.repeat(40),
    'mystery: value',
  ]) assert.throws(()=>parseAuthorLease(active.replace('capacity_state: active',`capacity_state: active\n${line}`),NOW),/unreadable|capacity_state must be|only for relinquished|unknown field/)
  assert.throws(()=>parseAuthorLease(active.replace('owner: owner-1','owner: owner-1\nowner: duplicate'),NOW),/unreadable/)
})

test('pre-Phase-A relinquished fences remain protected but are recovery blocked',()=>{
  const legacyBody=body(1,{capacityState:'relinquished',blockedOn:'issue:#900'}).replace(/^worktree_state:.*\r?\n/m,'')
  const lease=parseAuthorLease(legacyBody,NOW)
  assert.equal(lease.capacityActive,false)
  assert.equal(lease.worktreeState,'unknown-legacy')
  assert.equal(lease.relinquishmentMetadataLegacy,true)
})

test('relinquished claims protect objects without consuming active capacity',()=>{
  const claims=Array.from({length:8},(_,index)=>({number:index+1,body:body(index+1,{capacityState:'relinquished',blockedOn:'issue:#900'})}))
  const result=assertLaneAvailable(claims,['table test.new'],NOW)
  assert.equal(result.protected.length,8)
  assert.equal(result.active.length,0)
  assert.throws(()=>assertLaneAvailable(claims,['table test.t_8'],NOW),/collision/)
})

test('clock expiry blocks merge readiness but frees zero capacity',()=>{
  const expired=Array.from({length:MAX_AUTHOR_LANES},(_,index)=>({number:index+1,body:body(index+1,{expiresAt:new Date('2026-08-28T11:00:00Z')})}))
  assert.equal(parseAuthorLease(expired[0].body,NOW).capacityState,'expired-unconfirmed')
  assert.throws(()=>assertLaneAvailable(expired,['table test.new'],NOW),/active-author leases are occupied/)
})

test('more protected claims than the active cap remain representable in queues',()=>{
  const claims=Array.from({length:8},(_,index)=>({number:index+1,body:body(index+1,{capacityState:'relinquished',blockedOn:'issue:#900'})}))
  const result=buildDynamicQueues([],claims,NOW)
  assert.equal(result.queues.flatMap((queue)=>queue.protected).length,8)
  assert.equal(result.emptyLanes,MAX_AUTHOR_LANES)
})

function memoryIo(){
  const refs=new Map(),comments=[],issues=new Map()
  const claim={number:77,state:'open',title:'CLAIM: #42 throughput fixture',body:body(77)}
  issues.set(77,claim);issues.set(42,{number:42,state:'open',body:''});issues.set(900,{number:900,state:'open',body:''})
  refs.set('refs/db-claims/20260828000077','reservation')
  let serial=0
  return {
    comments,issues,
    makeOwnerCommit:()=>`owner-${++serial}`,
    createRef:(name,sha)=>{if(refs.has(name))return false;refs.set(name,sha);return true},
    readRef:(name)=>refs.get(name)??null,
    deleteRef:(name)=>{refs.delete(name)},
    getCommitMessage:()=>'',
    openClaims:()=>[structuredClone(issues.get(77))],
    getIssue:(number)=>structuredClone(issues.get(Number(number))),
    updateIssue:(number,{body:newBody})=>{issues.get(Number(number)).body=newBody},
    localClean:()=>true,
    prSources:()=>[],
    commentIssue:(number,comment)=>comments.push({number,body:comment}),
  }
}

test('guarded relinquish and resume preserve the claim and write replayable events',()=>{
  const io=memoryIo()
  const relinquished=relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io)
  assert.equal(relinquished.capacityState,'relinquished')
  assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).capacityActive,false)
  const resumed=resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io)
  assert.equal(resumed.capacityState,'active')
  assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).active,true)
  assert.equal(io.comments.length,4)
})

test('resume excludes only the protected claim own open pull request',()=>{
  const io=memoryIo()
  relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io)
  io.prSources=()=>[{label:'PR #78',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000077']}]
  const resumed=resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io)
  assert.equal(resumed.capacityState,'active')
  assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).capacityActive,true)
})

test('resume preserves every foreign claim and pull-request collision',()=>{
  for(const collision of ['claim','pull request']){
    const io=memoryIo()
    relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io)
    io.prSources=()=>[{label:'PR #78',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000077']}]
    if(collision==='claim'){
      const original=io.openClaims
      io.openClaims=()=>[...original(),{number:88,state:'open',body:body(88).replace('table test.t_88','table test.t_77')}]
    }else{
      io.prSources=()=>[
        {label:'PR #78',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000077']},
        {label:'PR #89',branch:'branch-89',objects:['table test.t_77'],versions:['20260828000089']},
      ]
    }
    assert.throws(()=>resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io),/object collision/)
    assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).capacityState,'relinquished')
  }
})

test('resume refuses ambiguous or version-mismatched self pull-request identity',()=>{
  for(const identity of ['ambiguous','wrong version']){
    const io=memoryIo()
    relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io)
    io.prSources=()=>identity==='ambiguous' ? [
      {label:'PR #78',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000077']},
      {label:'PR #79',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000077']},
    ] : [{label:'PR #78',branch:'branch-77',objects:['table test.t_77'],versions:['20260828000078']}]
    assert.throws(
      ()=>resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io),
      identity==='ambiguous' ? /multiple open pull-request sources/ : /does not carry the permanent claim version/,
    )
    assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).capacityState,'relinquished')
  }
})

test('relinquishment records only matching worktree evidence states',()=>{
  for(const state of WORKTREE_STATES){
    const io=memoryIo()
    io.localWorktreeState=()=>({state})
    const options={claim:77,owner:'owner-77',blockedOn:'issue:#900'}
    if(state!=='clean')options.worktreeState=state
    const result=relinquishAuthorLease(options,NOW,io)
    assert.equal(result.worktreeState,state)
    assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).worktreeState,state)
  }
  for(const state of ['dirty','absent','remote']){
    const io=memoryIo();io.localWorktreeState=()=>({state})
    assert.throws(()=>relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io),new RegExp(`explicit --worktree-state ${state} is required`))
  }
  const io=memoryIo();io.localWorktreeState=()=>{throw new Error('access denied')}
  assert.throws(()=>relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900',worktreeState:'absent'},NOW,io),/inspection is ambiguous/)
})

test('claim 2574 absent-worktree shape can relinquish only with explicit absent evidence',()=>{
  const io=memoryIo();io.localWorktreeState=()=>({state:'absent'})
  assert.throws(()=>relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io),/explicit --worktree-state absent is required/)
  const result=relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900',worktreeState:'absent'},NOW,io)
  assert.equal(result.worktreeState,'absent')
})

test('idempotence binds blocker, worktree state, and recovery artifact',()=>{
  const io=memoryIo();io.localWorktreeState=()=>({state:'dirty'})
  const tuple={claim:77,owner:'owner-77',blockedOn:'issue:#900',worktreeState:'dirty',recoveryArtifact:'artifact:'+'b'.repeat(64)}
  relinquishAuthorLease(tuple,NOW,io)
  assert.equal(relinquishAuthorLease(tuple,NOW,io).idempotent,true)
  assert.throws(()=>relinquishAuthorLease({...tuple,recoveryArtifact:'artifact:'+'c'.repeat(64)},NOW,io),/different blocker, worktree state, or recovery artifact/)
})

test('legacy relinquishment metadata must be reconciled before resume',()=>{
  const io=memoryIo()
  io.issues.get(77).body=body(77,{capacityState:'relinquished',blockedOn:'issue:#900'}).replace(/^worktree_state:.*\r?\n/m,'')
  assert.throws(()=>resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io),/must be reconciled/)
  const reconciled=relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,io)
  assert.equal(reconciled.idempotent,false)
  assert.equal(parseAuthorLease(io.issues.get(77).body,NOW).worktreeState,'clean')
})

test('resume from non-clean evidence requires current clean proof or immutable recovery',()=>{
  for(const state of ['dirty','absent','remote']){
    const io=memoryIo();io.localWorktreeState=()=>({state})
    relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900',worktreeState:state},NOW,io)
    assert.throws(()=>resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,io),/requires a proven-clean worktree or --recovery-artifact/)
    assert.equal(resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12,recoveryArtifact:'artifact:'+'d'.repeat(40)},NOW,io).capacityState,'active')
  }
  const recovered=memoryIo();recovered.localWorktreeState=()=>({state:'dirty'})
  relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900',worktreeState:'dirty'},NOW,recovered)
  recovered.localWorktreeState=()=>({state:'clean'})
  assert.equal(resumeAuthorLease({claim:77,owner:'owner-77',leaseHours:12},NOW,recovered).capacityState,'active')
})

test('blocker TOCTOU and failed readback roll back without partial capacity write',()=>{
  const changing=memoryIo(),get=changing.getIssue;let blockerReads=0
  changing.getIssue=(number)=>{if(Number(number)===900&&++blockerReads>1)return{number:900,state:'closed',body:''};return get(number)}
  assert.throws(()=>relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,changing),/not durably open/)
  assert.equal(parseAuthorLease(changing.issues.get(77).body,NOW).capacityState,'active')

  const badReadback=memoryIo(),read=badReadback.getIssue;let claimReads=0
  badReadback.getIssue=(number)=>{const issue=read(number);if(Number(number)===77&&++claimReads===2)return{...issue,body:issue.body.replace('worktree_state: clean','worktree_state: dirty')};return issue}
  assert.throws(()=>relinquishAuthorLease({claim:77,owner:'owner-77',blockedOn:'issue:#900'},NOW,badReadback),/readback failed/)
  assert.equal(parseAuthorLease(badReadback.issues.get(77).body,NOW).capacityState,'active')
})

test('CLI accepts explicit worktree and recovery evidence flags',()=>{
  const io=memoryIo();io.localWorktreeState=()=>({state:'absent'})
  const originalLog=console.log;console.log=()=>{}
  try{assert.equal(main(['--relinquish-author-lease','--claim-number','77','--owner','owner-77','--blocked-on','issue:#900','--worktree-state','absent','--recovery-artifact','artifact:'+'e'.repeat(40)],NOW,io),0)}finally{console.log=originalLog}
  const lease=parseAuthorLease(io.issues.get(77).body,NOW)
  assert.equal(lease.worktreeState,'absent')
  assert.equal(lease.recoveryArtifact,'artifact:'+'e'.repeat(40))
})

test('capacity lifecycle never mutates worktree contents',()=>{
  const source=readFileSync(new URL('../manage-migration-author-lanes.mjs',import.meta.url),'utf8')
  for(const name of ['relinquishAuthorLease','resumeAuthorLease']){
    const start=source.indexOf(`export function ${name}`),end=source.indexOf('\nfunction ',start)
    const body=source.slice(start,end)
    assert.doesNotMatch(body,/\b(?:delete|move|clean|reset|write|rename)(?:Sync)?\s*\(/i)
  }
})
