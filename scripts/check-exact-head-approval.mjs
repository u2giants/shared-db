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
import { REPO, REVIEW_ASSIGNMENT_REF_PREFIX } from './manage-migration-author-lanes.mjs'

export class ApprovalCheckError extends Error {}

// A decision is "tied" to a head when GitHub records it against that commit or the
// author wrote the SHA into the body. Same rule the preview gate uses, so the two
// gates cannot drift into disagreeing about what a reviewer approved.
const tiedToHead = (row, headSha) => row.commit_id === headSha || String(row.body ?? '').includes(headSha)
const APPROVE = /\bAPPROVE(?:D)?\b/i
// REJECT is a real verdict word in this repo's reviewer wrappers alongside REVISE
// and GitHub's own CHANGES_REQUESTED. Omitting any of them would let a refusal at
// the merged head be silently outvoted by an approval that came before it.
const REFUSAL = /\b(?:REJECT(?:ED)?|REVISE|REQUEST_CHANGES)\b/i

export function evaluateExactHeadApproval({ pr, headSha, evidence = [], assignments = [] }) {
  if (!/^[0-9a-f]{40}$/i.test(String(headSha ?? ''))) throw new ApprovalCheckError('an exact 40-character head SHA is required')
  if (!Number.isInteger(Number(pr)) || Number(pr) <= 0) throw new ApprovalCheckError('an exact pull request number is required')

  const pinned = assignments.filter((row) => String(row.headSha ?? '').toLowerCase() === String(headSha).toLowerCase())
  if (!pinned.length) throw new ApprovalCheckError(`no independent reviewer was ever assigned head ${headSha}; an assignment pinned to an earlier head does not carry forward to new commits`)

  const atHead = evidence.filter((row) => tiedToHead(row, headSha))
  const state = (row) => String(row.state ?? '').toUpperCase()
  const refusals = atHead.filter((row) => REFUSAL.test(String(row.body ?? '')) || state(row) === 'CHANGES_REQUESTED')
  if (refusals.length) throw new ApprovalCheckError(`head ${headSha} carries an unanswered reviewer refusal; answer it with a new commit and a fresh exact-head review`)

  const approvals = atHead.filter((row) => APPROVE.test(String(row.body ?? '')) || state(row) === 'APPROVED')
  if (!approvals.length) throw new ApprovalCheckError(`head ${headSha} has no APPROVE tied to it; an approval of an earlier head never approves these bytes`)

  return { approved: true, head_sha: headSha, pr: Number(pr), assignments: pinned.length, approvals: approvals.length }
}

function gh(args) { try { return execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }) } catch (e) { throw new ApprovalCheckError(`GitHub read failed: ${e.stderr || e.message}`) } }
function json(args) { const raw = gh(args); try { return JSON.parse(raw) } catch { throw new ApprovalCheckError('GitHub returned malformed JSON') } }
function pages(endpoint) { const result = json(['api', '--paginate', '--slurp', endpoint]); if (!Array.isArray(result) || result.some((x) => !Array.isArray(x))) throw new ApprovalCheckError(`GitHub pagination for ${endpoint} is malformed`); return result.flat() }

// Assignment refs are named <issue>-<pr>-<headSha>, so the pull request alone is
// enough to find them; the work issue never has to be guessed here.
export function gatherApprovalInput(env = process.env) {
  let event = {}; if (env.GITHUB_EVENT_PATH) event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'))
  const pr = Number(env.PR_NUMBER || event.pull_request?.number); if (!pr) throw new ApprovalCheckError('PR number is unavailable')
  const headSha = String(env.REQUESTED_SHA || json(['api', `repos/${REPO}/pulls/${pr}`])?.head?.sha || '')
  const issueNumbers = new Set([pr])
  const refs = json(['api', `repos/${REPO}/git/matching-refs/${REVIEW_ASSIGNMENT_REF_PREFIX.replace(/^refs\//, '')}/`])
  const assignments = (Array.isArray(refs) ? refs : []).flatMap((row) => {
    const match = new RegExp(`^${REVIEW_ASSIGNMENT_REF_PREFIX}/(\\d+)-(\\d+)-([0-9a-f]{40})$`).exec(String(row.ref ?? ''))
    if (!match || Number(match[2]) !== pr) return []
    issueNumbers.add(Number(match[1]))
    return [{ issue: Number(match[1]), pr, headSha: match[3] }]
  })
  const evidence = [
    ...[...issueNumbers].flatMap((number) => pages(`repos/${REPO}/issues/${number}/comments?per_page=100`)),
    ...pages(`repos/${REPO}/pulls/${pr}/reviews?per_page=100`),
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
