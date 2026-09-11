import { createHash } from 'node:crypto'
import { canonicalJson } from './evidence-bundle.mjs'

export class DeliveryPreflightError extends Error {}
export const DELIVERY_PREFLIGHT_SCHEMA_VERSION = 1
export const DELIVERY_CHECKS = Object.freeze([
  'route', 'work_contract', 'object_collision', 'dependencies', 'sidecars',
  'producers', 'migration_order', 'reviewer_capacity', 'runner_capacity',
])

const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const exactKeys = (value, keys, label) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new DeliveryPreflightError(`${label} must be an object`)
  const actual = Object.keys(value).sort()
  const expected = [...keys].sort()
  if (canonicalJson(actual) !== canonicalJson(expected)) throw new DeliveryPreflightError(`${label} must contain exactly ${expected.join(', ')}`)
}

export function deliveryPreflightInputs(input) {
  exactKeys(input, ['issue', 'pr', 'head_sha', 'checks'], 'preflight input')
  for (const key of ['issue', 'pr']) {
    if (!Number.isInteger(input[key]) || input[key] <= 0) throw new DeliveryPreflightError(`${key} must be a positive integer`)
  }
  if (!/^[0-9a-f]{40}$/i.test(input.head_sha)) throw new DeliveryPreflightError('head_sha must be an exact commit SHA')
  exactKeys(input.checks, DELIVERY_CHECKS, 'preflight checks')
  const checks = {}
  for (const name of DELIVERY_CHECKS) {
    const check = input.checks[name]
    exactKeys(check, ['status', 'evidence_id'], `check ${name}`)
    if (!['PASS', 'BLOCKED'].includes(check.status)) throw new DeliveryPreflightError(`check ${name} has invalid status`)
    if (typeof check.evidence_id !== 'string' || !check.evidence_id.trim()) throw new DeliveryPreflightError(`check ${name} lacks durable evidence`)
    checks[name] = { status: check.status, evidence_id: check.evidence_id }
  }
  return { issue: input.issue, pr: input.pr, head_sha: input.head_sha.toLowerCase(), checks }
}

export function runDeliveryPreflight(input) {
  const normalized = deliveryPreflightInputs(input)
  const inputDigest = sha256(canonicalJson(normalized))
  const blocked = DELIVERY_CHECKS.filter((name) => normalized.checks[name].status !== 'PASS')
  if (blocked.length) throw new DeliveryPreflightError(`delivery preflight blocked by ${blocked.join(', ')}`)
  return {
    schema_version: DELIVERY_PREFLIGHT_SCHEMA_VERSION,
    preflight_id: inputDigest,
    input_digest: inputDigest,
    status: 'PASS',
    input: normalized,
  }
}

export function reuseDeliveryPreflight(record, currentInput) {
  if (!record || record.schema_version !== DELIVERY_PREFLIGHT_SCHEMA_VERSION || record.status !== 'PASS') return null
  const normalized = deliveryPreflightInputs(currentInput)
  const currentDigest = sha256(canonicalJson(normalized))
  if (record.preflight_id !== record.input_digest || record.input_digest !== currentDigest) return null
  return record
}
