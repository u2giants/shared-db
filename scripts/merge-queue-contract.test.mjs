import test from 'node:test'
import assert from 'node:assert/strict'
import { assertOldestMigration, baseNeedsPreview, migrationVersions, pullRequestFromQueueRef, readOpenPullRequests, readPullRequestFiles, verifyQueuePullRequest } from './merge-queue-contract.mjs'

test('extracts exactly one PR from a GitHub merge queue ref', () => {
  assert.equal(pullRequestFromQueueRef('refs/heads/gh-readonly-queue/main/pr-1435-deadbeef'), 1435)
  assert.throws(() => pullRequestFromQueueRef('refs/heads/main'), /expected one pull request/)
})

test('queue-ref PR identity is independently verified against live PR shape', () => {
  const row = { number: 1435, state: 'OPEN', baseRefName: 'main', headRefOid: 'a'.repeat(40) }
  assert.equal(verifyQueuePullRequest(1435, row), 1435)
  assert.throws(() => verifyQueuePullRequest(1436, row), /different pull request/)
  assert.throws(() => verifyQueuePullRequest(1435, { ...row, state: 'MERGED' }), /not open/)
  assert.throws(() => verifyQueuePullRequest(1435, { ...row, baseRefName: 'develop' }), /base is not main/)
})

test('REST pagination is slurped and flattened without a 100-PR window', () => {
  const run = args => {
    assert.ok(args.includes('--slurp'))
    if (args.at(-1).includes('/files?')) return JSON.stringify([[{ filename: 'README.md' }], [{ filename: 'docs/x.md' }]])
    return JSON.stringify([[{ number: 1, draft: false }], [{ number: 2, draft: true }]])
  }
  assert.deepEqual(readPullRequestFiles(1, run), ['README.md', 'docs/x.md'])
  assert.deepEqual(readOpenPullRequests(run), [
    { number: 1, isDraft: false, files: ['README.md', 'docs/x.md'] },
    { number: 2, isDraft: true, files: ['README.md', 'docs/x.md'] },
  ])
})

test('migration versions are exact, unique, and ordered', () => {
  assert.deepEqual(migrationVersions([
    'supabase/migrations/20260825120001_b.sql',
    'docs/x.md',
    'supabase/migrations/20260825120000_a.sql',
  ]), ['20260825120000', '20260825120001'])
})

test('oldest open migration PR must enter first', () => {
  const candidate = ['supabase/migrations/20260825120002_candidate.sql']
  assert.throws(() => assertOldestMigration(20, candidate, [
    { number: 19, isDraft: false, files: ['supabase/migrations/20260825120001_older.sql'] },
  ]), /behind open PR #19/)
  assert.equal(assertOldestMigration(20, candidate, [
    { number: 19, isDraft: true, files: ['supabase/migrations/20260825120001_older.sql'] },
    { number: 21, isDraft: false, files: ['supabase/migrations/20260825120003_newer.sql'] },
  ]).relevant, true)
})

test('non-migration PRs do not participate and migration merges require preview', () => {
  assert.equal(assertOldestMigration(20, ['README.md'], []).relevant, false)
  assert.equal(baseNeedsPreview(['README.md']), false)
  assert.equal(baseNeedsPreview(['supabase/migrations/20260825120000_x.sql']), true)
})
