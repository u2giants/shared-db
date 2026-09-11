import { median } from '../throughput-guard/ledger-lib.mjs'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export class AcceptanceReportError extends Error {}

export const ACCEPTANCE_PHASES=Object.freeze([
  ['request_to_dispatch','entered','dispatched'],
  ['dispatch_to_implementation','dispatched','implementation_complete'],
  ['implementation_to_review','implementation_complete','review_ready'],
  ['review_ci_wait','review_ready','preview_verified'],
  ['merge','preview_verified','merged'],
  ['production_decision_wait','merged','production_authorized'],
  ['production_apply','production_authorized','production_applied'],
  ['live_verification','production_applied','live_verified'],
])

const minutes=(start,end)=>{const value=(Date.parse(end)-Date.parse(start))/60000;if(!Number.isFinite(value)||value<0)throw new AcceptanceReportError('outcome timestamps must be chronological ISO instants');return value}

export function buildFiveOutcomeAcceptanceReport({outcomes,baseline,refusal_evidence=[]}){
  if(!Array.isArray(outcomes)||outcomes.length!==5)throw new AcceptanceReportError('exactly five consecutive outcomes are required')
  if(!Number.isInteger(baseline?.n)||baseline.n<1||!Number.isFinite(baseline?.median_request_to_live_minutes)||baseline.median_request_to_live_minutes<=0)throw new AcceptanceReportError('raw baseline n and positive median are required')
  const numbers=outcomes.map((row)=>row.sequence)
  if(numbers.some((value,index)=>!Number.isInteger(value)||(index&&value!==numbers[index-1]+1)))throw new AcceptanceReportError('outcome sequence is not consecutive')
  const rows=outcomes.map((row)=>{
    if(row.work_type!=='structural'||!['urgent-application','standard-application'].includes(row.service_class))throw new AcceptanceReportError(`outcome #${row.issue} is not an admitted structural service outcome`)
    if(row.unchanged_poll_count!==0||row.manual_reconstruction_count!==0)throw new AcceptanceReportError(`outcome #${row.issue} used unchanged polling or manual queue reconstruction`)
    const events=(row.events??[]).filter((event)=>event.work_issue===row.issue&&event.result!=='refused')
    const requiredTypes=['entered',...ACCEPTANCE_PHASES.map(([, ,to])=>to)]
    if(events.length!==requiredTypes.length||requiredTypes.some((type,index)=>events[index]?.event_type!==type))throw new AcceptanceReportError(`outcome #${row.issue} lifecycle is duplicated, incomplete, or out of order`)
    const byType=new Map(events.map((event)=>[event.event_type,event]))
    const phases={}
    for(const [name,from,to] of ACCEPTANCE_PHASES){if(!byType.has(from)||!byType.has(to))throw new AcceptanceReportError(`outcome #${row.issue} is missing ${from} or ${to}`);phases[name]=minutes(byType.get(from).timestamp,byType.get(to).timestamp)}
    const requestToLive=minutes(byType.get('entered').timestamp,byType.get('live_verified').timestamp)
    const dispatchTarget=row.service_class==='urgent-application'?10:60
    if(phases.request_to_dispatch>dispatchTarget)throw new AcceptanceReportError(`outcome #${row.issue} missed its ${dispatchTarget}-minute dispatch target`)
    const waits={owner:0,external:0}
    for(const wait of row.waits??[]){if(!['owner','external'].includes(wait.kind))throw new AcceptanceReportError(`outcome #${row.issue} has an unknown wait kind`);waits[wait.kind]+=minutes(wait.started_at,wait.ended_at)}
    return{sequence:row.sequence,issue:row.issue,service_class:row.service_class,state:'live_verified',phase_minutes:phases,wait_minutes:waits,request_to_live_minutes:requestToLive,exceptions:[...(row.exceptions??[])]}
  })
  if(!Array.isArray(refusal_evidence)||!refusal_evidence.length||refusal_evidence.some((row)=>row?.result!=='refused'||typeof row?.evidence!=='string'||!row.evidence.trim()))throw new AcceptanceReportError('durable refusal-preservation evidence is required')
  const currentMedian=median(rows.map((row)=>row.request_to_live_minutes)),improvement=(baseline.median_request_to_live_minutes-currentMedian)/baseline.median_request_to_live_minutes
  if(improvement<0.5)throw new AcceptanceReportError(`median request-to-live improvement is ${(improvement*100).toFixed(1)}%, below 50%`)
  return{schema_version:1,status:'accepted',sample:{n:rows.length,consecutive_from:numbers[0],consecutive_to:numbers.at(-1)},baseline:{n:baseline.n,median_request_to_live_minutes:baseline.median_request_to_live_minutes},current:{n:rows.length,median_request_to_live_minutes:currentMedian,improvement_percent:Number((improvement*100).toFixed(1))},outcomes:rows,refusal_evidence,exceptions:rows.flatMap((row)=>row.exceptions.map((value)=>({issue:row.issue,detail:value})))}
}

export function main(argv){const index=argv.indexOf('--input');if(index<0||!argv[index+1]){console.error('REFUSED: --input <five-outcome.json> is required');return 2}try{console.log(JSON.stringify(buildFiveOutcomeAcceptanceReport(JSON.parse(readFileSync(argv[index+1],'utf8'))),null,2));return 0}catch(error){console.error(`REFUSED: ${error.message}`);return 2}}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))process.exitCode=main(process.argv.slice(2))
