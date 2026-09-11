import test from 'node:test'
import assert from 'node:assert/strict'
import {
  DELIVERY_CHECKS,
  DeliveryPreflightError,
  reuseDeliveryPreflight,
  runDeliveryPreflight,
} from './delivery-preflight.mjs'

const input = () => ({
  issue: 2728,
  pr: 2800,
  head_sha: 'a'.repeat(40),
  checks: Object.fromEntries(DELIVERY_CHECKS.map((name) => [name, { status: 'PASS', evidence_id: `${name}-proof` }])),
})

test('one composed preflight binds every early gate to the exact head', () => {
  const result = runDeliveryPreflight(input())
  assert.equal(result.status, 'PASS')
  assert.equal(result.preflight_id, result.input_digest)
  assert.equal(reuseDeliveryPreflight(result, input()), result)
})

for (const name of DELIVERY_CHECKS) test(`missing or blocked ${name} refuses early`, () => {
  const blocked = input()
  blocked.checks[name].status = 'BLOCKED'
  assert.throws(() => runDeliveryPreflight(blocked), new RegExp(`blocked by ${name}`))
  const missing = input()
  delete missing.checks[name]
  assert.throws(() => runDeliveryPreflight(missing), DeliveryPreflightError)
})

test('changed head, evidence, or status invalidates reuse', () => {
  const original = input()
  const result = runDeliveryPreflight(original)
  const changedHead = input()
  changedHead.head_sha = 'b'.repeat(40)
  assert.equal(reuseDeliveryPreflight(result, changedHead), null)
  const changedEvidence = input()
  changedEvidence.checks.producers.evidence_id = 'new-producer-proof'
  assert.equal(reuseDeliveryPreflight(result, changedEvidence), null)
  const blocked = input()
  blocked.checks.runner_capacity.status = 'BLOCKED'
  assert.equal(reuseDeliveryPreflight(result, blocked), null)
})

test('unknown checks and evidence-free success fail closed', () => {
  const unknown = input()
  unknown.checks.extra = { status: 'PASS', evidence_id: 'x' }
  assert.throws(() => runDeliveryPreflight(unknown), /must contain exactly/)
  const emptyEvidence = input()
  emptyEvidence.checks.sidecars.evidence_id = ''
  assert.throws(() => runDeliveryPreflight(emptyEvidence), /lacks durable evidence/)
})
