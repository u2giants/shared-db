import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluateAdmission, parseImpactBlock, STRUCTURAL_CHANGE_TYPES, NON_STRUCTURAL_CHANGE_TYPES, assertPrCarriesStructuralChange } from './admission.mjs'
import { advanceOutcome, completeOutcome, outcomeEvent, outcomeHistory, OUTCOME_STATES } from './outcome-lifecycle.mjs'
import { formatEventComment, parseEventComment } from '../db-coordination-events.mjs'
import { admitIssue, buildDynamicQueues, claimBody, main as managerMain, matchesGeneratedTypesProof, matchesLiveProof, parseQueueScope, resolveAdmittedIssueForPr } from '../manage-migration-author-lanes.mjs'
import { findCompletionRecord } from '../lib/work-dependencies.mjs'

const issue = (body, number = 41) => ({ number, state: 'open', title: 'structural outcome', body, createdAt: '2026-09-11T00:00:00Z' })
const scopeBody = ({ service='standard-application', change='migration', stage='entered', object='table core.example', returnTo='u2giants/example-app', live='authenticated create-and-read succeeds', generated='not-applicable', extra='' } = {}) => [
  '```db-work-scope', 'status: ready', 'work_type: structural', 'route: shared-db-orchestrator',
  `service_class: ${service}`, `change_type: ${change}`, `application_return_to: ${returnTo}`,
  `live_assertion: ${live}`, `generated_types: ${generated}`, `outcome_stage: ${stage}`,
  'priority: 5', 'depends_on:', 'writes:', `  - ${object}`, '```', extra,
].join('\n')
const impact = (kind) => ['```db-impact', JSON.stringify({ kind, environment:'production', evidence:'https://github.com/u2giants/example-app/issues/1' }), '```'].join('\n')

test('every structural actual-change type is independently admissible', () => {
  for (const change of STRUCTURAL_CHANGE_TYPES) {
    const row=issue(scopeBody({change}));const parsed=parseQueueScope(row.body)
    assert.equal(evaluateAdmission(row,parsed,null).admitted,true,change)
  }
})

test('sender structural labels cannot disguise any named non-structural actual change', () => {
  for (const change of NON_STRUCTURAL_CHANGE_TYPES) {
    const row=issue(scopeBody({change}));const parsed=parseQueueScope(row.body)
    assert.throws(()=>evaluateAdmission(row,parsed,null),/does not change database structure/,change)
  }
})

test('all four urgent impacts qualify only with environment, evidence, and application return address', () => {
  for (const kind of ['live-outage','blocked-release','security-exposure','owner-deadline']) {
    const row=issue(scopeBody({service:'urgent-application',extra:impact(kind)}));const parsed=parseQueueScope(row.body)
    assert.equal(evaluateAdmission(row,parsed,parseImpactBlock(row.body)).impact.kind,kind)
  }
  let row=issue(scopeBody({service:'urgent-application'}));assert.throws(()=>evaluateAdmission(row,parseQueueScope(row.body),null),/requires a db-impact/)
  row=issue(scopeBody({returnTo:''}));assert.throws(()=>evaluateAdmission(row,parseQueueScope(row.body),null),/application_return_to/)
  assert.throws(()=>parseQueueScope(scopeBody({object:''}).replace('  - \n','').replace('work_type: structural','work_type: repo-maintenance').replace('route: shared-db-orchestrator','route: repo-maintenance').replace('service_class: standard-application','service_class: urgent-application').replace('application_return_to: u2giants/example-app\n','')),/cannot self-promote/)
})

test('actual pull request files must contain a migration before reviewer or shared-stage admission', () => {
  assert.throws(()=>assertPrCarriesStructuralChange([{filename:'scripts/tool.mjs',status:'modified'}]),/no added or modified migration/)
  assert.deepEqual(assertPrCarriesStructuralChange([{filename:'supabase/migrations/20260911120000_example.sql',status:'added',content:'create table core.example(id bigint);'}]),['supabase/migrations/20260911120000_example.sql'])
  assert.throws(()=>assertPrCarriesStructuralChange([{filename:'supabase/migrations/20260911120000_example.sql',status:'added',content:'insert into core.example values (1);'}]),/actual change is not structural/)
  assert.throws(()=>assertPrCarriesStructuralChange([{filename:'supabase/migrations/20260911120000_example.sql',status:'added',content:'alter widget core.example frobnicate;'}]),/unmodelled DDL/)
  assert.throws(()=>assertPrCarriesStructuralChange([{filename:'supabase/migrations/20260911120000_example.sql',status:'modified',content:'create table core.example(id bigint);',patch:'@@ -2 +2 @@\n-old note\n+new note'}]),/actual change is not structural/)
  assert.deepEqual(assertPrCarriesStructuralChange([{filename:'supabase/migrations/20260911120000_example.sql',status:'modified',content:'create table core.example(id bigint);',patch:'@@ -2 +2 @@\n-old index\n+create index example_id_idx on core.example(id);'}]),['supabase/migrations/20260911120000_example.sql'])
})

test('finish-first queue order is service class, nearest-live stage, transitive impact, creation time, then issue', () => {
  const same=(number,service,stage,createdAt='2026-09-11T00:00:00Z')=>({...issue(scopeBody({service,stage,extra:service==='urgent-application'?impact('blocked-release'):''}),number),createdAt})
  const rows=[same(40,'maintenance','entered','2026-08-01T00:00:00Z'),same(30,'standard-application','entered','2026-09-01T00:00:00Z'),same(20,'urgent-application','entered'),same(10,'urgent-application','preview_verified')]
  const result=buildDynamicQueues(rows,[],new Date(),rows.map((row)=>row.number),null,new Map(),new Set(),new Map([[10,'preview_verified'],[20,'entered'],[30,'entered'],[40,'entered']]))
  assert.deepEqual(result.queues.find((q)=>q.queued.includes(10)).queued,[10,20,30,40])
})

test('transitive blocker impact wins, then created time and issue number break ties', () => {
  const body=(object,deps='')=>scopeBody({object}).replace('depends_on:',`depends_on:${deps}`)
  const rows=[
    {...issue(body('table core.same'),11),createdAt:'2026-09-01T00:00:00Z'},
    {...issue(body('table core.same'),10),createdAt:'2026-09-02T00:00:00Z'},
    {...issue(body('table core.same',' 10'),12),createdAt:'2026-09-03T00:00:00Z'},
    {...issue(body('table core.same',' 12'),13),createdAt:'2026-09-04T00:00:00Z'},
  ]
  const result=buildDynamicQueues(rows,[],new Date(),rows.map((row)=>row.number))
  assert.equal(result.dispatchable[0],10)
  const older=buildDynamicQueues(rows.slice(0,2).map((row,index)=>({...row,createdAt:`2026-09-0${index+1}T00:00:00Z`})),[])
  assert.equal(older.dispatchable[0],11)
})

test('unrelated structural authors can dispatch concurrently while object conflicts stay serial', () => {
  const unrelated=[issue(scopeBody({object:'table core.a'}),1),issue(scopeBody({object:'table core.b'}),2)]
  assert.deepEqual(buildDynamicQueues(unrelated,[]).dispatchable.sort((a,b)=>a-b),[1,2])
  const conflicting=[issue(scopeBody({object:'table core.a'}),1),issue(scopeBody({object:'table core.a'}),2)]
  assert.equal(buildDynamicQueues(conflicting,[]).dispatchable.length,1)
})

test('manager requires explicit admission before claim, reviewer, and shared-stage operations', () => {
  const io={enforceAdmission:true}
  const calls=[
    ['--claim','--task','x','--owner','o','--branch','b','--worktree','w','--objects','table core.x'],
    ['--assign-reviewer','--issue','41','--pr','1','--head-sha','a'.repeat(40)],
    ['--acquire-merge','--owner','o','--pr','1','--head-sha','a'.repeat(40)],
  ]
  const old=console.error;const messages=[];console.error=(m)=>messages.push(String(m))
  try { for (const args of calls) assert.equal(managerMain(args,new Date('2026-09-11T00:00:00Z'),io),2) } finally { console.error=old }
  assert.equal(messages.filter((m)=>m.includes('--admit-issue')).length,3)
})

test('production admission requires the source PR so actual SQL is rechecked',()=>{
  const io={enforceAdmission:true}
  const old=console.error;let message='';console.error=(value)=>{message=String(value)}
  try{assert.equal(managerMain(['--acquire-production','--admit-issue','41','--owner','test'],new Date(),io),2)}finally{console.error=old}
  assert.match(message,/--pr <source pull request>/)
})

test('legacy in-flight structural PRs remain executable but cannot enter as new claims',()=>{
  const legacy=issue(['```db-work-scope','status: ready','work_type: structural','route: shared-db-orchestrator','priority: 5','depends_on:','writes:','  - table core.example','```'].join('\n'))
  const io={getIssue:()=>legacy,closingIssuesForPr:()=>[{number:41,state:'open'}],getPr:()=>({head:{sha:'a'.repeat(40)}}),getPrFiles:()=>[{filename:'supabase/migrations/20260911120000_example.sql',status:'added'}],getFileAt:()=>'create table core.example(id bigint);'}
  assert.equal(admitIssue(41,io,{pr:7,allowLegacy:true}).legacy,true)
  assert.throws(()=>admitIssue(41,io),/change_type/)
})

test('a refused actual change publishes one typed refusal with return and reopening evidence', () => {
  const body=scopeBody({change:'application-code'}),comments=[]
  const io={enforceAdmission:true,getIssue:()=>issue(body),issueComments:()=>comments,commentIssue:(_n,value)=>comments.push({body:value})}
  const old=console.error;console.error=()=>{}
  try { assert.equal(managerMain(['--admit-issue','41'],new Date('2026-09-11T00:00:00Z'),io),2) } finally { console.error=old }
  const event=parseEventComment(comments[0].body)[0]
  assert.equal(event.event_type,'rejected_non_structural');assert.equal(event.result,'refused')
  assert.equal(event.return_to,'u2giants/example-app');assert.ok(event.evidence_required.length)
})

test('a data-only migration PR publishes a typed refusal instead of trusting its filename', () => {
  const comments=[]
  const io={
    enforceAdmission:true,getIssue:()=>issue(scopeBody()),issueComments:()=>comments,commentIssue:(_n,value)=>comments.push({body:value}),
    closingIssuesForPr:()=>[{number:41,state:'open'}],
    getPr:()=>({head:{sha:'a'.repeat(40)}}),getPrFiles:()=>[{filename:'supabase/migrations/20260911120000_data.sql',status:'added'}],
    getFileAt:()=>'insert into core.example values (1);',
  }
  const old=console.error;console.error=()=>{}
  try { assert.equal(managerMain(['--admit-issue','41','--pr','7'],new Date('2026-09-11T00:00:00Z'),io),2) } finally { console.error=old }
  const event=parseEventComment(comments[0].body)[0]
  assert.equal(event.event_type,'rejected_non_structural');assert.match(event.detail,/actual change is not structural/)
  assert.deepEqual(event.evidence_required,['readable pull request content containing acknowledged statement-leading schema DDL for the proposed structural change'])
})

test('repository-maintenance admission refusal cannot consume a lane or shared stage', () => {
  const body=scopeBody({change:'repository-maintenance'}),calls={claim:0,stage:0}
  const io={enforceAdmission:true,getIssue:()=>issue(body),issueComments:()=>[],commentIssue:()=>{},createIssue:()=>calls.claim++,createRef:()=>calls.stage++}
  const old=console.error;console.error=()=>{}
  try { assert.equal(managerMain(['--admit-issue','41'],new Date('2026-09-11T00:00:00Z'),io),2) } finally { console.error=old }
  assert.deepEqual(calls,{claim:0,stage:0})
})

test('legacy issues remain protected if already claimed but are never offered as new dispatches',()=>{
  const legacy=issue(['```db-work-scope','status: ready','work_type: structural','route: shared-db-orchestrator','priority: 5','depends_on:','writes:','  - table core.example','```'].join('\n'))
  const result=buildDynamicQueues([legacy],[])
  assert.deepEqual(result.dispatchable,[])
  assert.equal(result.skipped.find((row)=>row.issue===41)?.reason,'missing-required-admission-fields')
})

test('an admitted issue cannot authorize a claim for different objects',()=>{
  const comments=[];let claims=0
  const io={enforceAdmission:true,getIssue:()=>issue(scopeBody({object:'table core.authorized'})),issueComments:()=>comments,commentIssue:(_n,body)=>comments.push({body}),createClaim:()=>{claims++}}
  const old=console.error;let message='';console.error=(value)=>{message=String(value)}
  try{
    assert.equal(managerMain(['--claim','--admit-issue','41','--task','x','--owner','o','--branch','b','--worktree','w','--objects','table core.unrelated'],new Date('2026-09-11T00:00:00Z'),io),2)
  }finally{console.error=old}
  assert.match(message,/must exactly match admitted issue/);assert.equal(claims,0)
})

test('source PR resolves exactly one linked open issue and independently admits its files', () => {
  const comments=[]
  const io={
    closingIssuesForPr:()=>[{number:41,state:'open'}],getIssue:()=>issue(scopeBody()),issueComments:()=>comments,commentIssue:(_n,body)=>comments.push({body}),
    getPr:()=>({head:{sha:'a'.repeat(40)}}),getFileAt:()=> 'create table core.example(id bigint);',getPrFiles:()=>[{filename:'supabase/migrations/20260911120000_example.sql',status:'added'}],
  }
  assert.deepEqual(resolveAdmittedIssueForPr(7,io),{issue:41,pr:7,admission:'admitted'})
  io.closingIssuesForPr=()=>[{number:41,state:'open'},{number:42,state:'open'}]
  assert.throws(()=>resolveAdmittedIssueForPr(7,io),/exactly one structural work issue/)
  io.closingIssuesForPr=()=>[{number:41,state:'open'}]
  io.getFileAt=()=>'create table core.example(id bigint); create table core.undeclared(id bigint);'
  assert.throws(()=>admitIssue(41,io,{pr:7}),/structural objects must exactly match/)
  io.getFileAt=()=> 'create table core.example(id bigint);'
  io.closingIssuesForPr=()=>[{number:99,state:'open'}]
  assert.throws(()=>admitIssue(41,io,{pr:7}),/must close exactly admitted issue #41/)
})

test('a merge-closed admitted issue reopens only for a merged linked PR', () => {
  let state='closed'
  const io={
    closingIssuesForPr:()=>[{number:41,state}],getIssue:()=>({...issue(scopeBody()),state}),updateIssue:(_n,fields)=>{state=fields.state},
    getPr:()=>({head:{sha:'a'.repeat(40)},merged_at:null}),getFileAt:()=> 'create table core.example(id bigint);',getPrFiles:()=>[{filename:'supabase/migrations/20260911120000_example.sql',status:'added'}],
  }
  assert.throws(()=>admitIssue(41,io,{pr:7}),/is closed and cannot be admitted/)
  assert.equal(state,'closed')
  io.getPr=()=>({head:{sha:'a'.repeat(40)},merged_at:'2026-09-11T00:00:00Z'})
  assert.equal(admitIssue(41,io,{pr:7}).admitted,true)
  assert.equal(state,'open')
})

test('downloaded proof contents bind live assertion and generated types to exact issue, app head, and instant',()=>{
  const evidence={work_issue:41,application_commit_sha:'a'.repeat(40),live_assertion:'create works',environment:'production',verified_at:'2026-09-11T01:00:00Z',generated_types_output_digest:`sha256:${'b'.repeat(64)}`}
  const live={schema_version:1,work_issue:41,application_commit_sha:'a'.repeat(40),live_assertion:'create works',environment:'production',result:'passed',observed_at:'2026-09-11T01:00:00Z'}
  const types={schema_version:1,work_issue:41,application_commit_sha:'a'.repeat(40),result:'passed',generated_types_sha256:`sha256:${'b'.repeat(64)}`}
  assert.equal(matchesLiveProof(live,evidence),true);assert.equal(matchesGeneratedTypesProof(types,evidence),true)
  assert.equal(matchesLiveProof({...live,live_assertion:'something else'},evidence),false)
  assert.equal(matchesLiveProof({...live,observed_at:'2026-09-11T01:01:00Z'},evidence),false)
  assert.equal(matchesGeneratedTypesProof({...types,application_commit_sha:'c'.repeat(40)},evidence),false)
})

test('full capacity records urgent waiting without revoking active work', () => {
  const claims=Array.from({length:8},(_,index)=>({number:100+index,body:claimBody({version:`20260911${String(index).padStart(6,'0')}`,objects:[`table core.active_${index}`],owner:`owner-${index}`,branch:`branch-${index}`,worktree:`C:/work/${index}`,expiresAt:new Date('2026-09-12T00:00:00Z')})}))
  const urgent=issue(scopeBody({service:'urgent-application',object:'table core.active_0',extra:impact('live-outage')}),41)
  const result=buildDynamicQueues([urgent],claims,new Date('2026-09-11T01:00:00Z'))
  assert.deepEqual(result.dispatchable,[]);assert.deepEqual(result.urgentWaitingCapacity,[41])
  assert.equal(result.queues.filter((row)=>row.active).length,8)
})

const linear=OUTCOME_STATES.filter((state)=>!['blocked','yielded'].includes(state))
const eventComments=(through='production_applied',issue=41)=>linear.slice(0,linear.indexOf(through)+1).map((state,index)=>({body:formatEventComment(outcomeEvent({issue,state,actor:'test',timestamp:new Date(Date.UTC(2026,8,11,0,index)).toISOString()}))}))

test('outcome lifecycle refuses every skip and merge is not live completion', () => {
  const skipped=[eventComments('entered')[0],eventComments('review_ready').at(-1)]
  assert.equal(outcomeHistory(skipped).valid,false)
  assert.equal(outcomeHistory(eventComments('merged')).complete,false)
  assert.equal(outcomeHistory(eventComments('live_verified')).complete,true)
})

test('completion refuses lifecycle events belonging to another issue',()=>{
  const {io}=completionFixture()
  io.issueComments=()=>eventComments('production_applied',42)
  assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/not production_applied/)
})

test('blocked outcomes must yield before advancing and malformed block events invalidate history',()=>{
  const comments=eventComments('classified')
  comments.push({body:formatEventComment(outcomeEvent({issue:41,state:'blocked',actor:'test',timestamp:'2026-09-11T00:03:00Z'}))})
  assert.throws(()=>advanceOutcome({issue:41,state:'dispatched',actor:'test',timestamp:'2026-09-11T00:04:00Z'}, {issueComments:()=>comments,commentIssue:()=>{}}),/record yielded/)
  comments.push({body:formatEventComment(outcomeEvent({issue:41,state:'yielded',actor:'test',timestamp:'2026-09-11T00:04:00Z'}))})
  assert.equal(outcomeHistory(comments).valid,true)
  const stray=[...eventComments('classified'),{body:formatEventComment(outcomeEvent({issue:41,state:'yielded',actor:'test',timestamp:'2026-09-11T00:03:00Z'}))}]
  assert.deepEqual(outcomeHistory(stray).problems,['yielded without an active blocked state'])
})

test('every linear outcome transition records exactly once and every skip refuses',()=>{
  const comments=[],io={issueComments:()=>comments,commentIssue:(_n,body)=>comments.push({body})}
  linear.forEach((state,index)=>{
    assert.equal(advanceOutcome({issue:41,state,actor:'test',timestamp:new Date(Date.UTC(2026,8,11,0,index)).toISOString(),evidenceUrls:['https://github.com/u2giants/shared-db/issues/41']},io).state,state)
  })
  assert.equal(outcomeHistory(comments).complete,true)
  assert.throws(()=>advanceOutcome({issue:42,state:'review_ready',actor:'test'}, {issueComments:()=>[],commentIssue:()=>{}}),/next state is entered/)
})

function completionFixture({through='production_applied',generated='not-applicable'}={}) {
  const comments=eventComments(through), merge='a'.repeat(40), app='b'.repeat(40)
  let issueState='open'
  const evidence={schema_version:1,work_issue:41,merge_pr:7,merge_sha:merge,application_repository:'u2giants/example-app',application_commit_sha:app,live_assertion:'authenticated create-and-read succeeds',live_evidence:'https://github.com/u2giants/example-app/actions/runs/99',live_artifact_id:123,live_artifact_digest:`sha256:${'c'.repeat(64)}`,environment:'production',verified_at:'2026-09-11T01:00:00Z',...(generated==='required'?{generated_types_evidence:'https://github.com/u2giants/example-app/actions/runs/98',generated_types_artifact_id:122,generated_types_artifact_digest:`sha256:${'d'.repeat(64)}`,generated_types_output_digest:`sha256:${'e'.repeat(64)}`}:{})}
  const io={
    getIssue:()=>({...issue(scopeBody({generated})),state:issueState}),updateIssue:(_n,fields)=>{issueState=fields.state},parseScope:parseQueueScope,issueComments:()=>comments,
    readOutcomeEvidence:()=>['```db-outcome-evidence',JSON.stringify(evidence),'```'].join('\n'),
    closingIssuesForPr:()=>[{number:41,state:'closed'}],prStructuralObjects:()=>['table core.example'],
    getPr:()=>({merged_at:'2026-09-11T00:00:00Z',merge_commit_sha:merge}),mergeCommitInMain:()=>true,
    applicationCommitInDefaultBranch:()=>true,verifyLiveAssertion:()=>true,verifyGeneratedTypes:()=>true,
    commentIssue:(_n,body)=>comments.push({body}),
  }
  return {io,comments}
}

test('completion re-derives merge, application, generated types, and live assertion before one authoritative completion', () => {
  const {io,comments}=completionFixture({generated:'required'})
  const result=completeOutcome({issue:41,evidenceRef:'https://github.com/u2giants/shared-db/issues/41#issuecomment-9',actor:'test',timestamp:'2026-09-11T02:00:00Z'},io)
  assert.equal(result.completed,true)
  assert.equal(outcomeHistory(comments).state,'live_verified')
  assert.equal(findCompletionRecord(comments).outcome,'live_verified')
})

test('completion resumes after the live event when a later write lost its response',()=>{
  const {io,comments}=completionFixture()
  const normal=io.commentIssue;let failed=false
  io.commentIssue=(number,body)=>{
    if(body.includes('Authoritative outcome completion')&&!failed){failed=true;throw new Error('response lost')}
    normal(number,body)
  }
  assert.throws(()=>completeOutcome({issue:41,evidenceRef:'https://github.com/u2giants/shared-db/issues/41#issuecomment-9',actor:'test',timestamp:'2026-09-11T02:00:00Z'},io),/response lost/)
  assert.equal(outcomeHistory(comments).state,'live_verified')
  assert.equal(completeOutcome({issue:41,evidenceRef:'https://github.com/u2giants/shared-db/issues/41#issuecomment-9',actor:'test',timestamp:'2026-09-11T02:01:00Z'},io).completed,true)
  assert.equal(comments.filter((row)=>row.body.includes('Authoritative outcome completion')).length,1)
})

test('completion retries safely after completion-comment or close response loss',()=>{
  for(const boundary of ['completion-comment','close']){
    const {io,comments}=completionFixture();const normalComment=io.commentIssue,normalUpdate=io.updateIssue;let failed=false
    if(boundary==='completion-comment')io.commentIssue=(number,body)=>{normalComment(number,body);if(body.includes('Authoritative outcome completion')&&!failed){failed=true;throw new Error('completion response lost')}}
    else io.updateIssue=(number,fields)=>{normalUpdate(number,fields);if(!failed){failed=true;throw new Error('close response lost')}}
    assert.throws(()=>completeOutcome({issue:41,evidenceRef:'https://github.com/u2giants/shared-db/issues/41#issuecomment-9',actor:'test'},io),/response lost/)
    assert.equal(completeOutcome({issue:41,evidenceRef:'https://github.com/u2giants/shared-db/issues/41#issuecomment-9',actor:'test'},io).completed,true,boundary)
    assert.equal(comments.filter((row)=>row.body.includes('Authoritative outcome completion')).length,1,boundary)
  }
})

test('completion refuses preview-only, merge-only, missing generated types, missing return address, and mismatched live assertion', () => {
  for(const through of ['preview_verified','merged']){const {io}=completionFixture({through});assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/not production_applied/)}
  {const {io}=completionFixture({generated:'required'});const base=io.readOutcomeEvidence;io.readOutcomeEvidence=()=>base().replace(/,"generated_types_evidence":"[^"]+"/,'');assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/generated types/)}
  {const {io}=completionFixture();io.getIssue=()=>issue(scopeBody({returnTo:''}));assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/application_return_to|return address/)}
  {const {io}=completionFixture();const base=io.readOutcomeEvidence;io.readOutcomeEvidence=()=>base().replace('authenticated create-and-read succeeds','different assertion');assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/live_assertion/)}
  {const {io}=completionFixture();io.closingIssuesForPr=()=>[{number:41},{number:42}];assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/not linked exclusively/)}
  {const {io}=completionFixture();io.prStructuralObjects=()=>['table core.other'];assert.throws(()=>completeOutcome({issue:41,evidenceRef:'x',actor:'test'},io),/structural objects do not match/)}
})
