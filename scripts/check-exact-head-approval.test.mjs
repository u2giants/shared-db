import assert from 'node:assert/strict'
import test from 'node:test'
import { evaluateExactHeadApproval, parseAssignmentRef, ApprovalCheckError } from './check-exact-head-approval.mjs'

const OLD = 'b494401028464ef8b2e67fe0b5b1836839b2be36'
const NEW = '8d3c31accd5b21ea669e65f5ae53f5f95cc57337'

test('an approval tied to the exact head, with an assignment pinned to it, authorizes the merge', () => {
  const result = evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `APPROVE ${NEW}` }],
  })
  assert.equal(result.approved, true)
  assert.equal(result.approvals, 1)
})

// This is the exact sequence that put unapproved bytes on main in PR #1809:
// grok-4.6 was assigned OLD and REJECTed it, the author pushed NEW to answer the
// findings, and NEW merged. Nothing in the merge gate looked at NEW.
test('REJECT at one head, then a new commit answering it, does not authorize merging the new head', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: OLD }],
    evidence: [{ body: `REJECT ${OLD} -- anchor validation is wrong` }],
  }), (error) => error instanceof ApprovalCheckError && /no independent reviewer was ever assigned head/.test(error.message))
})

test('an APPROVE of an earlier head never approves the bytes actually being merged', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `APPROVE ${OLD}` }],
  }), /has no APPROVE tied to it/)
})

test('a reviewer assignment alone is not an approval', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [],
  }), /has no APPROVE tied to it/)
})

test('a refusal at the merged head outranks an approval at that same head', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `APPROVE ${NEW}` }, { body: `REVISE ${NEW}` }],
  }), /unanswered reviewer refusal/)
})

test('GitHub\'s own review states are honoured alongside body verdicts', () => {
  assert.equal(evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ commit_id: NEW, state: 'APPROVED', body: '' }],
  }).approved, true)
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ commit_id: NEW, state: 'CHANGES_REQUESTED', body: '' }],
  }), /unanswered reviewer refusal/)
})

test('assignments belonging to a different head are ignored even when several exist', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: OLD }, { issue: 1769, pr: 1809, headSha: 'c'.repeat(40) }],
    evidence: [{ body: `APPROVE ${NEW}` }],
  }), /no independent reviewer was ever assigned head/)
})

test('an inexact or missing head is refused rather than guessed', () => {
  assert.throws(() => evaluateExactHeadApproval({ pr: 1809, headSha: '8d3c31a' }), /exact 40-character head SHA/)
  assert.throws(() => evaluateExactHeadApproval({ pr: 0, headSha: NEW }), /exact pull request number/)
})

// A reviewer replaced after a failure keeps its assignment under the replacement
// namespace, and slot 2 assignments carry a `-slot<N>` suffix. Both are pinned to
// the same head, so both must count -- otherwise a merge whose review genuinely
// happened is refused for lack of an assignment that is sitting right there.
test('slot and replacement assignment refs are recognised as assignments at that head', () => {
  assert.deepEqual(parseAssignmentRef(`refs/db-review-assignments/1769-1809-${NEW}`), { issue: 1769, pr: 1809, headSha: NEW })
  assert.deepEqual(parseAssignmentRef(`refs/db-review-assignments/1769-1809-${NEW}-slot2`), { issue: 1769, pr: 1809, headSha: NEW })
  assert.deepEqual(parseAssignmentRef(`refs/db-review-replacements/1769-1809-${NEW}/1`), { issue: 1769, pr: 1809, headSha: NEW })
  assert.equal(parseAssignmentRef('refs/heads/main'), null)
  assert.equal(parseAssignmentRef(`refs/db-review-assignments/1769-1809-${NEW.slice(0, 7)}`), null)
})

// A lane locked its own PR by writing a progress note that named the head SHA and
// contained the word REVISE. The note read as a recorded refusal, and under this
// enforced gate that head becomes unmergeable with no comment-shaped symptom.
// A verdict leads its line; prose that mentions one does not.
test('a progress note mentioning a verdict word does not lock or approve a head', () => {
  const note = { body: `Status: pushed a fix at ${NEW}; the earlier REVISE findings are answered here.` }
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [note],
  }), /has no APPROVE tied to it/)
  assert.equal(evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [note, { body: `APPROVE ${NEW}` }],
  }).approved, true)
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `We should APPROVE ${NEW} once CI is green.` }],
  }), /has no APPROVE tied to it/)
})

test('a real verdict still counts through markdown emphasis, quoting and a later line', () => {
  assert.throws(() => evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `Reviewed head ${NEW}.\n\n**REVISE** -- the anchor is wrong.` }],
  }), /unanswered reviewer refusal/)
  assert.equal(evaluateExactHeadApproval({
    pr: 1809, headSha: NEW,
    assignments: [{ issue: 1769, pr: 1809, headSha: NEW }],
    evidence: [{ body: `> APPROVE ${NEW}` }],
  }).approved, true)
})
