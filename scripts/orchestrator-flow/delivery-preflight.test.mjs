import test from 'node:test'
import assert from 'node:assert/strict'
import { canonicalJson, sha256, validateEvidenceBundle } from './evidence-bundle.mjs'
import {
  DELIVERY_CHECKS,
  DeliveryPreflightError,
  reuseDeliveryPreflight,
  runDeliveryPreflight,
  composeDeliveryPreflight,
  registerDeliveryPreflight,
} from './delivery-preflight.mjs'

const input = () => ({
  issue: 2728,
  pr: 2800,
  head_sha: 'a'.repeat(40),
  checks: Object.fromEntries(DELIVERY_CHECKS.map((name) => [name, { status: 'PASS', evidence_id: `${name}-proof` }])),
})

test('composition invokes every existing gate once and registers exact-head evidence',()=>{
  const calls=[]
  const adapters=Object.fromEntries(DELIVERY_CHECKS.map((name)=>[name,()=>{calls.push(name);return{status:'PASS',evidence_id:`${name}-proof`}}]))
  const result=composeDeliveryPreflight({issue:2728,pr:2800,head_sha:'a'.repeat(40)},adapters)
  assert.deepEqual(calls,DELIVERY_CHECKS)
  const identity={policy_version:1,migrations:[],focused_files:[],verification_files:[],claims:{writes:[],reads:[]},global_invalidators:[],migration_order_digest:'0'.repeat(64)}
  const bundle={schema_version:1,bundle_id:sha256(canonicalJson(identity)),identity,metadata:{issue:2728,pr:2800,claim:1,base_main_sha:'b'.repeat(40),integration_sha:'a'.repeat(40),review:null,ci:null}}
  const registered=registerDeliveryPreflight(bundle,result)
  assert.equal(registered.metadata.delivery_preflight.input_digest,result.input_digest)
  assert.equal(validateEvidenceBundle(registered),registered)
  bundle.metadata.integration_sha='b'.repeat(40)
  assert.throws(()=>registerDeliveryPreflight(bundle,result),/exact head/)
})

test('composition refuses before work when any gate adapter is absent',()=>{
  const adapters=Object.fromEntries(DELIVERY_CHECKS.slice(1).map((name)=>[name,()=>({status:'PASS',evidence_id:'proof'})]))
  assert.throws(()=>composeDeliveryPreflight({issue:1,pr:2,head_sha:'a'.repeat(40)},adapters),/adapter route is required/)
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
