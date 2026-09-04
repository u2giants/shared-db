import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { collectPages, evaluatePreflight, evaluateWithoutRequiredList, gatherPreflightInput, isPermissionRefusal, observedStates, readRequiredChecksMirror, requireWholePage, sanitize, PreflightError, REQUIRED_CHECKS_MIRROR, SELF_CONTEXT, SELF_CHECK_RUN, PINNED_REQUIRED_CONTEXTS, MIRROR_BOOTSTRAP_MAIN_SHA } from './check-required-checks-preflight.mjs'

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
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['neutral guard'], statuses: [],
    checkRuns: [{ name: 'neutral guard', status: 'completed', conclusion: 'neutral' }],
  }), PreflightError)
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['skipped guard'], statuses: [],
    checkRuns: [{ name: 'skipped guard', status: 'completed', conclusion: 'skipped' }],
  }), PreflightError)
  assert.throws(() => evaluatePreflight({
    requiredContexts: ['empty guard'], statuses: [],
    checkRuns: [{ name: 'empty guard', status: 'completed', conclusion: '' }],
  }), PreflightError)
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

test('a newer check run beats an older commit status with the same exact name', () => {
  const states = observedStates({
    statuses: [{ context: 'Domain ownership', state: 'success', updated_at: '2026-09-03T00:00:00Z' }],
    checkRuns: [{ name: 'Domain ownership', status: 'completed', conclusion: 'failure', completed_at: '2026-09-03T01:00:00Z' }],
  })
  assert.equal(states.get('Domain ownership'), 'failure')
})

test('only the exact self-context is excluded', () => {
  assert.throws(() => evaluatePreflight({
    requiredContexts: [`${SELF_CONTEXT} extra`], statuses: [], checkRuns: [],
  }), new RegExp(`never reported: ${SELF_CONTEXT} extra`))
})

test('a missing required-contexts list is refused rather than read as "nothing required"', () => {
  assert.throws(() => evaluatePreflight({ requiredContexts: undefined, statuses: [], checkRuns: [] }),
    (e) => e instanceof PreflightError && /no required status check list/.test(e.message))
})

// ---------------------------------------------------------------------------
// #2274: the gaps the #2272 governed review named. Each of these was a mutation
// the suite would previously have stayed green through.
// ---------------------------------------------------------------------------

test('nothing but an explicit success satisfies a REQUIRED context', () => {
  // #2274 originally pinned `neutral` and `skipped` as passing for a required
  // context. #2276 tightened that: the merge API can still refuse a skipped or
  // neutral required check, so accepting one here would refuse AFTER taking the
  // merge lock instead of before. Only `success` counts, and this test now pins
  // the stricter rule rather than the one it replaced. `neutral` and `skipped`
  // remain passing for a NON-required reported check (REPORTED_SUCCESS), which
  // is a different set and is pinned by the fallback tests below.
  for (const conclusion of ['skipped', 'neutral']) {
    assert.throws(() => evaluatePreflight({
      requiredContexts: ['preview'], statuses: [],
      checkRuns: [{ name: 'preview', status: 'completed', conclusion }],
    }), (e) => e.message.includes(`failing: preview (${conclusion})`))
  }
  // `cancelled` and `timed_out` are NOT in the passing set either. A check that was
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

// The fallback used when `github.token` cannot read main's branch protection.
// It has to be STRICTLY STRONGER than the check it replaces, never weaker, and it
// must not read an unchecked head as a green one.
const REASON = 'HTTP 403: Resource not accessible by integration'

const MIRROR = ['SQL migration guards', 'Tools offline tests']

test('an unreadable required list uses the committed mirror, and every reported check must also be green', () => {
  const result = evaluatePreflight({
    protectionUnreadable: REASON, mirrorContexts: MIRROR,
    statuses: [], checkRuns: [ok('SQL migration guards'), ok('Tools offline tests')],
  })
  assert.equal(result.mode, 'committed-mirror')
  assert.equal(result.required, 2)
})

// THE COUNTEREXAMPLE A GOVERNED REVIEW FOUND, and the reason the reported-checks-only
// fallback was not, in fact, strictly stronger: one green non-required check on a head
// whose required context never reported at all. Without the mirror this PASSED.
test('the fallback refuses a head whose required context never reported, even with other checks green', () => {
  assert.throws(() => evaluatePreflight({
    protectionUnreadable: REASON, mirrorContexts: MIRROR,
    statuses: [], checkRuns: [ok('SQL migration guards')],
  }), (e) => {
    assert.ok(e.message.includes('never reported: Tools offline tests'))
    return true
  })
})

test('the mirror does not have to name the workflow own context', () => {
  const result = evaluatePreflight({
    protectionUnreadable: REASON, mirrorContexts: [...MIRROR, SELF_CONTEXT],
    statuses: [], checkRuns: [ok('SQL migration guards'), ok('Tools offline tests'),
      { name: SELF_CONTEXT, status: 'completed', conclusion: 'failure' }],
  })
  assert.equal(result.mode, 'committed-mirror')
})

// The mirror reader is given a fake `git show`; only origin/main may be read.
const mirrorRun = (byRef) => (bin, args) => {
  if (args[0] === 'rev-parse') {
    if (!('origin/main@sha' in byRef)) throw new Error('origin/main is unreadable')
    return byRef['origin/main@sha']
  }
  const ref = String(args[1]).split(':')[0]
  if (!(ref in byRef)) throw new Error(`fatal: path does not exist in '${ref}'`)
  return byRef[ref]
}
const doc = (...contexts) => JSON.stringify({ contexts })

test('a missing mirror on origin/main is refused, never replaced by the head copy', () => {
  assert.throws(() => readRequiredChecksMirror('/x', mirrorRun({})), (e) => {
    assert.ok(e.message.includes('trusted origin/main mirror'))
    return true
  })
})

test('an unusable mirror body is refused, never read as an empty required list', () => {
  for (const body of ['{}', '{"contexts":[]}', '{"contexts":"SQL migration guards"}', '{"contexts":[1,2]}', 'not json']) {
    assert.throws(() => readRequiredChecksMirror('/x', mirrorRun({ 'origin/main': body })), PreflightError)
  }
  assert.deepEqual(readRequiredChecksMirror('/x', mirrorRun({ 'origin/main': doc(...PINNED_REQUIRED_CONTEXTS) })), PINNED_REQUIRED_CONTEXTS)
})

test('THE HEAD CANNOT REMOVE A CONTEXT main REQUIRES — only main is tested', () => {
  // A pull request that deletes `Domain ownership` from its own copy of the mirror
  // must not thereby stop the pre-flight from requiring it.
  const contexts = readRequiredChecksMirror('/x', mirrorRun({
    'origin/main': doc(...PINNED_REQUIRED_CONTEXTS),
    HEAD: doc('SQL migration guards'),
  }))
  assert.deepEqual(contexts, PINNED_REQUIRED_CONTEXTS)
})

test('optional skipped jobs and the running merge job cannot deadlock the preflight', () => {
  const result = evaluateWithoutRequiredList({
    reason: REASON, mirrorContexts: MIRROR, statuses: [],
    checkRuns: [ok('SQL migration guards'), ok('Tools offline tests'),
      { name: 'preview', status: 'completed', conclusion: 'skipped' },
      { name: SELF_CHECK_RUN, status: 'in_progress', conclusion: null }],
  })
  assert.equal(result.mode, 'committed-mirror')
})

test('the head cannot inject a context into the trusted list', () => {
  const contexts = readRequiredChecksMirror('/x', mirrorRun({
    'origin/main': doc(...PINNED_REQUIRED_CONTEXTS),
    HEAD: doc('SQL migration guards', 'Brand new guard'),
  }))
  assert.deepEqual(contexts, PINNED_REQUIRED_CONTEXTS)
})

test('the first mirror merge bootstraps only at the exact reviewed main head', () => {
  assert.deepEqual(readRequiredChecksMirror('/x', mirrorRun({ 'origin/main@sha': MIRROR_BOOTSTRAP_MAIN_SHA })), PINNED_REQUIRED_CONTEXTS)
  assert.throws(() => readRequiredChecksMirror('/x', mirrorRun({ 'origin/main@sha': 'f'.repeat(40), HEAD: doc('SQL migration guards') })), /missing or unreadable/)
})

test('a mirror naming only the workflow own context would test nothing, so it is refused', () => {
  // The pre-flight strips SELF_CONTEXT before testing. A one-entry mirror of exactly
  // that name is non-empty and used to pass with zero required-check coverage.
  assert.throws(() => readRequiredChecksMirror('/x', mirrorRun({ 'origin/main': doc(SELF_CONTEXT) })), (e) => {
    assert.ok(e.message.includes('would test nothing'))
    return true
  })
})

test('the committed mirror on disk is real and includes the workflow own context', () => {
  const onDisk = JSON.parse(readFileSync(new URL(`../${REQUIRED_CHECKS_MIRROR}`, import.meta.url), 'utf8'))
  assert.ok(onDisk.contexts.includes(SELF_CONTEXT))
  assert.equal(onDisk.strict, false, 'strict must stay false — owner ruling, issue #1286')
})

// Pinning the exact list is the defence against mirror rot in the shrinking
// direction: the workflow reads origin/main, and origin/main can only change through
// a pull request whose tests must pass, so dropping a context here fails CI first.
test('the committed mirror is exactly the list main requires today', () => {
  const onDisk = JSON.parse(readFileSync(new URL(`../${REQUIRED_CHECKS_MIRROR}`, import.meta.url), 'utf8'))
  assert.deepEqual([...onDisk.contexts].sort(), [...PINNED_REQUIRED_CONTEXTS].sort())
  assert.equal(onDisk.strict, false, 'strict must stay false — owner ruling, issue #1286')
  assert.ok(onDisk.contexts.includes(SELF_CONTEXT))
})

test('a stale-subset HEAD mirror cannot hide a required main context', () => {
  const contexts = readRequiredChecksMirror('/x', mirrorRun({
    'origin/main': doc(...PINNED_REQUIRED_CONTEXTS),
    HEAD: doc('SQL migration guards'),
  }))
  assert.throws(() => evaluateWithoutRequiredList({
    statuses: [], reason: REASON, mirrorContexts: contexts,
    checkRuns: [ok('SQL migration guards')],
  }), /never reported:.*Domain ownership/)
})

test('a read that returned fewer checks than GitHub reports is refused, not judged partially', () => {
  // Since #2274 both reads paginate, so this can only fire if the pagination
  // itself came up short. It stays as the belt-and-braces check it always was:
  // judging the fallback's "every OTHER check is green" half on a partial list
  // is exactly how an unchecked head reads as a green one.
  assert.throws(() => requireWholePage('check runs', 140, [1, 2, 3]), (e) => {
    assert.ok(e.message.includes('pagination returned only 3'))
    return true
  })
  assert.equal(requireWholePage('check runs', 3, [1, 2, 3]), undefined)
  assert.equal(requireWholePage('check runs', undefined, [1]), undefined)
})

test('the fallback blocks a NON-required failing check, which the required-list test would have allowed', () => {
  const args = {
    statuses: [], checkRuns: [ok('SQL migration guards'), { name: 'optional lint', status: 'completed', conclusion: 'failure', completed_at: '2026-09-03T00:00:00Z' }],
  }
  assert.equal(evaluatePreflight({ ...args, requiredContexts: ['SQL migration guards'] }).required, 1)
  assert.throws(() => evaluatePreflight({ ...args, protectionUnreadable: REASON, mirrorContexts: ['SQL migration guards'] }), (e) => {
    assert.ok(e instanceof PreflightError)
    assert.ok(e.message.includes('optional lint (failure)'))
    return true
  })
})

test('a head with nothing reported at all is refused, not treated as green', () => {
  assert.throws(() => evaluatePreflight({ protectionUnreadable: REASON, mirrorContexts: MIRROR, statuses: [], checkRuns: [] }), (e) => {
    assert.ok(e.message.includes('never reported'))
    return true
  })
})

test('the fallback names still-running checks separately from failing ones', () => {
  assert.throws(() => evaluateWithoutRequiredList({
    statuses: [], reason: REASON, mirrorContexts: ['preview'],
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
const MIRROR_DEP = { root: '/x', run: () => doc(...PINNED_REQUIRED_CONTEXTS) }
const reader = ({ protection, statuses = [], checkRuns = [] }) => (args) => {
  const path = args[1]
  if (path.includes('/protection/')) { if (protection instanceof Error) throw protection; return protection }
  if (path.includes('/status?')) return { statuses }
  return { check_runs: checkRuns }
}
const refusal = () => Object.assign(new PreflightError('GitHub read failed: HTTP 403: Resource not accessible by integration'), {})

test('a 403 on the protection read reaches evaluatePreflight as the fallback, not as "nothing required"', () => {
  const input = gatherPreflightInput(ENV, { ...MIRROR_DEP, json: reader({ protection: refusal(), checkRuns: PINNED_REQUIRED_CONTEXTS.filter((context) => context !== SELF_CONTEXT).map(ok) }) })
  assert.ok(input.protectionUnreadable)
  assert.equal(input.requiredContexts, null)
  assert.deepEqual(input.mirrorContexts, PINNED_REQUIRED_CONTEXTS)
  assert.equal(evaluatePreflight(input).mode, 'committed-mirror')
})

test('a 403 does not become a pass when the head is not green', () => {
  const input = gatherPreflightInput(ENV, { ...MIRROR_DEP, json: reader({ protection: refusal(), checkRuns: [{ name: 'SQL migration guards', status: 'completed', conclusion: 'failure', completed_at: '2026-09-03T00:00:00Z' }] }) })
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
    statuses: [], reason: 'x', mirrorContexts: ['SQL migration guards'],
    checkRuns: [ok('some unrelated job'), { name: 'SQL migration guards', status: 'queued', started_at: '2026-09-03T00:00:00Z' }],
  }), PreflightError)
})
