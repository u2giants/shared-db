#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { recordReviewVerdict, reviewerExecutionPreflight, resolveCommandPath } from './manage-migration-author-lanes.mjs'

export function parseArgs(argv){
  const split=argv.indexOf('--'),own=split<0?argv:argv.slice(0,split),wrapperArgs=split<0?[]:argv.slice(split+1),out={wrapperArgs,slot:1}
  for(let i=0;i<own.length;i+=2){const key=own[i]?.replace(/^--/,'').replace(/-([a-z])/g,(_,c)=>c.toUpperCase());if(!key||i+1>=own.length)throw new Error('governed review arguments must be --name value pairs followed by -- and wrapper arguments');out[key]=own[i+1]}
  out.issue=Number(out.issue);out.pr=Number(out.pr);out.slot=Number(out.reviewSlot??1)
  return out
}
export function verdictFromOutput(body,headSha){
  const lines=String(body??'').split(/\r?\n/).map((line)=>line.trim()).filter(Boolean)
  const verdictLines=lines.filter((line)=>/^VERDICT\s*:\s*(?:APPROVE|REVISE|REJECT)\b/i.test(line))
  if(verdictLines.length!==1||verdictLines[0]!==lines.at(-1))return null
  const match=/^VERDICT\s*:\s*(APPROVE|REVISE|REJECT)(?:\s+([0-9a-f]{40}))?\s*$/i.exec(verdictLines[0])
  if(!match||!match[2]||match[2].toLowerCase()!==String(headSha??'').toLowerCase())return null
  return match[1].toUpperCase()
}
export const VOID_MARKER='VERDICT LINE VOIDED BY THE GOVERNED REVIEW RUNNER'
// Rewrites ONLY the terminal machine-parseable verdict line of an already-posted
// findings comment into a clearly-marked voided form. The reviewer's analysis is
// evidence: every other line is preserved verbatim. The replacement must be
// unreadable both to `verdictFromOutput` (which requires the terminal line to
// match its VERDICT regex) and to `anyVerdictFor`/`isVerdictFor` (which strip a
// leading `VERDICT:` label plus leading `[\s>*_#-]` punctuation and then test
// whether the line OPENS with a decision word). So no produced line opens with
// VERDICT:, APPROVE, REVISE or REJECT; the decision word survives only
// mid-sentence, quoted, for the human reader.
export function neutraliseVerdictLine(body,reason){
  const lines=String(body??'').split(/\r?\n/)
  let index=-1
  for(let i=lines.length-1;i>=0;i-=1){
    if(!lines[i].trim())continue
    if(/^\s*VERDICT\s*:\s*(?:APPROVE|REVISE|REJECT)\b/i.test(lines[i]))index=i
    break
  }
  if(index<0)return null
  const decision=/(APPROVE|REVISE|REJECT)/i.exec(lines[index])?.[1]?.toUpperCase()??'UNKNOWN'
  lines[index]=[
    `> ${VOID_MARKER}.`,
    '>',
    `> The reviewer's terminal verdict line (its decision word was "${decision}") was rewritten so that no tool can read it as a verdict at this head. It was voided because the durable verdict artifact could not be recorded, so this comment authorizes nothing. Reason: ${reason}`,
    '>',
    "> The reviewer's findings above are unchanged and remain readable as evidence. A real decision requires a fresh governed review that records a create-only verdict artifact."
  ].join('\n')
  return lines.join('\n')
}
export function wrapperSpawnPlan(resolved,args,platform=process.platform){
  if(platform==='win32'&&/\.(cmd|bat)$/i.test(resolved))return{file:process.env.ComSpec||'cmd.exe',args:['/d','/s','/c',resolved,...args]}
  return{file:resolved,args}
}
export function runGovernedReview(options,deps={spawn:spawnSync,preflight:reviewerExecutionPreflight,record:recordReviewVerdict,resolve:resolveCommandPath}){
  deps.preflight({reviewer:options.reviewer,wrapper:options.wrapper,worktree:options.worktree,headSha:options.headSha})
  const resolved=(deps.resolve??resolveCommandPath)(options.wrapper)
  if(!resolved)throw new Error(`review wrapper ${options.wrapper} is not executable`)
  const plan=wrapperSpawnPlan(resolved,options.wrapperArgs)
  const run=deps.spawn(plan.file,plan.args,{cwd:options.worktree,encoding:'utf8',maxBuffer:64*1024*1024,stdio:['ignore','pipe','pipe']})
  const rawBody=String(run.stdout??'').trim(),verdict=verdictFromOutput(rawBody,options.headSha)
  if(run.error||run.status!==0||!verdict)throw new Error(`review wrapper did not produce a recordable terminal verdict (exit ${run.status??'unknown'})`)
  const body=`GOVERNED REVIEW FINDINGS — NON-AUTHORIZING UNLESS THE MATCHING CREATE-ONLY VERDICT ARTIFACT EXISTS\n\n${rawBody}`
  const posted=deps.spawn('gh',['api','-X','POST',`repos/u2giants/shared-db/issues/${options.pr}/comments`,'--input','-'],{encoding:'utf8',input:JSON.stringify({body}),maxBuffer:64*1024*1024,stdio:['pipe','pipe','pipe']})
  if(posted.error||posted.status!==0)throw new Error('review findings could not be posted durably; no verdict was recorded')
  let comment
  try{comment=JSON.parse(posted.stdout)}catch{throw new Error('durable findings response was unreadable; no verdict was recorded')}
  let artifact
  try{artifact=deps.record({...options,verdict,findingsRef:comment.html_url,replacementSequence:options.replacementSequence??null})}
  catch(error){
    // The findings comment posted above still ends in a machine-parseable
    // terminal verdict line. Left in place, the lane tooling reads it as a real
    // verdict at this head and the pull request deadlocks in both directions
    // (issue #2075). Void that one line before announcing the failure.
    let voidStatus='voided'
    try{
      const edited=neutraliseVerdictLine(body,error.message)
      if(edited===null)throw new Error('the posted findings comment carried no terminal verdict line to void')
      const patch=deps.spawn('gh',['api','-X','PATCH',`repos/u2giants/shared-db/issues/comments/${comment.id}`,'--input','-'],{encoding:'utf8',input:JSON.stringify({body:edited}),maxBuffer:64*1024*1024,stdio:['pipe','pipe','pipe']})
      if(patch.error||patch.status!==0)throw new Error(`gh exited ${patch.status??'unknown'}${patch.error?` (${patch.error.message})`:''}`)
    }catch(voidError){voidStatus=`FAILED: ${voidError.message}`}
    const stillLive=voidStatus!=='voided'
    const note=stillLive
      ? `\n\nTHE VOIDING EDIT ITSELF ${voidStatus}. A PARSEABLE TERMINAL VERDICT LINE IS STILL LIVE ON COMMENT ${comment.id} (${comment.html_url}). Lane tooling will read it as a real verdict at ${options.headSha} and deadlock this pull request. That line must be neutralised BY HAND on comment ${comment.id} before this pull request can proceed.`
      : `\n\nThe terminal verdict line on comment ${comment.id} was voided so no tool can read it as a verdict at ${options.headSha}. The reviewer's findings were left intact.`
    deps.spawn('gh',['api','-X','POST',`repos/u2giants/shared-db/issues/${options.pr}/comments`,'--input','-'],{encoding:'utf8',input:JSON.stringify({body:`REVIEW RECORDING FAILED — the preceding findings comment is non-authorizing and no verdict artifact was recorded. Reason: ${error.message}${note}`}),maxBuffer:64*1024*1024,stdio:['pipe','pipe','pipe']})
    if(stillLive)throw new Error(`${error.message} — and the voiding edit ${voidStatus}; a parseable terminal verdict line is still live on comment ${comment.id} and must be neutralised by hand`)
    throw error
  }
  return {artifact,body}
}
export function main(argv=process.argv.slice(2)){
  try{const result=runGovernedReview(parseArgs(argv));process.stdout.write(`${result.body}\n\nDURABLE VERDICT: ${result.artifact.ref} ${result.artifact.sha}\n`);return 0}catch(error){process.stderr.write(`REFUSED: ${error.message}\n`);return 2}
}
if(import.meta.url===pathToFileURL(process.argv[1]??'').href)process.exitCode=main()
