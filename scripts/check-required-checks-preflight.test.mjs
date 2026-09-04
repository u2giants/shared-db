import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluatePreflight, evaluateWithoutRequiredList, gatherPreflightInput, isPermissionRefusal, observedStates, sanitize, PreflightError, SELF_CONTEXT } from './check-required-checks-preflight.mjs'

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

// The defects below were all live in the first attempt at this fix and every unit
// test still passed, because nothing exercised `gatherPreflightInput` -> `evaluatePreflight`.
const SHA = 'e'.repeat(40)
const ENV = { REQUESTED_SHA: SHA }
const reader = ({ protection, statuses = [], checkRuns = [] }) => (args) => {
  const path = args[1]
  if (path.includes('/protection/')) { if (protection instanceof Error) throw protection; return protection }
  if (path.includes('/status?')) return { statuses }
  return { check_runs: checkRuns }
}
const refusal = () => Object.assign(new PreflightError('GitHub read failed: HTTP 403: Resource not accessible by integration'), {})

test('a 403 on the protection read reaches evaluatePreflight as the fallback, not as "nothing required"', () => {
  const input = gatherPreflightInput(ENV, { json: reader({ protection: refusal(), checkRuns: [ok('SQL migration guards')] }) })
  assert.ok(input.protectionUnreadable)
  assert.equal(input.requiredContexts, null)
  assert.equal(evaluatePreflight(input).mode, 'all-reported-checks')
})

test('a 403 does not become a pass when the head is not green', () => {
  const input = gatherPreflightInput(ENV, { json: reader({ protection: refusal(), checkRuns: [{ name: 'SQL migration guards', status: 'completed', conclusion: 'failure', completed_at: '2026-09-03T00:00:00Z' }] }) })
  assert.throws(() => evaluatePreflight(input), PreflightError)
})

test('a transient failure refuses instead of silently degrading to the fallback', () => {
  const boom = new PreflightError('GitHub read failed: HTTP 502 Bad Gateway')
  assert.throws(() => gatherPreflightInput(ENV, { json: reader({ protection: boom }) }), (e) => e === boom)
  assert.equal(isPermissionRefusal('HTTP 502 Bad Gateway'), false)
  assert.equal(isPermissionRefusal('HTTP 403: Resource not accessible by integration'), true)
})

test('a 200 carrying an empty contexts list is refused, not read as "nothing is required"', () => {
  const input = gatherPreflightInput(ENV, { json: reader({ protection: { contexts: [] }, checkRuns: [ok('anything')] }) })
  assert.deepEqual(input.requiredContexts, [])
  assert.throws(() => evaluatePreflight(input), (e) => {
    assert.ok(e.message.includes('not the same as'))
    return true
  })
})

test('a readable protection list is passed through and used', () => {
  const input = gatherPreflightInput(ENV, { json: reader({ protection: { contexts: ['SQL migration guards'] }, checkRuns: [ok('SQL migration guards')] }) })
  assert.equal(input.protectionUnreadable, null)
  assert.equal(evaluatePreflight(input).mode, 'required-contexts')
})

test('the fallback refuses a head missing a check that reported on an earlier attempt', () => {
  // The dangerous case: green noise on the SHA and the real guard absent.
  assert.throws(() => evaluateWithoutRequiredList({
    statuses: [], reason: 'x',
    checkRuns: [ok('some unrelated job'), { name: 'SQL migration guards', status: 'queued', started_at: '2026-09-03T00:00:00Z' }],
  }), PreflightError)
})
