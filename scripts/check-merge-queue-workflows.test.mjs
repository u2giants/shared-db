import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const required = [
  'coldlion-promotion-contract-tests.yml',
  'pr-object-collision.yml',
  'tools-offline-tests.yml',
  'shared-supabase-migrations.yml',
  'domain-ownership.yml',
  'intake-pointer-guard.yml',
  'handoff-contract-guard.yml',
  'migration-author-lease.yml',
  'orchestrator-marker-guard.yml',
  'cancelled-work-guard.yml',
]

test('every existing required Actions workflow runs for merge groups', () => {
  for (const name of required) {
    const text = readFileSync(new URL(`../.github/workflows/${name}`, import.meta.url), 'utf8')
    assert.match(text, /^  merge_group:\r?$/m, `${name} does not trigger for merge_group`)
    assert.match(text, /^    types: \[checks_requested\]\r?$/m, `${name} does not pin checks_requested`)
  }
})

test('the queue gate can become required before queue activation', () => {
  const text = readFileSync(new URL('../.github/workflows/merge-queue-gate.yml', import.meta.url), 'utf8')
  assert.match(text, /^  pull_request:\r?$/m)
  assert.match(text, /name: Merge queue gate/)
  assert.match(text, /^  statuses: write\r?$/m)
  assert.match(text, /MERGE_GROUP_REF: \$\{\{ github\.event\.merge_group\.head_ref \}\}/)
  assert.equal((text.match(/MERGE_GROUP_SHA: \$\{\{ github\.event\.merge_group\.head_sha \}\}/g) ?? []).length, 3)
  assert.match(text, /git merge-base --is-ancestor "\$pr_head" "\$MERGE_GROUP_SHA"/)
  assert.match(text, /statuses\/\$MERGE_GROUP_SHA/)
  assert.match(text, /context='Migration guarded merge authorization'/)
})

test('event-specific PR checks defer to the exact queue gate on merge_group', () => {
  for (const name of ['pr-object-collision.yml', 'handoff-contract-guard.yml', 'migration-author-lease.yml']) {
    const text = readFileSync(new URL(`../.github/workflows/${name}`, import.meta.url), 'utf8')
    assert.match(text, /if: github\.event_name != 'merge_group'/, `${name} must not consume absent pull_request payload fields`)
  }
})

test('the preview job can publish the exact-main rehearsal status', () => {
  const text = readFileSync(new URL('../.github/workflows/shared-supabase-migrations.yml', import.meta.url), 'utf8')
  const preview = text.match(/^  preview:\r?\n([\s\S]*?)^  production-dry-run:/m)?.[1] ?? ''
  assert.match(preview, /^    permissions:\r?\n(?:^      .+\r?\n)*?^      statuses: write\r?$/m)
  assert.match(preview, /context='Post-merge preview rehearsal'/)
})
