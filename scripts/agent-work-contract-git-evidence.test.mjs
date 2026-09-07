import test from 'node:test'
import assert from 'node:assert/strict'
import { verifyGitEvidence } from './agent-work-contract-git-evidence.mjs'

const base = 'a'.repeat(40)
const implementation = 'b'.repeat(40)
const prHead = 'c'.repeat(40)
const contract = { base_sha: base }
const report = { head_sha: implementation, files_changed: ['scripts/fix.mjs'] }
const io = (over = {}) => ({
  isAncestor: () => true,
  changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json'],
  ...over,
})

test('the implementation diff and evidence-only tail are accepted', () => {
  assert.equal(verifyGitEvidence({ contract, report, prHeadSha: prHead }, io()), true)
})

test('a self-reported file list cannot hide a changed file', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prHeadSha: prHead }, io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs', 'scripts/hidden.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })), /does not match Git/)
})

test('code changed after the reported head is refused', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prHeadSha: prHead }, io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json', 'scripts/late.mjs'] })), /only the two/)
})

test('both ancestry links and full SHAs are required', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prHeadSha: prHead }, io({ isAncestor: () => false })), /not an ancestor/)
  assert.throws(() => verifyGitEvidence({ contract: { base_sha: 'abc1234' }, report, prHeadSha: prHead }, io()), /40-character/)
})
