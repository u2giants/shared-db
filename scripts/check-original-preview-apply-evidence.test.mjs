import assert from 'node:assert/strict'
import test from 'node:test'
import { selectOriginalPreviewApplyEvidence } from './manage-migration-author-lanes.mjs'

const PR = 1809
const VERSION = '20260828232207'
const HEAD = '75a6e35e46a79af7c059836a64a5b621ac79404a'
const ready = [{
  schema_version: 2,
  event_type: 'preview_ready',
  result: 'succeeded',
  pr: PR,
  route: 'merged_rehearsal',
  route_context: HEAD,
}]
const run = { id: 33308168016, conclusion: 'success', event: 'workflow_dispatch', path: '.github/workflows/shared-supabase-migrations.yml', head_sha: HEAD }
const binding = { schema: 'shared-db-preview-instance-binding/v1', runId: run.id, sourcePr: PR, appliedCommit: HEAD, allowlist: [VERSION] }

const select = ({ events=ready, runs=[run], proof=binding }={}) => selectOriginalPreviewApplyEvidence({
  pr: PR,
  versions: [VERSION],
  events,
  runs: () => runs,
  loadBinding: () => proof,
})

test('selects one successful immutable preview-apply binding', () => {
  assert.deepEqual(select(), { type: 'preview-apply', run_id: String(run.id) })
})

test('missing evidence remains absent instead of guessing', () => {
  assert.equal(select({ events: [] }), null)
  assert.equal(select({ runs: [] }), null)
  assert.equal(select({ proof: null }), null)
})

test('wrong run, PR, commit, allowlist, workflow, or outcome is rejected', () => {
  for (const proof of [
    { ...binding, runId: 9 },
    { ...binding, sourcePr: 99 },
    { ...binding, appliedCommit: 'a'.repeat(40) },
    { ...binding, allowlist: ['20260829004145'] },
  ]) assert.equal(select({ proof }), null)
  assert.equal(select({ runs: [{ ...run, conclusion: 'failure' }] }), null)
  assert.equal(select({ runs: [{ ...run, path: '.github/workflows/other.yml' }] }), null)
})

test('ambiguous successful runs fail closed', () => {
  const other = { ...run, id: 33308168017 }
  assert.throws(() => selectOriginalPreviewApplyEvidence({
    pr: PR,
    versions: [VERSION],
    events: ready,
    runs: () => [run, other],
    loadBinding: (candidate) => ({ ...binding, runId: candidate.id }),
  }), /multiple original preview-apply runs/)
})
