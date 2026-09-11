// A merge-from-main refresh keeps an APPROVE; a change of the author's own does not (#2758).
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { isContentPreservingRefresh } from './pr-content-equivalence.mjs'

const git = (repo, args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
function write(repo, files) { for (const [path, body] of Object.entries(files)) { mkdirSync(dirname(join(repo, path)), { recursive: true }); writeFileSync(join(repo, path), body) } }
function commit(repo, files, message) { write(repo, files); git(repo, ['add', '-A']); git(repo, ['commit', '-q', '-m', message]); return git(repo, ['rev-parse', 'HEAD']).trim() }

// main: seed. PR branch: a migration + evidence, approved at A. main then gains
// unrelated code, and the branch merges main (head B).
function fixture() {
  const repo = mkdtempSync(join(tmpdir(), 'pr-equiv-'))
  git(repo, ['init', '-q', '-b', 'main']); git(repo, ['config', 'user.email', 't@example.invalid']); git(repo, ['config', 'user.name', 'T']); git(repo, ['config', 'commit.gpgsign', 'false'])
  commit(repo, { 'seed.sql': 'select 1;\n', '.agent/contract.json': '{"head":"seed"}\n' }, 'seed')
  git(repo, ['switch', '-q', '-c', 'pr'])
  const approved = commit(repo, { 'supabase/migrations/20260911120000_add_thing.sql': 'create table thing (id int);\n', '.agent/contract.json': '{"head":"a"}\n' }, 'pr change')
  git(repo, ['switch', '-q', 'main'])
  commit(repo, { 'scripts/other.mjs': 'export const x = 1\n', 'supabase/migrations/20260911110000_other.sql': 'select 2;\n' }, 'main moves')
  git(repo, ['switch', '-q', 'pr'])
  git(repo, ['merge', '-q', '--no-edit', 'main'])
  const refreshed = git(repo, ['rev-parse', 'HEAD']).trim()
  return { repo, approved, refreshed }
}
const check = (repo, approvedHead, head) => isContentPreservingRefresh({ approvedHead, head, mainRef: 'main', gitRunner: (args) => git(repo, args) })

test('a merge-only refresh from main keeps the approval', () => {
  const { repo, approved, refreshed } = fixture()
  try { const proof = check(repo, approved, refreshed); assert.equal(proof.ok, true, proof.reason) } finally { rmSync(repo, { recursive: true, force: true }) }
})

test('POSITIVE CONTROL: a refresh that also edits the migration needs a new review', () => {
  const { repo, approved } = fixture()
  try {
    const edited = commit(repo, { 'supabase/migrations/20260911120000_add_thing.sql': 'create table thing (id bigint);\n' }, 'edit migration')
    const proof = check(repo, approved, edited)
    assert.equal(proof.ok, false); assert.match(proof.reason, /diff changed/)
  } finally { rmSync(repo, { recursive: true, force: true }) }
})

test('POSITIVE CONTROL: a whitespace-only edit inside SQL is a change', () => {
  const { repo, approved } = fixture()
  try {
    const edited = commit(repo, { 'supabase/migrations/20260911120000_add_thing.sql': 'create table thing  (id int);\n' }, 'whitespace')
    assert.equal(check(repo, approved, edited).ok, false)
  } finally { rmSync(repo, { recursive: true, force: true }) }
})

test('an .agent evidence-only change keeps the approval', () => {
  const { repo, approved, refreshed } = fixture()
  try {
    const evidence = commit(repo, { '.agent/contract.json': `{"head":"${refreshed}"}\n`, '.agent/completion.json': '{}\n' }, 'bind evidence')
    const proof = check(repo, approved, evidence); assert.equal(proof.ok, true, proof.reason)
  } finally { rmSync(repo, { recursive: true, force: true }) }
})

test('POSITIVE CONTROL: a rewritten branch is not a refresh even with the same diff', () => {
  const { repo, approved } = fixture()
  try {
    git(repo, ['switch', '-q', '-c', 'rewrite', 'main'])
    const rebuilt = commit(repo, { 'supabase/migrations/20260911120000_add_thing.sql': 'create table thing (id int);\n', '.agent/contract.json': '{"head":"a"}\n' }, 'rebased')
    const proof = check(repo, approved, rebuilt)
    assert.equal(proof.ok, false); assert.match(proof.reason, /not an ancestor/)
  } finally { rmSync(repo, { recursive: true, force: true }) }
})

test('POSITIVE CONTROL: an unreadable head is not equivalent', () => {
  const { repo, approved } = fixture()
  try { assert.equal(check(repo, approved, 'f'.repeat(40)).ok, false) } finally { rmSync(repo, { recursive: true, force: true }) }
})
