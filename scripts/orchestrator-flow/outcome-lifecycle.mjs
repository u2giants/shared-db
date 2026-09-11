import { createHash } from 'node:crypto'
import { coordinationEvent, formatEventComment, parseEventComment } from '../db-coordination-events.mjs'
import { COMPLETION_FENCE, findCompletionRecord, validateCompletionRecord } from '../lib/work-dependencies.mjs'

export class OutcomeError extends Error {}

export const OUTCOME_STATES = Object.freeze([
  'entered', 'classified', 'dispatched', 'implementation_complete', 'review_ready',
  'preview_verified', 'merged', 'production_authorized', 'production_applied',
  'live_verified', 'blocked', 'yielded',
])
export const OUTCOME_EVIDENCE_FENCE = 'db-outcome-evidence'

const SHA = /^[0-9a-f]{40}$/i
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/
const EVIDENCE_REF = /^(?:https:\/\/github\.com\/|artifact:)/
const LINEAR = Object.freeze([
  'entered', 'classified', 'dispatched', 'implementation_complete', 'review_ready',
  'preview_verified', 'merged', 'production_authorized', 'production_applied', 'live_verified',
])

export function parseOutcomeEvidence(body = '') {
  const fences = [...String(body).matchAll(new RegExp('```' + OUTCOME_EVIDENCE_FENCE + '\\s*\\n([\\s\\S]*?)```', 'g'))]
  if (fences.length !== 1) throw new OutcomeError('evidence reference must resolve to exactly one db-outcome-evidence block')
  let record
  try { record = JSON.parse(fences[0][1]) } catch { throw new OutcomeError('db-outcome-evidence block is not valid JSON') }
  if (!record || typeof record !== 'object' || Array.isArray(record)) throw new OutcomeError('db-outcome-evidence must be a JSON object')
  const known = new Set([
    'schema_version', 'work_issue', 'merge_pr', 'merge_sha', 'application_repository',
    'application_commit_sha', 'generated_types_evidence', 'live_assertion',
    'live_evidence', 'live_artifact_id', 'live_artifact_digest', 'environment', 'verified_at',
  ])
  for (const key of Object.keys(record)) if (!known.has(key)) throw new OutcomeError(`db-outcome-evidence has unknown field ${key}`)
  if (record.schema_version !== 1) throw new OutcomeError('db-outcome-evidence schema_version must be 1')
  if (!Number.isInteger(record.work_issue) || record.work_issue <= 0) throw new OutcomeError('db-outcome-evidence work_issue must be positive')
  if (!Number.isInteger(record.merge_pr) || record.merge_pr <= 0) throw new OutcomeError('db-outcome-evidence must name merge_pr')
  if (!SHA.test(record.merge_sha ?? '')) throw new OutcomeError('db-outcome-evidence must name the exact 40-character merge_sha')
  if (!REPOSITORY.test(record.application_repository ?? '')) throw new OutcomeError('db-outcome-evidence must name application_repository as owner/repo')
  if (!SHA.test(record.application_commit_sha ?? '')) throw new OutcomeError('db-outcome-evidence must name the exact application_commit_sha')
  if (typeof record.live_assertion !== 'string' || !record.live_assertion.trim()) throw new OutcomeError('db-outcome-evidence must repeat the live assertion')
  if (typeof record.live_evidence !== 'string' || !EVIDENCE_REF.test(record.live_evidence)) throw new OutcomeError('db-outcome-evidence must link durable live application proof')
  if (!Number.isInteger(record.live_artifact_id) || record.live_artifact_id <= 0) throw new OutcomeError('db-outcome-evidence must name the live proof artifact id')
  if (typeof record.live_artifact_digest !== 'string' || !/^sha256:[0-9a-f]{64}$/i.test(record.live_artifact_digest)) throw new OutcomeError('db-outcome-evidence must name the live proof artifact sha256 digest')
  if (typeof record.environment !== 'string' || !record.environment.trim()) throw new OutcomeError('db-outcome-evidence must name the environment verified')
  if (typeof record.verified_at !== 'string' || Number.isNaN(Date.parse(record.verified_at))) throw new OutcomeError('db-outcome-evidence verified_at must be an ISO instant')
  return record
}

export function outcomeHistory(comments = []) {
  const events = comments.flatMap((comment) => parseEventComment(comment?.body ?? ''))
    .filter((event) => OUTCOME_STATES.includes(event.event_type))
    .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp)
      || (LINEAR.indexOf(a.event_type)<0?LINEAR.length:LINEAR.indexOf(a.event_type))-(LINEAR.indexOf(b.event_type)<0?LINEAR.length:LINEAR.indexOf(b.event_type))
      || a.event_id.localeCompare(b.event_id))
  const problems = []
  const seen = new Set()
  let highest = -1
  let blocked = false
  for (const event of events) {
    if (seen.has(event.event_id)) { problems.push(`duplicate outcome event ${event.event_id}`); continue }
    seen.add(event.event_id)
    if (event.result === 'refused') continue
    if (event.event_type === 'blocked') { blocked = true; continue }
    if (event.event_type === 'yielded') { blocked = false; continue }
    const index = LINEAR.indexOf(event.event_type)
    if (index < 0) continue
    if (index > highest + 1) problems.push(`${event.event_type} skips ${LINEAR[highest + 1]}`)
    if (index <= highest) problems.push(`${event.event_type} repeats or moves backward from ${LINEAR[highest]}`)
    highest = Math.max(highest, index)
  }
  return {
    valid: problems.length === 0,
    problems,
    state: highest >= 0 ? LINEAR[highest] : null,
    blocked,
    complete: highest === LINEAR.length - 1,
    events,
  }
}

export function assertOutcomeTransition(comments, next) {
  if (!OUTCOME_STATES.includes(next)) throw new OutcomeError(`unknown outcome state ${next}`)
  const history = outcomeHistory(comments)
  if (!history.valid) throw new OutcomeError(`outcome history is invalid: ${history.problems.join('; ')}`)
  if (next === 'blocked') {
    if(history.blocked)throw new OutcomeError('outcome is already blocked')
    return history
  }
  if (next === 'yielded') {
    if(!history.blocked)throw new OutcomeError('outcome can yield only from blocked')
    return history
  }
  const expected = LINEAR[(history.state ? LINEAR.indexOf(history.state) : -1) + 1]
  if (next !== expected) throw new OutcomeError(`cannot advance outcome from ${history.state ?? 'none'} to ${next}; next state is ${expected ?? 'none'}`)
  return history
}

export function advanceOutcome({issue,state,actor,timestamp=new Date().toISOString(),evidenceUrls=[]},io){
  const comments=io.issueComments(Number(issue))
  assertOutcomeTransition(comments,state)
  const event=outcomeEvent({issue,state,actor,timestamp,evidenceUrls})
  io.commentIssue(Number(issue),formatEventComment(event))
  const readBack=outcomeHistory(io.issueComments(Number(issue)))
  if(!readBack.valid||!readBack.events.some((row)=>row.event_id===event.event_id))throw new OutcomeError(`outcome ${state} event did not read back exactly`)
  return {issue:Number(issue),state,event_id:event.event_id}
}

export function outcomeEvent({ issue, state, actor, timestamp, evidenceUrls = [], detail }) {
  return coordinationEvent({
    eventType: state, workIssue: Number(issue), actor, timestamp,
    evidence_urls: evidenceUrls, ...(detail ? { detail } : {}),
  })
}

function sameSha(expected, actual) { return String(expected).toLowerCase() === String(actual).toLowerCase() }

export function completeOutcome({ issue, evidenceRef, actor, timestamp = new Date().toISOString() }, io) {
  const work = io.getIssue(Number(issue))
  if (!work || String(work.state).toLowerCase() !== 'open') throw new OutcomeError(`outcome issue #${issue} must remain open until live verification`)
  const scope = io.parseScope(work.body ?? '')
  if (!scope || scope.workType !== 'structural' || scope.route !== 'shared-db-orchestrator') throw new OutcomeError('only an admitted structural outcome can complete')
  if (!scope.applicationReturnTo || !scope.liveAssertion) throw new OutcomeError('outcome is missing its application return address or live assertion')
  const history = outcomeHistory(io.issueComments(Number(issue)))
  if (!history.valid) throw new OutcomeError(`outcome history is invalid: ${history.problems.join('; ')}`)
  if (history.state !== 'production_applied') throw new OutcomeError(`merge or preview is not completion; outcome is at ${history.state ?? 'none'}, not production_applied`)
  if(findCompletionRecord(io.issueComments(Number(issue))))throw new OutcomeError(`issue #${issue} already has an immutable completion record`)

  const evidenceBody = io.readOutcomeEvidence(evidenceRef)
  const evidence = parseOutcomeEvidence(evidenceBody)
  if (evidence.work_issue !== Number(issue)) throw new OutcomeError(`evidence belongs to issue #${evidence.work_issue}`)
  if (evidence.application_repository !== scope.applicationReturnTo) throw new OutcomeError('evidence application repository does not match application_return_to')
  if (evidence.live_assertion !== scope.liveAssertion) throw new OutcomeError('live evidence does not prove the intake live_assertion verbatim')
  if (scope.generatedTypes === 'required' && !(typeof evidence.generated_types_evidence === 'string' && EVIDENCE_REF.test(evidence.generated_types_evidence))) {
    throw new OutcomeError('generated types are required but no durable generated-types evidence was supplied')
  }
  const pr = io.getPr(evidence.merge_pr)
  if (!pr?.merged_at || !sameSha(evidence.merge_sha, pr.merge_commit_sha ?? '')) throw new OutcomeError('merge evidence does not match GitHub')
  if (!io.mergeCommitInMain(evidence.merge_sha)) throw new OutcomeError('merge commit is not in current shared-db main history')
  if (!io.applicationCommitInDefaultBranch(evidence.application_repository, evidence.application_commit_sha)) {
    throw new OutcomeError('application commit is not in the application default branch history')
  }
  if (!io.verifyLiveAssertion(evidence)) throw new OutcomeError('live application assertion could not be re-derived from its durable evidence')

  assertOutcomeTransition(io.issueComments(Number(issue)), 'live_verified')
  const event = outcomeEvent({ issue, state: 'live_verified', actor, timestamp, evidenceUrls: [evidenceRef, evidence.live_evidence] })
  io.commentIssue(Number(issue), formatEventComment(event))
  const completion=validateCompletionRecord({
    schema_version:1, work_issue:Number(issue), outcome:'live_verified', pr:evidence.merge_pr,
    merge_sha:evidence.merge_sha, application_repository:evidence.application_repository,
    application_commit_sha:evidence.application_commit_sha, live_evidence:evidence.live_evidence,
  })
  io.commentIssue(Number(issue),[
    'Authoritative outcome completion. Published only after live evidence was re-derived.', '',
    '```'+COMPLETION_FENCE, JSON.stringify(completion,null,2), '```',
  ].join('\n'))
  const readBack = outcomeHistory(io.issueComments(Number(issue)))
  const completionReadBack=findCompletionRecord(io.issueComments(Number(issue)))
  if (!readBack.valid || !readBack.complete || completionReadBack?.outcome!=='live_verified') throw new OutcomeError('live_verified event or completion record did not read back as the authoritative completion')
  io.updateIssue(Number(issue),{state:'closed'})
  if(String(io.getIssue(Number(issue))?.state??'').toLowerCase()!=='closed')throw new OutcomeError('authoritative outcome was verified but the issue did not close on exact readback')
  return { issue: Number(issue), state: 'live_verified', completed: true, evidence_digest: createHash('sha256').update(JSON.stringify(evidence)).digest('hex') }
}
