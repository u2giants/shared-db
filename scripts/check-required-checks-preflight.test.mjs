import test from 'node:test'
import assert from 'node:assert/strict'
import { collectPages, evaluatePreflight, observedStates, PreflightError, SELF_CONTEXT } from './check-required-checks-preflight.mjs'

const ok = (name) => ({ name, status: 'completed', conclusion: 'success', completed_at: '2026-09-03T00:00:00Z' })

test('a fully green head passes and does not require the workflow\'s own context', () => {
  const result = evaluatePreflight({
    requiredContexts: ['SQL migration guards', SELF_CONTEXT],
    statuses: [], checkRuns: [ok('SQL migration guards')],
  })
  assert.equal(result.required, 1)
})

test('a required check that never reported is refused by name — the #1175 case', () => {
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['SQL migration guards', 'Domain ownership'],
    statuses: [], checkRuns: [ok('SQL migration guards')],
  }), (e) => e instanceof PreflightError && /never reported: Domain ownership/.test(e.message))
})

test('a failing required check is refused with its state', () => {
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['Cross-PR object collision'],
    statuses: [], checkRuns: [{ name: 'Cross-PR object collision', status: 'completed', conclusion: 'failure' }],
  }), (e) => /failing: Cross-PR object collision \(failure\)/.test(e.message))
})

test('an in-progress required check is pending, not passing', () => {
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['Tools offline tests'],
    statuses: [], checkRuns: [{ name: 'Tools offline tests', status: 'in_progress', conclusion: null }],
  }), (e) => /still running: Tools offline tests/.test(e.message))
})

test('a commit status can satisfy a required context', () => {
  assert.equal(evaluatePreflight({
    requiredContexts: ['Handoff contract'],
    statuses: [{ context: 'Handoff contract', state: 'success', updated_at: '2026-09-03T00:00:00Z' }],
    checkRuns: [],
  }).required, 1)
})

test('the latest report wins when a context was re-run', () => {
  const states = observedStates({
    statuses: [
      { context: 'Intake pointer guard', state: 'failure', updated_at: '2026-09-03T00:00:00Z' },
      { context: 'Intake pointer guard', state: 'success', updated_at: '2026-09-03T01:00:00Z' },
    ], checkRuns: [],
  })
  assert.equal(states.get('Intake pointer guard'), 'success')
  const stale = observedStates({
    statuses: [
      { context: 'Intake pointer guard', state: 'success', updated_at: '2026-09-03T00:00:00Z' },
      { context: 'Intake pointer guard', state: 'failure', updated_at: '2026-09-03T01:00:00Z' },
    ], checkRuns: [],
  })
  assert.equal(stale.get('Intake pointer guard'), 'failure')
})

test('a missing required-contexts list is refused rather than read as "nothing required"', () => {
  assert.throws(() => evaluatePreflight({ requiredContexts: undefined, statuses: [], checkRuns: [] }),
    (e) => e instanceof PreflightError && /no required status check list/.test(e.message))
})

// ---------------------------------------------------------------------------
// #2274: the gaps the #2272 governed review named. Each of these was a mutation
// the suite would previously have stayed green through.
// ---------------------------------------------------------------------------

test('neutral and skipped count as passing, and nothing else silently does', () => {
  assert.equal(evaluatePreflight({
    requiredContexts: ['preview', 'production-dry-run'],
    statuses: [],
    checkRuns: [
      { name: 'preview', status: 'completed', conclusion: 'skipped' },
      { name: 'production-dry-run', status: 'completed', conclusion: 'neutral' },
    ],
  }).required, 2)
  // `cancelled` and `timed_out` are NOT in the passing set. A check that was
  // cancelled reported no result; treating it as passing is the whole failure
  // this pre-flight exists to prevent.
  for (const conclusion of ['cancelled', 'timed_out', 'action_required', 'stale']) {
    assert.throws(() => evaluatePreflight({
      requiredContexts: ['preview'], statuses: [],
      checkRuns: [{ name: 'preview', status: 'completed', conclusion }],
    }), (e) => e.message.includes(`failing: preview (${conclusion})`))
  }
})

test('a completed check run with no conclusion is pending, not passing', () => {
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['Domain ownership'], statuses: [],
    checkRuns: [{ name: 'Domain ownership', status: 'completed', conclusion: null }],
  }), (e) => /still running: Domain ownership/.test(e.message))
})

test('the self-context filter is an exact match, not a substring', () => {
  // A context merely CONTAINING the workflow's own name must still be required.
  // A substring filter here would silently drop a real required check.
  assert.throws(() => evaluatePreflight({
    requiredContexts: [SELF_CONTEXT, `${SELF_CONTEXT} (dry run)`],
    statuses: [], checkRuns: [],
  }), (e) => e.message.includes(`never reported: ${SELF_CONTEXT} (dry run)`))
})

test('when a commit status and a check run share one name, the later report wins', () => {
  const statusLater = observedStates({
    statuses: [{ context: 'Handoff contract', state: 'failure', updated_at: '2026-09-03T02:00:00Z' }],
    checkRuns: [{ name: 'Handoff contract', status: 'completed', conclusion: 'success', completed_at: '2026-09-03T01:00:00Z' }],
  })
  assert.equal(statusLater.get('Handoff contract'), 'failure')
  const runLater = observedStates({
    statuses: [{ context: 'Handoff contract', state: 'failure', updated_at: '2026-09-03T01:00:00Z' }],
    checkRuns: [{ name: 'Handoff contract', status: 'completed', conclusion: 'success', completed_at: '2026-09-03T02:00:00Z' }],
  })
  assert.equal(runLater.get('Handoff contract'), 'success')
})

test('every page of a paginated read is collected, not only the first', () => {
  // The real failure this prevents: past 100 reports on one head, a context that
  // DID pass comes back absent and the merge is refused for an unactionable reason.
  const rows = collectPages([
    { statuses: [{ context: 'a' }, { context: 'b' }] },
    { statuses: [{ context: 'c' }] },
  ], 'statuses')
  assert.deepEqual(rows.map((r) => r.context), ['a', 'b', 'c'])
  // A single unwrapped object still works, so the shape is not load-bearing.
  assert.equal(collectPages({ statuses: [{ context: 'a' }] }, 'statuses').length, 1)
  // A page with the key absent contributes nothing rather than throwing.
  assert.equal(collectPages([{}], 'statuses').length, 0)
  // A page whose key is not a list is refused rather than skipped.
  assert.throws(() => collectPages([{ statuses: 'nope' }], 'statuses'),
    (e) => e instanceof PreflightError && /non-list "statuses" page/.test(e.message))
})

test('a 200 whose body carries no contexts list is refused, not read as "nothing required"', () => {
  // The 404 case already failed closed. THIS is the 200-shaped fail-open the
  // #2272 review found: `protection?.contexts ?? []` turned a bodyless success
  // into zero required checks, and zero required checks pass having checked nothing.
  for (const requiredContexts of [undefined, null, {}, 'SQL migration guards']) {
    assert.throws(() => evaluatePreflight({ requiredContexts, statuses: [], checkRuns: [] }),
      (e) => e instanceof PreflightError && /no required status check list/.test(e.message))
  }
})
