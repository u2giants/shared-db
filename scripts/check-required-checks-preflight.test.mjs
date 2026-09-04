import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluatePreflight, evaluateWithoutRequiredList, observedStates, sanitize, PreflightError, SELF_CONTEXT } from './check-required-checks-preflight.mjs'

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

// The fallback used when `github.token` cannot read main's branch protection.
// It has to be STRICTLY STRONGER than the check it replaces, never weaker, and it
// must not read an unchecked head as a green one.
const REASON = 'HTTP 403: Resource not accessible by integration'

test('an unreadable required list is not a pass: every reported check must be green', () => {
  const result = evaluatePreflight({
    protectionUnreadable: REASON,
    statuses: [], checkRuns: [ok('SQL migration guards'), ok('Tools offline tests')],
  })
  assert.equal(result.mode, 'all-reported-checks')
  assert.equal(result.required, 2)
})

test('the fallback blocks a NON-required failing check, which the required-list test would have allowed', () => {
  const args = {
    statuses: [], checkRuns: [ok('SQL migration guards'), { name: 'optional lint', status: 'completed', conclusion: 'failure', completed_at: '2026-09-03T00:00:00Z' }],
  }
  assert.equal(evaluatePreflight({ ...args, requiredContexts: ['SQL migration guards'] }).required, 1)
  assert.throws(() => evaluatePreflight({ ...args, protectionUnreadable: REASON }), (e) => {
    assert.ok(e instanceof PreflightError)
    assert.ok(e.message.includes('optional lint (failure)'))
    return true
  })
})

test('a head with nothing reported at all is refused, not treated as green', () => {
  assert.throws(() => evaluatePreflight({ protectionUnreadable: REASON, statuses: [], checkRuns: [] }), (e) => {
    assert.ok(e.message.includes('NOTHING has reported'))
    return true
  })
})

test('the fallback names still-running checks separately from failing ones', () => {
  assert.throws(() => evaluateWithoutRequiredList({
    statuses: [], reason: REASON,
    checkRuns: [{ name: 'preview', status: 'in_progress', started_at: '2026-09-03T00:00:00Z' }],
  }), (e) => {
    assert.ok(e.message.includes('still running: preview'))
    return true
  })
})

test('the reason is flattened and bounded before it reaches a public workflow log', () => {
  assert.equal(sanitize('  HTTP 403:\n  not\taccessible  '), 'HTTP 403: not accessible')
  assert.equal(sanitize(''), 'no reason was reported')
  assert.equal(sanitize(undefined), 'no reason was reported')
  assert.equal(sanitize('x'.repeat(500)).length, 203)
})

test('a readable required list still takes precedence over the fallback', () => {
  const result = evaluatePreflight({
    protectionUnreadable: null,
    requiredContexts: ['SQL migration guards'],
    statuses: [], checkRuns: [ok('SQL migration guards')],
  })
  assert.equal(result.mode, 'required-contexts')
})
