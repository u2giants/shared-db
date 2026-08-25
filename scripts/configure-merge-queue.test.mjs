import test from 'node:test'
import assert from 'node:assert/strict'
import { assertActivationReady, desiredRuleset, QUEUE_RULE } from './configure-merge-queue.mjs'

test('queue is exactly one all-green PR built and merged at a time', () => {
  assert.deepEqual(QUEUE_RULE.parameters, {
    check_response_timeout_minutes: 30,
    grouping_strategy: 'ALLGREEN',
    max_entries_to_build: 1,
    max_entries_to_merge: 1,
    merge_method: 'MERGE',
    min_entries_to_merge: 1,
    min_entries_to_merge_wait_minutes: 0,
  })
  assert.deepEqual(desiredRuleset().conditions.ref_name.include, ['refs/heads/main'])
})

test('activation refuses until code and both queue contexts are live on main', () => {
  const ready = { rulesets: [], contexts: ['Migration guarded merge authorization', 'Merge queue gate'], workflows: ['merge-queue-gate.yml'] }
  assert.equal(assertActivationReady(ready), null)
  assert.throws(() => assertActivationReady({ ...ready, contexts: ['Merge queue gate'] }), /guarded merge/)
  assert.throws(() => assertActivationReady({ ...ready, contexts: ['Migration guarded merge authorization'] }), /Merge queue gate/)
  assert.throws(() => assertActivationReady({ ...ready, workflows: [] }), /not present on main/)
})
