import assert from 'node:assert/strict'
import test from 'node:test'
import { evaluateExactHeadApproval, ApprovalCheckError } from './check-exact-head-approval.mjs'

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
