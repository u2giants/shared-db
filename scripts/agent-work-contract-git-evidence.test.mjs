import test from 'node:test'
import assert from 'node:assert/strict'
import { verifyGitEvidence } from './agent-work-contract-git-evidence.mjs'

const base = 'a'.repeat(40)
const prBase = 'd'.repeat(40)
const implementation = 'b'.repeat(40)
const prHead = 'c'.repeat(40)
const contract = {
  schema_version: 1, work_issue: 42, generation: 1, work_type: 'repo-maintenance', route: 'repo-maintenance',
  goal: 'fix the guard', base_sha: base, dispatcher: 'repo-session', worker: 'codex', branch: 'codex/fix', worktree: 'worktrees/fix',
  allowed_paths: ['scripts/**'], file_writes: ['scripts/fix.mjs'], db_reads: [], db_writes: [], prohibited_actions: ['no database writes'],
  required_checks: ['node --test'], assumptions: [], stop_conditions: ['stop on scope change'],
}
const report = { head_sha: implementation, files_changed: ['scripts/fix.mjs'], contract_ref: 'refs/db-contracts/42/1' }
const io = (over = {}) => ({
  isAncestor: () => true,
  changedFiles: (from) => from === prBase ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json'],
  readPublishedContract: () => contract,
  ...over,
})

test('the implementation diff and evidence-only tail are accepted', () => {
  assert.equal(verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io()), true)
})

test('a self-reported file list cannot hide a changed file', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ changedFiles: (from) => from === prBase ? ['scripts/fix.mjs', 'scripts/hidden.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })), /does not match Git/)
})

test('code changed after the reported head is refused', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ changedFiles: (from) => from === prBase ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json', 'scripts/late.mjs'] })), /only the two/)
})

test('both ancestry links and full SHAs are required', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ isAncestor: () => false })), /not an ancestor/)
  assert.throws(() => verifyGitEvidence({ contract: { ...contract, base_sha: 'abc1234' }, report, prBaseSha: prBase, prHeadSha: prHead }, io()), /40-character/)
})

test('the checked-in contract must match its exact immutable published ref', () => {
  assert.throws(() => verifyGitEvidence({ contract, report: { ...report, contract_ref: 'refs/db-contracts/42/2' }, prBaseSha: prBase, prHeadSha: prHead }, io()), /exact immutable ref/)
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ readPublishedContract: () => ({ ...contract, goal: 'wider after the fact' }) })), /does not match/)
})
