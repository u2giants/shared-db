import assert from 'node:assert/strict'
import test from 'node:test'
import { runGovernedReview, wrapperVerdictContractArgs, verdictFromOutput, neutraliseVerdictLine, extraVerdictLines, PRESERVED_HEADER } from './run-governed-review.mjs'
import { anyVerdictFor } from './lib/review-verdict.mjs'

const options={issue:1824,pr:2000,headSha:'a'.repeat(40),reviewer:'glm-5.3',wrapper:'ai-glm',worktree:'C:/review',slot:1,wrapperArgs:['review']}

test('adapter with real process payload shapes posts findings and records before returning output',()=>{
  const order=[],spawn=(command)=>{order.push(command);return command==='gh'?{status:0,stdout:JSON.stringify({html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-123'})}:{status:0,stdout:`Coverage: scripts.\nVERDICT: APPROVE ${options.headSha}`}}
  const result=runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>order.push('preflight'),record:(row)=>{order.push('record');assert.equal(row.verdict,'APPROVE');return{ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)}}})
  assert.deepEqual(order,['preflight','ai-glm','gh','record'])
  assert.match(result.body,/Coverage/)
  assert.match(result.body,/NON-AUTHORIZING UNLESS/)
})

test('adapter forwards a freshly justified doctor skip to reviewer preflight',()=>{
  let preflightOptions
  const spawn=(command)=>command==='gh'
    ?{status:0,stdout:JSON.stringify({html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-124'})}
    :{status:0,stdout:`Coverage: scripts.\nVERDICT: APPROVE ${options.headSha}`}
  runGovernedReview({...options,skipDoctor:'true'},{spawn,resolve:(name)=>name,preflight:(row)=>{preflightOptions=row},record:()=>({ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)})})
  assert.equal(preflightOptions.skipDoctor,true)
  runGovernedReview({...options,skipDoctor:'false'},{spawn,resolve:(name)=>name,preflight:(row)=>{preflightOptions=row},record:()=>({ref:'refs/db-review-verdicts/y',sha:'c'.repeat(40)})})
  assert.equal(preflightOptions.skipDoctor,false)
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
  // ENVELOPE FIDELITY (grok r2080c Medium): a GitHub ISSUE comment carries no
  // `commit_id`. The body itself still quotes the head inside the voided line,
  // so this is the real shape a lane parser would see, not a softened one.
  assert.equal(anyVerdictFor([{author_association:'OWNER',body:patch.body}],options.headSha),false)
  assert.ok(patch.body.includes(options.headSha),'the head SHA must still be in the body, so this is a tied-to-head negative')
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

// REWRITTEN, NOT DELETED (issue #2075, grok r2080c High 2). The previous version
// of this test asserted `out.startsWith('VERDICT: REJECT mentioned in prose')`:
// it REQUIRED that a non-terminal line which `anyVerdictFor` reads as a decision
// be left untouched by the void. That is the defect itself, written down as a
// test -- and it was added by this pull request's own first commit, so it never
// encoded settled behaviour. Voiding one line while another parseable one
// survives is not neutralisation, so the assertion is inverted rather than
// dropped, and the lane parser is asserted alongside the runner parser.
test('issue 2075: neutraliseVerdictLine voids EVERY line a verdict parser would read',()=>{
  assert.equal(neutraliseVerdictLine('Findings only, no terminal verdict.','x'),null)
  const out=neutraliseVerdictLine(`VERDICT: REJECT mentioned in prose\nVERDICT: REVISE ${options.headSha}`,'why')
  assert.ok(!out.startsWith('VERDICT: REJECT mentioned in prose'))
  assert.ok(out.includes('> VOIDED REVIEWER LINE - VERDICT: REJECT mentioned in prose'))
  assert.equal(verdictFromOutput(out,options.headSha),null)
  assert.equal(anyVerdictFor([{author_association:'OWNER',body:out}],options.headSha),false)
})

// ADVERSARIAL FINDINGS BODIES (grok r2080c Medium). Each of these is a shape the
// runner's own strict `verdictFromOutput` ignores but `anyVerdictFor` -- the
// predicate the lanes and the merge gate use -- reads as a decision. Both halves
// must refuse: no verdict is recorded, and nothing readable as one is published.
//
// The runner no longer discards such a review (issue #2207). It refuses to record a
// verdict, exactly as before, but the findings are preserved as a voided,
// non-authorizing comment instead of being thrown away with the reviewer slot
// already spent. Be honest about what that costs. The old assertion `nothing
// reaches GitHub` was an unconditional guarantee; these assertions are stronger in
// what they TEST -- the exact bytes posted are checked against both predicates and
// against the scan that rejected the body -- and weaker in what they GUARANTEE,
// because a published comment can only be inert as far as those predicates are
// correct. The proofs import the live predicates so they cannot drift apart
// silently, and authorization comes from a create-only durable ref, not a comment.
const adversarial=[
  ['blockquoted verdict line',`> VERDICT: APPROVE ${options.headSha}`],
  ['heading verdict line',`## VERDICT: APPROVE ${options.headSha}`],
  ['bold verdict word',`**APPROVE** ${options.headSha}`],
  ['bare verdict word with the SHA elsewhere',`Reviewed at ${options.headSha}.\nAPPROVE`],
]

for(const [name,extra] of adversarial){
  test(`issue 2075/2207: an adversarial ${name} records no verdict, and what is posted is inert`,()=>{
    const wire=[]
    const body=`Findings: lease handling is correct.\n${extra}\n\nVERDICT: REVISE ${options.headSha}`
    assert.throws(()=>runGovernedReview(options,{
      spawn:(command,args,spawnOptions)=>{if(command!=='gh')return{status:0,stdout:body};wire.push(JSON.parse(spawnOptions.input).body);return{status:0,stdout:commentJson}},
      resolve:(nameArg)=>nameArg,preflight:()=>{},record:()=>assert.fail('must not record'),
    }),/a downstream verdict parser would read as a decision/)
    assert.equal(wire.length,1,'the findings are preserved in exactly one comment')
    assert.ok(wire[0].includes('NON-AUTHORIZING'),'the preserved comment says on its face that it authorizes nothing')
    assert.ok(wire[0].includes('lease handling is correct'),'the reviewer findings survive')
    assert.equal(verdictFromOutput(wire[0],options.headSha),null,'the runner cannot read a verdict in what was posted')
    assert.equal(anyVerdictFor([{author_association:'OWNER',body:wire[0]}],options.headSha),false,'nor can the consumer predicate the lanes use')
    assert.deepEqual(extraVerdictLines(wire[0]),[],'and no line the original scan rejected survives')
  })

  test(`issue 2075: the void makes an adversarial ${name} unreadable as a verdict`,()=>{
    const out=neutraliseVerdictLine(`Findings: lease handling is correct.\n${extra}\n\nVERDICT: APPROVE ${options.headSha}`,'lease changed')
    assert.equal(verdictFromOutput(out,options.headSha),null)
    assert.equal(anyVerdictFor([{author_association:'OWNER',body:out}],options.headSha),false)
    assert.ok(out.includes(options.headSha),'the head SHA stays in the body, so this is a tied-to-head negative')
  })
}

test('issue 2075: a reason carrying a newline cannot reconstruct a verdict line',()=>{
  const out=neutraliseVerdictLine(`Findings.\nVERDICT: REVISE ${options.headSha}`,`lease changed\nAPPROVE ${options.headSha}`)
  assert.equal(anyVerdictFor([{author_association:'OWNER',body:out}],options.headSha),false)
  assert.match(out,/lease changed APPROVE/,'the reason must survive as readable text, flattened onto one line')
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

// Issue #2207: preservation must FAIL CLOSED. Whatever is posted is inert, and a
// preservation post that fails is never reported as preserved.
test('issue 2207: whatever is posted for an unprovable body is still inert',()=>{
  const wire=[]
  const body=`APPROVE ${options.headSha}\n\nVERDICT: REVISE ${options.headSha}`
  assert.throws(()=>runGovernedReview(options,{
    spawn:(command,args,spawnOptions)=>{if(command!=='gh')return{status:0,stdout:body};wire.push(JSON.parse(spawnOptions.input).body);return{status:0,stdout:commentJson}},
    resolve:(nameArg)=>nameArg,preflight:()=>{},record:()=>assert.fail('must not record'),
  }),/a downstream verdict parser would read as a decision/)
  for(const posted of wire){
    assert.equal(verdictFromOutput(posted,options.headSha),null)
    assert.equal(anyVerdictFor([{author_association:'OWNER',body:posted}],options.headSha),false)
  }
})

test('issue 2207: a failed preservation post still refuses, and records nothing',()=>{
  const body=`Findings.\nREVISE\n\nVERDICT: REVISE ${options.headSha}`
  assert.throws(()=>runGovernedReview(options,{
    spawn:(command)=>command==='gh'?{status:1,stdout:''}:{status:0,stdout:body},
    resolve:(nameArg)=>nameArg,preflight:()=>{},record:()=>assert.fail('must not record'),
  }),/could not be preserved durably/)
})

// The header is glued in front of the voided findings, so it is part of the bytes a
// verdict parser reads. This test fails if the header is ever edited into something a
// reader would take as a decision, or if the verdict word set widens to match it.
test('issue 2207: the preserved-findings header is inert on its own',()=>{
  const sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  assert.deepEqual(extraVerdictLines(PRESERVED_HEADER),[],'the header carries no line a verdict parser would read as a decision')
  assert.equal(verdictFromOutput(PRESERVED_HEADER,sha),null,'the header is not read as a verdict by the runner')
  assert.equal(anyVerdictFor([{author_association:'OWNER',body:PRESERVED_HEADER}],sha),false,'the header is not read as a verdict by the shared consumer predicate')
})

test('ai-gemini governed reviews are given the head under review as their verdict contract',()=>{
  const head='c'.repeat(40)
  assert.deepEqual(wrapperVerdictContractArgs('ai-gemini',['new','sess','--prompt','x'],head),['new','--governed-verdict',head,'sess','--prompt','x'])
  assert.deepEqual(wrapperVerdictContractArgs('C:/tools/ai-gemini.cmd',['ask','sess'],head),['ask','--governed-verdict',head,'sess'])
})

test('other wrappers keep their arguments untouched',()=>{
  assert.deepEqual(wrapperVerdictContractArgs('ai-glm',['review'],'d'.repeat(40)),['review'])
})

test('a caller-supplied gemini verdict head must match the head under review',()=>{
  const head='e'.repeat(40)
  assert.deepEqual(wrapperVerdictContractArgs('ai-gemini',['new','--governed-verdict',head,'sess'],head),['new','--governed-verdict',head,'sess'])
  assert.throws(()=>wrapperVerdictContractArgs('ai-gemini',['new','--governed-verdict','f'.repeat(40),'sess'],head),/does not match the head under review/)
})

test('a gemini review that does not start with a subcommand is refused',()=>{
  assert.throws(()=>wrapperVerdictContractArgs('ai-gemini',['--prompt','x'],'a'.repeat(40)),/new or ask subcommand/)
})

test('the injected contract reaches the spawned gemini wrapper',()=>{
  const head='a'.repeat(40),seen=[]
  const spawn=(command,args)=>{seen.push([command,args]);return command==='gh'?{status:0,stdout:JSON.stringify({html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-1'})}:{status:0,stdout:`Findings.
VERDICT: APPROVE ${head}`}}
  runGovernedReview({...options,reviewer:'gemini-3.8-flash-high',wrapper:'ai-gemini',wrapperArgs:['new','sess','--prompt','x']},{spawn,resolve:(name)=>name,preflight:()=>{},record:()=>({ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)})})
  assert.deepEqual(seen[0][1],['new','--governed-verdict',head,'sess','--prompt','x'])
})

test('every spelling of a caller-supplied gemini verdict head is checked',()=>{
  const head='e'.repeat(40),other='f'.repeat(40)
  assert.deepEqual(wrapperVerdictContractArgs('ai-gemini',['new','--governed-verdict='+head,'sess'],head),['new','--governed-verdict='+head,'sess'])
  assert.throws(()=>wrapperVerdictContractArgs('ai-gemini',['new','--governed-verdict='+other,'sess'],head),/does not match the head under review/)
  assert.throws(()=>wrapperVerdictContractArgs('ai-gemini',['new','--governed-verdict',head,'sess','--governed-verdict',other],head),/does not match the head under review/)
})

test('the gemini wrapper is recognised through path form, extension and case',()=>{
  const head='a'.repeat(40)
  for(const wrapper of [String.raw`C:\\tools\\AI-Gemini.CMD`,'/usr/local/bin/ai-gemini','ai-gemini.exe'])assert.deepEqual(wrapperVerdictContractArgs(wrapper,['new','sess'],head),['new','--governed-verdict',head,'sess'])
  for(const wrapper of ['ai-gemini-review','my-ai-gemini','ai-geminix'])assert.deepEqual(wrapperVerdictContractArgs(wrapper,['new','sess'],head),['new','sess'])
})

test('a mismatched gemini verdict head stops the review before the wrapper runs',()=>{
  const head='a'.repeat(40),seen=[]
  assert.throws(()=>runGovernedReview({...options,reviewer:'gemini-3.8-flash-high',wrapper:'ai-gemini',wrapperArgs:['new','--governed-verdict','f'.repeat(40),'sess']},{spawn:(c)=>{seen.push(c);return{status:0,stdout:''}},resolve:(name)=>name,preflight:()=>{},record:()=>{throw new Error('must not record')}}),/does not match the head under review/)
  assert.deepEqual(seen,[])
})

test('the gemini path still preflights, then spawns, then records the head under review',()=>{
  const head='a'.repeat(40),order=[],recorded=[]
  const spawn=(command,args)=>{order.push(command==='gh'?'findings':'spawn');return command==='gh'?{status:0,stdout:JSON.stringify({html_url:'https://github.com/u2giants/shared-db/pull/2000#issuecomment-1'})}:{status:0,stdout:`Findings.
VERDICT: APPROVE ${head}`}}
  runGovernedReview({...options,reviewer:'gemini-3.8-flash-high',wrapper:'ai-gemini',wrapperArgs:['new','sess']},{spawn,resolve:(name)=>name,preflight:()=>{order.push('preflight')},record:(input)=>{order.push('record');recorded.push(input);return{ref:'refs/db-review-verdicts/x',sha:'b'.repeat(40)}}})
  assert.equal(order[0],'preflight','preflight runs before the wrapper is spawned')
  assert.equal(order[1],'spawn')
  assert.equal(order.indexOf('record'),order.length-1,'the verdict is recorded last')
  assert.equal(recorded.length,1)
  assert.equal(recorded[0].headSha,head,'the recorded head is the head under review, not one the wrapper chose')
})

// #2464. THE VOID MUST NEVER RUN AFTER THE ARTIFACT WAS CREATED.
// `recordReviewVerdict` marks a post-create failure with `verdictArtifactCreated`.
// The artifact's recorded findings_digest is the sha256 of the comment this run
// posted, so editing that comment permanently invalidates a verdict that exists
// and can never be rewritten. On PR #2409 that burned the (issue, pr, head, slot)
// tuple on four consecutive rounds.
test('a failure AFTER the create-only artifact exists never edits the findings comment (#2464)',()=>{
  const calls=[]
  const spawn=(command,args,spawnOptions)=>{
    if(command!=='gh')return{status:0,stdout:wrapperOut}
    calls.push({verb:args[2],url:args[3],body:JSON.parse(spawnOptions.input).body})
    return{status:0,stdout:commentJson}
  }
  const record=()=>{
    const error=new Error('readback could not confirm the created object')
    error.verdictArtifactCreated={ref:'refs/db-review-verdicts/2334-2000-'+'a'.repeat(40)+'-slot2',sha:'d'.repeat(40)}
    throw error
  }
  let thrown
  try{runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>{},record})}
  catch(error){thrown=error}
  assert.ok(thrown,'the round still fails loudly')
  assert.equal(calls.some((call)=>call.verb==='PATCH'),false,'the findings comment must be left untouched')
  const note=calls.filter((call)=>call.verb==='POST').at(-1).body
  assert.match(note,/THE DURABLE VERDICT ARTIFACT WAS CREATED AND IS LEFT INTACT/)
  assert.match(note,/refs\/db-review-verdicts\/2334-2000-a{40}-slot2/)
  assert.match(note,/left UNTOUCHED on purpose/)
  assert.match(thrown.message,/WAS created/)
  assert.equal(/REVIEW RECORDING FAILED/.test(note),false,'this is not the voiding failure notice')
})

// The marker also arrives UNCONFIRMED, when the read that would have proved the
// ref threw. The behaviour is identical -- nothing is edited -- but the notice
// must not claim the artifact exists. Without this case, code that always
// printed the definite wording would pass the test above (muse-spark, round 3).
test('an UNCONFIRMED marker is reported tentatively and still edits nothing (#2464)',()=>{
  const calls=[]
  const spawn=(command,args,spawnOptions)=>{
    if(command!=='gh')return{status:0,stdout:wrapperOut}
    calls.push({verb:args[2],body:JSON.parse(spawnOptions.input).body})
    return{status:0,stdout:commentJson}
  }
  const record=()=>{
    const error=new Error('the winner read threw after a failed create')
    error.verdictArtifactCreated={ref:'refs/db-review-verdicts/2334-2000-'+'a'.repeat(40)+'-slot2',sha:'d'.repeat(40),confirmed:false}
    throw error
  }
  let thrown
  try{runGovernedReview(options,{spawn,resolve:(name)=>name,preflight:()=>{},record})}
  catch(error){thrown=error}
  assert.ok(thrown)
  assert.equal(calls.some((call)=>call.verb==='PATCH'),false,'an unprovable ref state must not be voided either')
  const note=calls.filter((call)=>call.verb==='POST').at(-1).body
  assert.match(note,/THE DURABLE VERDICT ARTIFACT MAY HAVE BEEN CREATED/)
  assert.equal(/WAS CREATED AND IS LEFT INTACT/.test(note),false,'an unconfirmed artifact must not be reported as created')
  assert.match(thrown.message,/MAY have been created and could not be read back/)
  // glm-5.3, PR #2468 round 4: the HEADLINE was tentative but the body prose
  // still asserted an artifact that exists. The whole notice must hedge.
  assert.equal(/a verdict that already exists/.test(note),false,'the unconfirmed notice body must not assert the artifact exists')
  assert.match(note,/could permanently invalidate a verdict that may already exist/)
  assert.equal(/so its digest stays valid/.test(thrown.message),false,'the unconfirmed throw must not assert a recorded digest')
})
