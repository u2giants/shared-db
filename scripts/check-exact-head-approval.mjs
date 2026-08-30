#!/usr/bin/env node
// Merge authorization requires an independent APPROVE tied to the EXACT head
// being merged.
//
// Why this file exists (#1816): the guarded-migration-merge workflow proved head
// identity, base currency, object collisions and the author lease, but never once
// asked whether the bytes being merged had been approved. The exact-head rule was
// enforced by convention in the orchestrator's instructions and by the PREVIEW
// gate -- which, under merge-first (AGENTS.md section 4 rule 2), only runs AFTER
// the merge. So the sequence
//
//     reviewer REJECTs head A  ->  author pushes head B answering it  ->  merge B
//
// merged bytes no reviewer had ever seen. That happened on PR #1809 (issue #1769):
// grok-4.6 was assigned and REJECTed b494401, commit 8d3c31a answered the findings,
// and 8d3c31a merged as 2b68e7e with zero approvals tied to it.
//
// An assignment is not an approval and an approval at an older head is not an
// approval of these bytes. Both are required, both pinned to the same exact SHA.
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { REPO, REVIEW_ASSIGNMENT_REF_PREFIX, REVIEW_REPLACEMENT_REF_PREFIX } from './manage-migration-author-lanes.mjs'

export class ApprovalCheckError extends Error {}

// A decision is "tied" to a head when GitHub records it against that commit or the
// author wrote the SHA into the body. Same rule the preview gate uses, so the two
// gates cannot drift into disagreeing about what a reviewer approved.
const tiedToHead = (row, headSha) => row.commit_id === headSha || String(row.body ?? '').includes(headSha)
// A VERDICT is a line that OPENS with the verdict word -- not prose that happens to
// mention it. A lane wrote a progress note on its own PR naming the head SHA and the
// word REVISE, and permanently locked its own head: the note read as a recorded
// refusal. Under an ENFORCED gate a self-locked head is unmergeable, and the failure
// looks like an unexplained refusal rather than anything comment-shaped. So the verdict
// word must lead its line (markdown emphasis and quoting allowed), which is how the
// reviewer wrappers emit it and is not how anyone writes a status update. The rule is
// applied symmetrically: prose cannot grant an approval either.
const verdictLine = (body, pattern) => String(body ?? '').split(/\r?\n/).some((line) => pattern.test(line.replace(/^[\s>*_#-]+/, '')))
const APPROVE = /^APPROVE(?:D)?\b/i
// REJECT is a real verdict word in this repo's reviewer wrappers alongside REVISE
// and GitHub's own CHANGES_REQUESTED. Omitting any of them would let a refusal at
// the merged head be silently outvoted by an approval that came before it.
const REFUSAL = /^(?:REJECT(?:ED)?|REVISE|REQUEST_CHANGES)\b/i

export function evaluateExactHeadApproval({ pr, headSha, evidence = [], assignments = [] }) {
  if (!/^[0-9a-f]{40}$/i.test(String(headSha ?? ''))) throw new ApprovalCheckError('an exact 40-character head SHA is required')
  if (!Number.isInteger(Number(pr)) || Number(pr) <= 0) throw new ApprovalCheckError('an exact pull request number is required')

  const pinned = assignments.filter((row) => String(row.headSha ?? '').toLowerCase() === String(headSha).toLowerCase())
  if (!pinned.length) throw new ApprovalCheckError(`no independent reviewer was ever assigned head ${headSha}; an assignment pinned to an earlier head does not carry forward to new commits`)

  const atHead = evidence.filter((row) => tiedToHead(row, headSha))
  const state = (row) => String(row.state ?? '').toUpperCase()
  const refusals = atHead.filter((row) => verdictLine(row.body, REFUSAL) || state(row) === 'CHANGES_REQUESTED')
  if (refusals.length) throw new ApprovalCheckError(`head ${headSha} carries an unanswered reviewer refusal; answer it with a new commit and a fresh exact-head review`)

  const approvals = atHead.filter((row) => verdictLine(row.body, APPROVE) || state(row) === 'APPROVED')
  if (!approvals.length) throw new ApprovalCheckError(`head ${headSha} has no APPROVE tied to it; an approval of an earlier head never approves these bytes`)

  return { approved: true, head_sha: headSha, pr: Number(pr), assignments: pinned.length, approvals: approvals.length }
}

function gh(args) { try { return execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }) } catch (e) { throw new ApprovalCheckError(`GitHub read failed: ${e.stderr || e.message}`) } }
function json(args) { const raw = gh(args); try { return JSON.parse(raw) } catch { throw new ApprovalCheckError('GitHub returned malformed JSON') } }
function pages(endpoint) { const result = json(['api', '--paginate', '--slurp', endpoint]); if (!Array.isArray(result) || result.some((x) => !Array.isArray(x))) throw new ApprovalCheckError(`GitHub pagination for ${endpoint} is malformed`); return result.flat() }

export function parseAssignmentRef(ref) {
  const match = /^refs\/db-review-(?:assignments|replacements)\/(\d+)-(\d+)-([0-9a-f]{40})(?:-slot\d+)?(?:\/.*)?$/.exec(String(ref ?? ''))
  return match ? { issue: Number(match[1]), pr: Number(match[2]), headSha: match[3] } : null
}

// Assignment refs are named <issue>-<pr>-<headSha>, so the pull request alone is
// enough to find them; the work issue never has to be guessed here.
// `deps` exists so this ADAPTER can be tested against real GitHub payload shapes.
// The evaluation core was tested and the adapter that feeds it was not -- which is
// where the same class of defect has now hidden twice repo-wide: a conversion layer
// whose test-time shape diverges from the one production produces. Nothing is
// stubbed in production; the defaults are the real readers.
export function gatherApprovalInput(env = process.env, deps = { json, pages }) {
  const { json: readJson = json, pages: readPages = pages } = deps
  let event = {}; if (env.GITHUB_EVENT_PATH) event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'))
  const pr = Number(env.PR_NUMBER || event.pull_request?.number); if (!pr) throw new ApprovalCheckError('PR number is unavailable')
  const headSha = String(env.REQUESTED_SHA || readJson(['api', `repos/${REPO}/pulls/${pr}`])?.head?.sha || '')
  const issueNumbers = new Set([pr])
  // Slot 2 assignments are suffixed `-slot<N>`, and a reviewer replaced after a
  // failure keeps its own ref under the replacement namespace, pinned to the SAME
  // head. Both are genuine independent assignments to these exact bytes, so both
  // count; ignoring either would refuse a merge whose review really did happen.
  const refs = [REVIEW_ASSIGNMENT_REF_PREFIX, REVIEW_REPLACEMENT_REF_PREFIX].flatMap((prefix) => {
    const rows = readJson(['api', `repos/${REPO}/git/matching-refs/${prefix.replace(/^refs\//, '')}/`])
    return Array.isArray(rows) ? rows : []
  })
  const assignments = refs.flatMap((row) => {
    const parsed = parseAssignmentRef(row.ref)
    if (!parsed || parsed.pr !== pr) return []
    issueNumbers.add(parsed.issue)
    return [parsed]
  })
  const evidence = [
    ...[...issueNumbers].flatMap((number) => readPages(`repos/${REPO}/issues/${number}/comments?per_page=100`)),
    ...readPages(`repos/${REPO}/pulls/${pr}/reviews?per_page=100`),
  ]
  return { pr, headSha, evidence, assignments }
}

export function main(env = process.env) {
  try {
    const result = evaluateExactHeadApproval(gatherApprovalInput(env))
    console.log(`Exact-head approval verified: PR #${result.pr} head ${result.head_sha} (${result.approvals} approval(s), ${result.assignments} pinned assignment(s)).`)
    return 0
  } catch (e) { console.error(`REFUSED: ${e.message}`); return 2 }
}
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main()
