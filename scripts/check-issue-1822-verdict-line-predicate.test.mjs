// Issue #1822 -- a progress comment naming a head SHA and a verdict word must
// not register as a recorded verdict.
//
// EVERY assertion here runs against the SAME regex engine production uses, by
// importing the real predicate. It deliberately does not shell out to `jq`:
// `jq 'test("\\b(APPROVE|REVISE)\\b";"i")'` returns ZERO matches on the very
// comment bodies below, because the doubled backslash collapses to a literal
// \b, which Oniguruma reads as a backspace control character. A verification
// tool whose escaping inverts the answer is worse than no check at all -- it
// was what made this bug look absent while it was actively blocking PR #1818.
//
// It also pins NO line numbers. This file moves constantly; the sidecar that
// pinned line numbers breaks on every shift. Assert on behaviour only.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  verdictOpensLine,
  isApprovalFor,
  isVerdictFor,
  anyVerdictFor,
  evidenceTiedToHead,
} from './manage-migration-author-lanes.mjs'

const HEAD = '8bb1886a31f89409d06c312d3a9005eff07a1cea'

// ---------------------------------------------------------------------------
// The two REAL comment bodies from PR #1818, verbatim, each in a body that also
// quotes the 40-character head. Copied from the live PR, not paraphrased: a
// test on a synthetic string would be a test of a different program.
// ---------------------------------------------------------------------------
const REAL_APPROVE_PROSE = [
  '**Branch frozen at `8bb1886a31f89409d06c312d3a9005eff07a1cea` while its review runs.**',
  '',
  'Remaining state is `BLOCKED`, which is correct — this needs its exact-head review. **Approval must be pinned to all forty characters of `8bb1886a31f89409d06c312d3a9005eff07a1cea`**, verdict opening its line, and it must be a review of *this delta*: if the reviewer is handed a merge commit with no base, it will review the incoming side and approve something else entirely, exactly as happened on #1813.',
].join('\n')

const REAL_REVISE_PROSE = [
  '**Conflict resolved. Settled head: `8bb1886a31f89409d06c312d3a9005eff07a1cea`. Now MERGEABLE.**',
  '',
  'Three further doctrine entries are ready and are being **deliberately withheld**, because `docs/agents/section-4-anti-collision-rules.md` is one of the six files under review. Pushing them would move the head and void the review — the fourth head in two hours, for prose that can wait an hour. Good additions do not justify moving a head under review; that is exactly the exemption this PR exists to refuse. They land as a follow-up documentation PR after merge, or ride along with any REVISE findings.',
].join('\n')

const comment = (body) => ({ body, state: undefined, commit_id: undefined })

test('both real #1818 progress notes are tied to the head', () => {
  // The tie is what made them dangerous; the fix must not work by accidentally
  // losing the tie.
  assert.equal(evidenceTiedToHead(comment(REAL_APPROVE_PROSE), HEAD), true)
  assert.equal(evidenceTiedToHead(comment(REAL_REVISE_PROSE), HEAD), true)
})

test('the OLD anywhere-in-body reading registered both notes as verdicts', () => {
  // Reproduces the defect exactly as it was written at all nine sites, so the
  // test proves a real behaviour CHANGE rather than merely asserting the new
  // behaviour into existence.
  const oldReading = (body) =>
    body.includes(HEAD) && /\b(?:APPROVE|REVISE|REQUEST_CHANGES)\b/i.test(body)
  assert.equal(oldReading(REAL_APPROVE_PROSE), true)
  assert.equal(oldReading(REAL_REVISE_PROSE), true)
})

test('neither real progress note registers as a verdict under the new rule', () => {
  assert.equal(isVerdictFor(comment(REAL_APPROVE_PROSE), HEAD), false)
  assert.equal(isVerdictFor(comment(REAL_REVISE_PROSE), HEAD), false)
  assert.equal(anyVerdictFor([comment(REAL_APPROVE_PROSE), comment(REAL_REVISE_PROSE)], HEAD), false)
})

test('neither real progress note satisfies the fail-OPEN preview approval gate', () => {
  assert.equal(isApprovalFor(comment(REAL_APPROVE_PROSE), HEAD), false)
  assert.equal(isApprovalFor(comment(REAL_REVISE_PROSE), HEAD), false)
})

// ---------------------------------------------------------------------------
// The capability must survive. A fix that blocks real approvals is not a fix.
// ---------------------------------------------------------------------------
test('a genuine APPROVE opening its line still registers', () => {
  for (const body of [
    `APPROVE\n\nReviewed ${HEAD}. Examined all six files.`,
    `**APPROVE**\n\nHead ${HEAD}.`,
    `> APPROVE\n\nHead ${HEAD}.`,
    `## APPROVED\n\nHead ${HEAD}.`,
    // The form the reviewer wrappers actually emit.
    `VERDICT: APPROVE\n\nHead ${HEAD}, seven-point review follows.`,
  ]) {
    assert.equal(isApprovalFor(comment(body), HEAD), true, body.split('\n')[0])
    assert.equal(isVerdictFor(comment(body), HEAD), true, body.split('\n')[0])
  }
})

test('a genuine refusal opening its line still registers', () => {
  for (const body of [
    `REVISE\n\nHead ${HEAD}. Critical: the adapter never receives this value.`,
    `**REVISE**\n\nHead ${HEAD}.`,
    `VERDICT: REJECT\n\nHead ${HEAD}.`,
    `REQUEST_CHANGES\n\nHead ${HEAD}.`,
  ]) {
    assert.equal(isVerdictFor(comment(body), HEAD), true, body.split('\n')[0])
    // A refusal is a verdict but is NOT an approval -- the asymmetry that
    // would otherwise let a refusal authorize a migration.
    assert.equal(isApprovalFor(comment(body), HEAD), false, body.split('\n')[0])
  }
})

test('structured GitHub review states are still trusted as data, not prose', () => {
  assert.equal(isApprovalFor({ body: '', state: 'APPROVED', commit_id: HEAD }, HEAD), true)
  assert.equal(isVerdictFor({ body: '', state: 'CHANGES_REQUESTED', commit_id: HEAD }, HEAD), true)
  assert.equal(isApprovalFor({ body: '', state: 'CHANGES_REQUESTED', commit_id: HEAD }, HEAD), false)
})

// ---------------------------------------------------------------------------
// The ninth site, which fails OPEN. This is the case live in the repository
// right now: sentences arguing about what approval ought to mean, and sentences
// stating that an approval is ABSENT.
// ---------------------------------------------------------------------------
test('prose stating an approval is ABSENT must not satisfy the preview gate', () => {
  for (const body of [
    `There is no APPROVE tied to ${HEAD}; the review slot is still empty.`,
    `PR #1821 merged with an assignment at ${HEAD} and no APPROVE pinned to it.`,
    `Head ${HEAD} has not been approved. Do not merge.`,
    `Approval must be pinned to all forty characters of ${HEAD}.`,
    `An APPROVE with no coverage statement is not review evidence — head ${HEAD}.`,
  ]) {
    assert.equal(isApprovalFor(comment(body), HEAD), false, body.slice(0, 60))
    assert.equal(isVerdictFor(comment(body), HEAD), false, body.slice(0, 60))
  }
})

test('a verdict word for a DIFFERENT head never counts for this head', () => {
  const other = '0be60cfc34fec94d87b6ea145cf7c6c8657cf968a'
  const body = `APPROVE\n\nReviewed ${other}.`
  assert.equal(isApprovalFor(comment(body), HEAD), false)
  assert.equal(isVerdictFor(comment(body), HEAD), false)
})

test('verdictOpensLine ignores a verdict word that does not open its line', () => {
  assert.equal(verdictOpensLine('we will approve later', /^APPROVE(?:D)?\b/i), false)
  assert.equal(verdictOpensLine('APPROVE', /^APPROVE(?:D)?\b/i), true)
  assert.equal(verdictOpensLine('line one\n   **APPROVE**', /^APPROVE(?:D)?\b/i), true)
  // Word-boundary discipline is preserved: APPROVEMENT is not APPROVE.
  assert.equal(verdictOpensLine('APPROVEMENT of the plan', /^APPROVE(?:D)?\b/i), false)
})

test('empty and malformed evidence is inert', () => {
  assert.equal(anyVerdictFor(undefined, HEAD), false)
  assert.equal(anyVerdictFor([], HEAD), false)
  assert.equal(isVerdictFor({}, HEAD), false)
  assert.equal(isApprovalFor(null, HEAD), false)
})
