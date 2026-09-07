#!/usr/bin/env node
// RECOVERY FOR A VERDICT ARTIFACT THIS TOOLING INVALIDATED ITSELF (issue #2464).
//
// `run-governed-review.mjs` used to react to a recording failure by rewriting the findings
// comment to void its decision lines -- even when the create-only verdict ref had ALREADY
// been created and had recorded the sha256 of those exact bytes. The rewrite changed the
// bytes, so `validateVerdictArtifact` could never match again; and because the ref is
// create-only, the tuple could never be re-recorded. Observed on PR #2461 slot 2 (artifact
// 43340d95) and PR #2415 (head 0fab4ace). The runner no longer does this. Tuples burned
// BEFORE that fix still exist, and their reviews were real, complete and paid for.
//
// This repairs exactly that, and nothing else. The void is a deterministic transform, so it
// is invertible: this un-voids the live comment and PROVES the restoration is correct by
// re-deriving the sha256 and requiring it to equal the digest the artifact already recorded.
// That digest is the artifact's own evidence, written before the damage -- it cannot be
// satisfied by a body this script invented. If the digest does not match, nothing is
// written and the refusal names what it compared.
//
// It asserts nothing on the operator's behalf. It does not create, move or delete a ref, it
// does not record a verdict, and it cannot manufacture one: it only restores bytes that the
// artifact already attests to.
import { pathToFileURL } from 'node:url'
import { spawnGitHub } from './lib/github-transport.mjs'
import { findingsDigest, parseVerdictCommit, parseVerdictRef } from './lib/review-verdict-artifact.mjs'
import { VOID_MARKER, VOID_LINE_PREFIX } from './run-governed-review.mjs'

export const REPO='u2giants/shared-db'

// The exact inverse of `neutraliseVerdictLine`: drop the appended void block, then strip the
// `> VOIDED REVIEWER LINE - ` prefix from every line that carries it. It is deliberately
// unforgiving -- a body that does not carry the marker, or that carries no voided line, is
// not a body this tool damaged, so it returns null rather than guessing.
export function unvoidFindingsBody(body){
  const lines=String(body??'').split(/\r?\n/)
  const marker=lines.findIndex((line)=>line.includes(VOID_MARKER))
  if(marker<1)return null
  const tail=lines.at(-1)??''
  if(!tail.startsWith('> The reviewer\'s findings are otherwise unchanged'))return null
  let cut=marker
  if(lines[cut-1]==='')cut-=1
  let restored=0
  const kept=lines.slice(0,cut).map((line)=>{
    if(!line.startsWith(VOID_LINE_PREFIX))return line
    restored+=1
    return line.slice(VOID_LINE_PREFIX.length)
  })
  if(!restored)return null
  return kept.join('\n')
}

export function commentIdFromFindingsRef(findingsRef){
  const match=/#issuecomment-(\d+)$/.exec(String(findingsRef??''))
  return match?Number(match[1]):null
}

export function repairVoidedFindings({ref,apply=false},io){
  if(!parseVerdictRef(ref))throw new Error('a verdict ref is required, for example refs/db-review-verdicts/2355-2415-<head>')
  const sha=io.readRef(ref)
  if(!sha)throw new Error(`no verdict artifact exists at ${ref}; there is nothing to repair`)
  const record=parseVerdictCommit(io.getCommit(sha))
  const commentId=commentIdFromFindingsRef(record.findings_ref)
  if(!commentId)throw new Error(`the artifact records an unusable findings_ref (${record.findings_ref})`)
  const live=io.readComment(commentId)
  if(typeof live!=='string')throw new Error(`findings comment ${commentId} could not be read`)
  const liveDigest=findingsDigest(live)
  if(liveDigest===record.findings_digest)return{status:'already-valid',ref,sha,commentId,digest:liveDigest}
  const restored=unvoidFindingsBody(live)
  if(restored===null)throw new Error(`findings comment ${commentId} does not carry the governed runner's void markers, so this is not the damage this tool repairs; live digest ${liveDigest}, artifact digest ${record.findings_digest}`)
  const restoredDigest=findingsDigest(restored)
  // THE PROOF. The artifact's digest was written before the damage and cannot be satisfied
  // by a body this script invented. Equality here means the restored bytes ARE the bytes the
  // reviewer produced and the artifact attests to.
  if(restoredDigest!==record.findings_digest)throw new Error(`un-voiding comment ${commentId} did not reproduce the digest the artifact recorded (restored ${restoredDigest}, artifact ${record.findings_digest}); nothing was written`)
  if(!apply)return{status:'repairable',ref,sha,commentId,restored,digest:restoredDigest}
  io.patchComment(commentId,restored)
  const after=findingsDigest(io.readComment(commentId))
  if(after!==record.findings_digest)throw new Error(`the repair was written but comment ${commentId} still reads ${after}, not ${record.findings_digest}`)
  return{status:'repaired',ref,sha,commentId,digest:after}
}

const githubIo={
  readRef(ref){
    const out=spawnGitHub(['api',`repos/${REPO}/git/ref/${ref.replace(/^refs\//,'')}`])
    if(out.status!==0)return null
    try{return JSON.parse(out.stdout).object.sha}catch{return null}
  },
  getCommit(sha){
    const out=spawnGitHub(['api',`repos/${REPO}/git/commits/${sha}`])
    if(out.status!==0)throw new Error(`commit ${sha} could not be read`)
    return JSON.parse(out.stdout)
  },
  readComment(id){
    const out=spawnGitHub(['api',`repos/${REPO}/issues/comments/${id}`])
    if(out.status!==0)return null
    try{return JSON.parse(out.stdout).body}catch{return null}
  },
  patchComment(id,body){
    const out=spawnGitHub(['api','-X','PATCH',`repos/${REPO}/issues/comments/${id}`,'--input','-'],{input:JSON.stringify({body})})
    if(out.status!==0)throw new Error(`comment ${id} could not be updated`)
  },
}

export function main(argv=process.argv.slice(2)){
  const ref=argv[argv.indexOf('--ref')+1]
  const apply=argv.includes('--apply')
  try{
    const result=repairVoidedFindings({ref,apply},githubIo)
    if(result.status==='already-valid')process.stdout.write(`ALREADY VALID: ${result.ref} matches comment ${result.commentId}; no repair is needed\n`)
    else if(result.status==='repairable')process.stdout.write(`REPAIRABLE: un-voiding comment ${result.commentId} reproduces the artifact digest ${result.digest}. Re-run with --apply to write it.\n`)
    else process.stdout.write(`REPAIRED: comment ${result.commentId} restored; ${result.ref} validates again at digest ${result.digest}\n`)
    return 0
  }catch(error){process.stderr.write(`REFUSED: ${error.message}\n`);return 2}
}
if(import.meta.url===pathToFileURL(process.argv[1]??'').href)process.exitCode=main()
