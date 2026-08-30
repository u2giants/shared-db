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
//
// WHAT THIS GATE DOES NOT CHECK -- stated here so nobody reads more into a pass
// than it carries. It enforces `an assignment exists at this head` AND `an approval
// exists at this head`, not `the assigned reviewer approved`. Assignment refs record
// {issue, pr, headSha} and no reviewer identity, and the evidence rows are read from
// issue and PR comments with no author, association or permission field consulted at
// all. So anyone who can comment can supply the approval half. The word
// "independent" here describes the assignment PROCESS -- the rotation in
// `manage-migration-author-lanes.mjs`, which picks the reviewer and refuses the
// live orchestrator's own engine -- and is not a property this file verifies.
// Two related limits, both deliberate:
//   - The head tie (`tiedToHead`) matches the SHA anywhere in the body, while the
//     verdict must open a line. A comment quoting an old approval and separately
//     naming the new head therefore counts at the new head. Requiring the SHA on
//     the verdict line itself was considered and rejected: every genuine wrapper
//     review in `.ai/reviews` names the head in a header block and ends with a bare
//     `VERDICT: APPROVE`, so that rule would refuse all real approvals -- the
//     inverse defect described below, which is the more dangerous one.
//   - Fenced or indented code containing a verdict line counts.
// Against the status quo this replaces -- nothing at all, which merged unapproved
// bytes on PR #1809 -- it is a process-integrity gate and a large improvement. It is
// not an authenticity gate, and it should never be cited as one.
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
// The reviewer wrappers do not emit a bare verdict word: they are instructed to
// end with `VERDICT: APPROVE` / `VERDICT: REVISE`, and the reviews in .ai/reviews
// show it in the wild as `VERDICT: APPROVE`, `## VERDICT: APPROVE` and
// `VERDICT: APPROVED`. Anchoring on the bare word alone would have rejected every
// genuine approval this repo produces -- the inverse of the defect this file fixes,
// and the more dangerous inverse: a self-locked head fails closed loudly and gets
// investigated, while a gate that refuses all valid input looks like reviewers not
// returning verdicts, so the wrappers get blamed and re-run instead of the gate.
// The optional label is stripped, never the verdict itself: `VERDICT: DO NOT
// APPROVE` still does not open with APPROVE and is still not an approval.
const stripVerdictLabel = (line) => line.replace(/^[\s>*_#-]+/, '').replace(/^VERDICT\s*:\s*/i, '')
const verdictLine = (body, pattern) => String(body ?? '').split(/\r?\n/).some((line) => pattern.test(stripVerdictLabel(line)))
// `APPROVE WITH CONDITIONS` is a refusal-with-remedy, not an approval: the
// conditions ARE the reviewer's finding, so merging on it merges the state the
// reviewer declined to authorize -- while producing an audit trail saying they
// approved. `psg4-glm52-review-brief.md` offers reviewers exactly that wording.
// Matching it because the line opens with APPROVE is the anywhere-in-body defect
// in miniature: matching the token instead of the claim.
//
// It deliberately does NOT join REFUSAL. Failing to satisfy the approval gate is
// not the same as recording a refusal: a conditional response must leave the head
// unapproved without LOCKING it, or the reviewer's own conditions strand the head
// those conditions were meant to be met on -- the self-lock through a new door.
// The separator before WITH is any run of non-letters, not a space: `APPROVE, WITH
// CONDITIONS` and `APPROVE -- WITH CONDITIONS` are the same claim as the plain form
// and a whitespace-only lookahead let both through as clean approvals.
const APPROVE = /^APPROVE(?:D)?\b(?![^A-Za-z]+WITH\b)/i
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
// The replacement writer names its link `<base>-<failedSequence>` -- a DASH and
// digits, not a slash (`manage-migration-author-lanes.mjs`, `replacementRef`, and
// `inReviewReplacementNamespace`, which requires the remainder to match /^-\d+$/).
// This parser originally accepted only the slash form, so every real replacement
// ref parsed to null and the documented "both namespaces count" behaviour was not
// implemented -- fail-closed, but false. Its two tests asserted the slash shape
// production never writes: the adapter-shape defect this file's own header warns
// about, committed in the file that warns about it. The tail now mirrors
// `matchesReplacementTuple`.
  const match = /^refs\/db-review-(?:assignments|replacements)\/(\d+)-(\d+)-([0-9a-f]{40})(?:-slot\d+)?(?:-\d+)?(?:\/.*)?$/.exec(String(ref ?? ''))
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
