import { canonicalJson, sha256 } from './evidence-bundle.mjs'

export class StartRerouteError extends Error {}
export const START_SLO_MS=10*60*1000
export const REROUTE_REF_PREFIX='refs/db-start-reroutes'
const SHA=/^[0-9a-f]{40}$/i, DIGEST=/^[0-9a-f]{64}$/i, TOKEN=/^[A-Za-z0-9._-]+$/
function ms(value){const n=Date.parse(value);if(Number.isNaN(n))throw new StartRerouteError('timestamp is unreadable');return n}
function token(value,label){if(!TOKEN.test(String(value??'')))throw new StartRerouteError(`${label} is unsafe`);return String(value)}
function assertions(value,label='required assertions'){
  if(!Array.isArray(value)||!value.length)throw new StartRerouteError(`${label} must be nonempty`)
  const normalized=value.map((x)=>token(x,'assertion')).sort()
  if(new Set(normalized).size!==normalized.length)throw new StartRerouteError(`${label} must be unique`)
  return normalized
}

export function reviewerStartDecision(assignment,{now,provider_state,lifecycle=[]}){
  if(!assignment?.id||!SHA.test(String(assignment.head_sha??'')))throw new StartRerouteError('exact assignment and head are required')
  const events=lifecycle.filter((e)=>e.assignment_id===assignment.id),started=events.find((e)=>['provider_launched','provider_contacted','review_started'].includes(e.type))
  if(started)return {action:'keep-active',started_at:started.at,source:'durable-lifecycle'}
  if(events.some((e)=>e.type==='terminal_format_invalid'))return {action:'same-session-clarification'}
  const overdue=ms(now)-ms(assignment.assigned_at)>=START_SLO_MS
  if(!overdue&&provider_state==='usable')return {action:'wait'}
  if(provider_state==='remote-unknown')throw new StartRerouteError('paid review start is uncertain; preserve the lease and refuse replacement')
  if(!['unusable','quarantined','confirmed-not-started'].includes(provider_state))throw new StartRerouteError('reviewer start state is not authoritative')
  return {action:'governed-return-and-reroute',reason:provider_state}
}

export function runnerStartDecision(attempt,{now,lifecycle=[],qualified_lanes=[]}){
  if(!attempt?.id||!attempt.workflow||!attempt.lane||!SHA.test(String(attempt.head_sha??'')))throw new StartRerouteError('runner attempt requires exact workflow, lane, head, and assertions')
  const required=assertions(attempt.required_assertions)
  const events=lifecycle.filter((e)=>e.attempt_id===attempt.id),started=events.find((e)=>e.type==='runner_started')
  if(started)return {action:'keep-active',started_at:started.at}
  if(ms(now)-ms(attempt.queued_at)<START_SLO_MS)return {action:'wait'}
  const lane=qualified_lanes.find((x)=>x.name!==attempt.lane&&x.qualified===true&&(()=>{try{return canonicalJson(assertions(x.assertions,'lane assertions'))===canonicalJson(required)}catch{return false}})())
  if(!lane)throw new StartRerouteError('no independent qualified runner lane preserves every assertion')
  return {action:'dispatch-new-run',lane:lane.name,supersedes:attempt.id,workflow:attempt.workflow,head_sha:attempt.head_sha.toLowerCase(),required_assertions:required}
}

function reserveAndDispatch(kind,original,decision,replacement,io){
  const expectedAction=kind==='reviewer'?'governed-return-and-reroute':'dispatch-new-run'
  if(decision?.action!==expectedAction)throw new StartRerouteError(`cannot reserve a ${kind} reroute from this decision`)
  const originalId=token(original.id,`${kind} original id`),replacementId=token(replacement.id,`${kind} replacement id`)
  const record={schema_version:1,kind,original_id:originalId,replacement_id:replacementId,head_sha:String(original.head_sha).toLowerCase(),...(kind==='runner'?{workflow:token(original.workflow,'workflow'),lane:token(decision.lane,'lane'),required_assertions:assertions(original.required_assertions)}:{provider:token(replacement.provider,'replacement provider')})}
  const rerouteId=sha256(canonicalJson(record)),sealed={...record,reroute_id:rerouteId},ref=`${REROUTE_REF_PREFIX}/${kind}/${originalId}`
  if(typeof io?.createReroute!=='function'||typeof io?.readReroute!=='function'||typeof io?.createReplacement!=='function')throw new StartRerouteError('atomic reroute store and dispatcher are required')
  if(!io.createReroute(ref,rerouteId,sealed)){
    const prior=io.readReroute(ref)
    if(prior?.digest!==rerouteId||canonicalJson(prior.record)!==canonicalJson(sealed))throw new StartRerouteError(`a different ${kind} replacement already owns this original attempt`)
  }
  const acknowledgement=io.createReplacement(rerouteId,sealed)
  if(!acknowledgement||acknowledgement.reroute_id!==rerouteId||acknowledgement.replacement_id!==replacementId||!['created','existing'].includes(acknowledgement.status))throw new StartRerouteError(`${kind} replacement lacks exact compare-and-create acknowledgement`)
  return {ref,reroute_id:rerouteId,replacement_id:replacementId,status:acknowledgement.status}
}

export const reserveReviewerReroute=(assignment,decision,replacement,io)=>reserveAndDispatch('reviewer',assignment,decision,replacement,io)
export const reserveRunnerReroute=(attempt,decision,replacement,io)=>reserveAndDispatch('runner',attempt,decision,replacement,io)

export function acceptRunnerResult(result,originalAttempt,io){
  if(!result?.attempt_id||!result?.supersedes_attempt_id||!result?.reroute_id||!result?.workflow||!result?.lane||!SHA.test(String(result.head_sha??''))||!Array.isArray(result.assertions)||!result.assertions.length)throw new StartRerouteError('accepted runner result must contain an exact supersession identity')
  if(!originalAttempt?.id||result.supersedes_attempt_id!==originalAttempt.id||result.workflow!==originalAttempt.workflow||String(result.head_sha).toLowerCase()!==String(originalAttempt.head_sha).toLowerCase())throw new StartRerouteError('runner result does not bind the original workflow, head, and supersession')
  const required=assertions(originalAttempt.required_assertions),reported=result.assertions.map((x)=>({name:token(x?.name,'assertion name'),result:x?.result})).sort((a,b)=>a.name.localeCompare(b.name))
  if(reported.some((x)=>x.result!=='passed')||canonicalJson(reported.map((x)=>x.name))!==canonicalJson(required))throw new StartRerouteError('runner result does not pass the exact original assertion set')
  const rerouteRef=`${REROUTE_REF_PREFIX}/runner/${token(originalAttempt.id,'runner original id')}`,reserved=io.readReroute(rerouteRef)
  const reservationRecord=reserved?.record??{},reservationIdentity={...reservationRecord};delete reservationIdentity.reroute_id
  if(!reserved||reserved.digest!==result.reroute_id||reservationRecord.reroute_id!==result.reroute_id||sha256(canonicalJson(reservationIdentity))!==result.reroute_id||reservationRecord.replacement_id!==result.attempt_id||reservationRecord.original_id!==originalAttempt.id||reservationRecord.workflow!==originalAttempt.workflow||reservationRecord.lane!==result.lane||reservationRecord.head_sha!==String(originalAttempt.head_sha).toLowerCase()||canonicalJson(reservationRecord.required_assertions)!==canonicalJson(required))throw new StartRerouteError('runner result is not bound to the immutable reroute reservation')
  const resultIdentity={attempt_id:result.attempt_id,supersedes_attempt_id:result.supersedes_attempt_id,reroute_id:result.reroute_id,workflow:result.workflow,lane:result.lane,head_sha:String(result.head_sha).toLowerCase(),assertions:reported}
  if(!DIGEST.test(String(result.result_digest??''))||result.result_digest!==sha256(canonicalJson(resultIdentity)))throw new StartRerouteError('runner result requires its exact canonical digest')
  const ref=`refs/db-runner-accepted/${token(result.workflow,'workflow')}/${String(result.head_sha).toLowerCase()}`,digest=result.result_digest
  if(!io.createAccepted(ref,digest,result)){const prior=io.readAccepted(ref);if(prior?.digest!==digest)throw new StartRerouteError('another runner result was already accepted for this workflow and head')}
  return {accepted:true,ref,digest}
}
