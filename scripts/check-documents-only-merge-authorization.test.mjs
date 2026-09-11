import test from 'node:test'
import assert from 'node:assert/strict'
import { main } from './check-documents-only-merge-authorization.mjs'

const run = (rows) => {
  const out = []
  const err = []
  const code = main(['u2giants/shared-db', '2715'], { read: () => JSON.stringify(rows), out: (text) => out.push(text), err: (text) => err.push(text) })
  return { code, out: out.join(''), err: err.join('') }
}

test('documents, handoffs, and plans receive the lightweight merge authorization', () => {
  const result = run([{ filename: 'docs/note.md' }, { filename: 'HANDOFF.d/x.md' }, { filename: 'plan_delivery.md' }])
  assert.equal(result.code, 0)
  assert.match(result.out, /documents-only merge authorization/)
})

test('executable rulebooks retain the guarded path', () => {
  for (const path of ['AGENTS.md', 'CLAUDE.md', 'docs/task-router.md', 'skills/x/SKILL.md', '.claude/commands/x.md']) {
    assert.equal(run([{ filename: path, patch: '@@ -1 +1 @@\n-Run the old check.\n+Run the new check.' }]).code, 1, path)
  }
})

test('declarative routing pointers in rulebooks use the lightweight lane', () => {
  for (const path of ['AGENTS.md', 'docs/task-router.md', 'skills/x/SKILL.md']) {
    const result = run([{ filename: path, patch: '@@ -1,0 +2 @@\n+- Throughput plan: [plan](plan_delivery.md)' }])
    assert.equal(result.code, 0, path)
  }
})

test('rulebook pointer classification fails closed on missing patches and disguised behavior', () => {
  assert.equal(run([{ filename: 'AGENTS.md' }]).code, 1)
  assert.equal(run([{ filename: 'AGENTS.md', patch: '@@ -1,0 +2 @@\n+Read and apply [this plan](plan_delivery.md).' }]).code, 1)
  assert.equal(run([{ filename: 'AGENTS.md', patch: '@@ -1,0 +2 @@\n+- [Disable checks](plan_delivery.md)' }]).code, 1)
  assert.equal(run([{ filename: 'AGENTS.md', patch: '@@ -1,0 +2 @@\n+- [Safety plan](plan_delivery.md) skips checks' }]).code, 1)
  assert.equal(run([{ filename: 'docs/AGENTS.md', previous_filename: 'AGENTS.md', patch: '@@ -1 +1 @@\n-- [Old plan](old.md)\n+- [New plan](new.md)' }]).code, 1)
})

test('code, workflow, test, config, migration, mixed, rename-origin, and unknown input refuse', () => {
  for (const path of ['app.js', '.github/workflows/x.yml', 'scripts/x.mjs', 'config/x.json', 'supabase/migrations/20260101000000_x.sql']) {
    assert.equal(run([{ filename: 'docs/note.md' }, { filename: path }]).code, 1, path)
  }
  assert.equal(run([{ filename: 'docs/new.md', previous_filename: 'scripts/old.mjs' }]).code, 1)
  assert.equal(run([]).code, 1)
  assert.equal(main(['u2giants/shared-db', '2715'], { read: () => { throw new Error('offline') }, out: () => {}, err: () => {} }), 1)
})
