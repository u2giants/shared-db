import assert from 'node:assert/strict'
import test from 'node:test'
import { repairVoidedFindings, unvoidFindingsBody, commentIdFromFindingsRef } from './repair-voided-findings.mjs'
import { neutraliseVerdictLine } from './run-governed-review.mjs'
import { findingsDigest } from './lib/review-verdict-artifact.mjs'

const headSha='c5a186effd6207d05a763fc422670c1db53e1fea'
const ref=`refs/db-review-verdicts/2460-2461-${headSha}`
const findingsRef='https://github.com/u2giants/shared-db/pull/2461#issuecomment-987654'
const original=`GOVERNED REVIEW FINDINGS\n\nCoverage: scripts/x.mjs lines 1-40.\nNo material findings.\nVERDICT: APPROVE ${headSha}`
const voided=neutraliseVerdictLine(original,'create-only verdict readback disagrees with the created object')

function ioFixture({body=voided,digest=findingsDigest(original)}={}){
  const comments=new Map([[987654,body]])
  const patches=[]
  return{comments,patches,
    readRef:()=>'a'.repeat(40),
    getCommit:()=>({message:`db-review-verdict ${JSON.stringify({verdict:'APPROVE',head_sha:headSha,issue:2460,pr:2461,slot:2,findings_digest:digest,findings_ref:findingsRef})}`}),
    readComment:(id)=>comments.get(id)??null,
    patchComment:(id,next)=>{patches.push({id,next});comments.set(id,next)}}
}

test('the void transform is exactly invertible',()=>{
  assert.equal(unvoidFindingsBody(voided),original)
})

test('a dry run proves the repair without writing, and --apply restores the recorded digest',()=>{
  const io=ioFixture()
  const dry=repairVoidedFindings({ref},io)
  assert.equal(dry.status,'repairable')
  assert.equal(io.patches.length,0)
  const applied=repairVoidedFindings({ref,apply:true},io)
  assert.equal(applied.status,'repaired')
  assert.equal(io.comments.get(987654),original)
  assert.equal(applied.digest,findingsDigest(original))
})

test('an undamaged comment is reported as already valid and never written',()=>{
  const io=ioFixture({body:original})
  assert.equal(repairVoidedFindings({ref,apply:true},io).status,'already-valid')
  assert.equal(io.patches.length,0)
})

// PROVE THE PROOF CAN FAIL. The digest is the whole safeguard: it is the artifact's own
// evidence, written before the damage. If the un-voided bytes do not reproduce it, the
// restoration is wrong -- a differently-damaged comment, a hand edit, a different review --
// and the tool must write nothing rather than install a body that merely looks plausible.
test('a restoration that does not reproduce the recorded digest writes nothing',()=>{
  const io=ioFixture({digest:'0'.repeat(64)})
  assert.throws(()=>repairVoidedFindings({ref,apply:true},io),/did not reproduce the digest/)
  assert.equal(io.patches.length,0)
})

test('a comment that carries no void markers is refused, not guessed at',()=>{
  const io=ioFixture({body:'someone edited this by hand'})
  assert.throws(()=>repairVoidedFindings({ref,apply:true},io),/does not carry the governed runner's void markers/)
  assert.equal(io.patches.length,0)
})

test('a missing artifact and a malformed ref are both refused',()=>{
  const io=ioFixture();io.readRef=()=>null
  assert.throws(()=>repairVoidedFindings({ref},io),/nothing to repair/)
  assert.throws(()=>repairVoidedFindings({ref:'refs/heads/main'},ioFixture()),/a verdict ref is required/)
})

test('the comment id comes from the findings ref',()=>{
  assert.equal(commentIdFromFindingsRef(findingsRef),987654)
  assert.equal(commentIdFromFindingsRef('https://github.com/u2giants/shared-db/pull/2461'),null)
})
