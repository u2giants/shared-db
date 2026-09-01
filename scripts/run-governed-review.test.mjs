import assert from 'node:assert/strict'
import test from 'node:test'
import { runGovernedReview, verdictFromOutput, neutraliseVerdictLine } from './run-governed-review.mjs'
import { anyVerdictFor } from './lib/review-verdict.mjs'

const options={issue:1824,pr:2000,headSha:'a'.repeat(40),reviewer:'glm-5.3',wrapper:'ai-glm',worktree:'C:/review',slot:1,wrapperArgs:['review']}

test('adapter with real process payload shapes posts findings and records before returning output',()=>{
  const order=[],spawn=(command)=>{order.push(command);return command==='gh'?{status:0,stdout:JSON.stringify({html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-123'})}:{status:0,stdout:`Coverage: scripts.\nVERDICT: APPROVE ${options.headSha}`}}
  const result=runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>order.push('preflight'),record:(row)=>{order.push('record');assert.equal(row.verdict,'APPROVE');return{ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)}}})
  assert.deepEqual(order,['preflight','ai-glm','gh','record'])
  assert.match(result.body,/Coverage/)
  assert.match(result.body,/NON-AUTHORIZING UNLESS/)
})

test('recording failure leaves an explicit durable non-authorizing notice',()=>{
  const posts=[]
  const spawn=(command,args,spawnOptions)=>{if(command!=='gh')return{status:0,stdout:`VERDICT: APPROVE ${options.headSha}`};if(args[2]==='POST')posts.push(JSON.parse(spawnOptions.input).body);return{status:0,stdout:JSON.stringify({id:123,html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-123'})}}
  assert.throws(()=>runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>{},record:()=>{throw new Error('lease changed')}}),/lease changed/)
  assert.match(posts[0],/NON-AUTHORIZING UNLESS/)
  assert.match(posts[1],/REVIEW RECORDING FAILED/)
})

const findingsText='Coverage: scripts. The lease ref is stale and must be reissued.'
const wrapperOut=`${findingsText}\nVERDICT: APPROVE ${options.headSha}`
const commentJson=JSON.stringify({id:987654,html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-987654'})

function recordingFailureRun({patchFails=false}={}){
  const calls=[]
  const spawn=(command,args,spawnOptions)=>{
    if(command!=='gh')return{status:0,stdout:wrapperOut}
    const verb=args[2]
    calls.push({verb,url:args[3],body:JSON.parse(spawnOptions.input).body})
    if(verb==='PATCH')return patchFails?{status:1,stdout:'',stderr:'gh: 403'}:{status:0,stdout:commentJson}
    return{status:0,stdout:commentJson}
  }
  let thrown
  try{runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>{},record:()=>{throw new Error('lease changed')}})}
  catch(error){thrown=error}
  return{calls,thrown}
}

test('issue 2075: recording failure voids the posted findings comment so the orphan line is no longer a verdict',()=>{
  const{calls,thrown}=recordingFailureRun()
  assert.match(thrown.message,/lease changed/)
  const patch=calls.find((call)=>call.verb==='PATCH')
  assert.ok(patch,'the findings comment must be edited on the recording-failure path')
  assert.equal(patch.url,'repos/u2giants/shared-db/issues/comments/987654')
  assert.equal(verdictFromOutput(patch.body,options.headSha),null)
  assert.equal(anyVerdictFor([{author_association:'OWNER',body:patch.body,commit_id:options.headSha}],options.headSha),false)
})

test("issue 2075: voiding the verdict line preserves the reviewer's findings",()=>{
  const{calls}=recordingFailureRun()
  const patch=calls.find((call)=>call.verb==='PATCH')
  assert.ok(patch.body.includes(findingsText),'reviewer analysis must survive the neutralising edit')
  assert.match(patch.body,/VERDICT LINE VOIDED/)
  assert.match(patch.body,/lease changed/)
})

test('issue 2075: a failed voiding edit is announced loudly and the command still refuses',()=>{
  const{calls,thrown}=recordingFailureRun({patchFails:true})
  const follow=calls.filter((call)=>call.verb==='POST').at(-1).body
  assert.match(follow,/REVIEW RECORDING FAILED/)
  assert.match(follow,/STILL LIVE ON COMMENT 987654/)
  assert.match(follow,/BY HAND/)
  assert.match(thrown.message,/still live on comment 987654/)
})

test('issue 2075: the success path posts and records with no edit call',()=>{
  const calls=[]
  const spawn=(command,args)=>{if(command!=='gh')return{status:0,stdout:wrapperOut};calls.push(args[2]);return{status:0,stdout:commentJson}}
  const result=runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>{},record:()=>({ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)})})
  assert.deepEqual(calls,['POST'])
  assert.match(result.body,/VERDICT: APPROVE/)
})

test('issue 2075: neutraliseVerdictLine touches only the terminal verdict line',()=>{
  assert.equal(neutraliseVerdictLine('Findings only, no terminal verdict.','x'),null)
  const out=neutraliseVerdictLine(`VERDICT: REJECT mentioned in prose\nVERDICT: REVISE ${options.headSha}`,'why')
  assert.ok(out.startsWith('VERDICT: REJECT mentioned in prose'))
  assert.equal(verdictFromOutput(out,options.headSha),null)
})

test('honest review output without a verdict artifact path is refused',()=>{
  assert.throws(()=>runGovernedReview(options,{spawn:()=>({status:0,stdout:'I reviewed every file and found no issues.'}),resolve:(name)=>name,preflight:()=>{},record:()=>assert.fail('must not record')}),/did not produce/)
})
test('wrapper refusal forms remain terminal verdicts, not transport failures',()=>{
  assert.equal(verdictFromOutput(`VERDICT: REVISE ${options.headSha}`,options.headSha),'REVISE')
  assert.equal(verdictFromOutput(`VERDICT: REJECT ${options.headSha}`,options.headSha),'REJECT')
  assert.equal(verdictFromOutput(`VERDICT: APPROVE ${options.headSha}\nVERDICT: REJECT ${options.headSha}`,options.headSha),null)
  assert.equal(verdictFromOutput(`VERDICT: APPROVE ${'b'.repeat(40)}`,options.headSha),null)
})
