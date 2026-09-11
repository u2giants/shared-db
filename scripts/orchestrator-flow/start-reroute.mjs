export class StartRerouteError extends Error {}
export const START_SLO_MS=10*60*1000
const SHA=/^[0-9a-f]{40}$/i
function ms(value){const n=Date.parse(value);if(Number.isNaN(n))throw new StartRerouteError('timestamp is unreadable');return n}

export function reviewerStartDecision(assignment,{now,provider_state,lifecycle=[],replacement_exists=false}){
  if(!assignment?.id||!SHA.test(String(assignment.head_sha??'')))throw new StartRerouteError('exact assignment and head are required')
  const events=lifecycle.filter((e)=>e.assignment_id===assignment.id),started=events.find((e)=>['provider_launched','provider_contacted','review_started'].includes(e.type))
  if(started)return {action:'keep-active',started_at:started.at,source:'durable-lifecycle'}
  if(events.some((e)=>e.type==='terminal_format_invalid'))return {action:'same-session-clarification'}
  const overdue=ms(now)-ms(assignment.assigned_at)>=START_SLO_MS
  if(!overdue&&provider_state==='usable')return {action:'wait'}
  if(provider_state==='remote-unknown')throw new StartRerouteError('paid review start is uncertain; preserve the lease and refuse replacement')
  if(!['unusable','quarantined','confirmed-not-started'].includes(provider_state))throw new StartRerouteError('reviewer start state is not authoritative')
  if(replacement_exists)throw new StartRerouteError('replacement already exists; reroute is exactly once')
  return {action:'governed-return-and-reroute',reason:provider_state}
}

export function runnerStartDecision(attempt,{now,lifecycle=[],qualified_lanes=[],replacement_exists=false}){
  if(!attempt?.id||!attempt.workflow||!attempt.lane||!SHA.test(String(attempt.head_sha??''))||!Array.isArray(attempt.required_assertions)||!attempt.required_assertions.length)throw new StartRerouteError('runner attempt requires exact workflow, lane, head, and assertions')
  const events=lifecycle.filter((e)=>e.attempt_id===attempt.id),started=events.find((e)=>e.type==='runner_started')
  if(started)return {action:'keep-active',started_at:started.at}
  if(ms(now)-ms(attempt.queued_at)<START_SLO_MS)return {action:'wait'}
  if(replacement_exists)throw new StartRerouteError('runner replacement already exists; reroute is exactly once')
  const lane=qualified_lanes.find((x)=>x.name!==attempt.lane&&x.qualified===true&&x.assertions?.length===attempt.required_assertions.length&&attempt.required_assertions.every((a)=>x.assertions.includes(a)))
  if(!lane)throw new StartRerouteError('no independent qualified runner lane preserves every assertion')
  return {action:'dispatch-new-run',lane:lane.name,supersedes:attempt.id,head_sha:attempt.head_sha,required_assertions:[...attempt.required_assertions]}
}

export function acceptRunnerResult(result,io){
  if(!result?.attempt_id||!result?.head_sha||result.assertions?.some((x)=>x.result!=='passed')||!result.assertions?.length)throw new StartRerouteError('accepted runner result must contain passing assertions')
  const ref=`refs/db-runner-accepted/${result.workflow}/${result.head_sha}`,digest=result.result_digest
  if(!/^[0-9a-f]{64}$/i.test(String(digest??'')))throw new StartRerouteError('runner result requires exact digest')
  if(!io.createAccepted(ref,digest,result)){const prior=io.readAccepted(ref);if(prior?.digest!==digest)throw new StartRerouteError('another runner result was already accepted for this workflow and head')}
  return {accepted:true,ref,digest}
}
