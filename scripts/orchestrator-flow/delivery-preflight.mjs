import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { canonicalJson, validateEvidenceBundle } from './evidence-bundle.mjs'

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

export function validateDeliveryPreflight(record) {
  if(!record||record.schema_version!==DELIVERY_PREFLIGHT_SCHEMA_VERSION||record.status!=='PASS')throw new DeliveryPreflightError('passing preflight record is unreadable')
  const normalized=deliveryPreflightInputs(record.input)
  const digest=sha256(canonicalJson(normalized))
  if(record.preflight_id!==digest||record.input_digest!==digest)throw new DeliveryPreflightError('preflight seal does not match its canonical input')
  return record
}

export function reuseDeliveryPreflight(record, currentInput) {
  try{validateDeliveryPreflight(record)}catch{return null}
  const normalized = deliveryPreflightInputs(currentInput)
  const currentDigest = sha256(canonicalJson(normalized))
  if (record.preflight_id !== record.input_digest || record.input_digest !== currentDigest) return null
  return record
}

export function composeDeliveryPreflight({ issue, pr, head_sha }, adapters) {
  if (!adapters || typeof adapters !== 'object') throw new DeliveryPreflightError('preflight adapters are required')
  const checks={}
  for(const name of DELIVERY_CHECKS){
    if(typeof adapters[name]!=='function')throw new DeliveryPreflightError(`preflight adapter ${name} is required`)
    const result=adapters[name]({issue,pr,head_sha})
    checks[name]=result
  }
  return runDeliveryPreflight({issue,pr,head_sha,checks})
}

export function registerDeliveryPreflight(evidenceBundle, preflight) {
  try{validateEvidenceBundle(evidenceBundle)}catch(error){throw new DeliveryPreflightError(`evidence bundle is unreadable: ${error.message}`)}
  validateDeliveryPreflight(preflight)
  if(Number(evidenceBundle.metadata?.issue)!==preflight.input.issue||Number(evidenceBundle.metadata?.pr)!==preflight.input.pr||String(evidenceBundle.metadata?.integration_sha).toLowerCase()!==preflight.input.head_sha)throw new DeliveryPreflightError('preflight does not bind the evidence bundle issue, PR, and exact head')
  const registered={...evidenceBundle,metadata:{...evidenceBundle.metadata,delivery_preflight:{preflight_id:preflight.preflight_id,input_digest:preflight.input_digest}}}
  try{validateEvidenceBundle(registered)}catch(error){throw new DeliveryPreflightError(`preflight registration is invalid: ${error.message}`)}
  return registered
}

export function main(argv){
  try{
    const index=argv.indexOf('--input');if(index<0||!argv[index+1])throw new DeliveryPreflightError('--input <json> is required')
    const input=JSON.parse(readFileSync(argv[index+1],'utf8')),record=runDeliveryPreflight(input)
    console.log(JSON.stringify(record,null,2));return 0
  }catch(error){console.error(`REFUSED: ${error.message}`);return 2}
}
if(process.argv[1]&&path.resolve(fileURLToPath(import.meta.url))===path.resolve(process.argv[1]))process.exitCode=main(process.argv.slice(2))
