import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')

test('contract runner starts without blanket licensing authorization', () => {
  const workflow = fs.readFileSync(
    path.join(root, '.github/workflows/database-contract-tests.yml'),
    'utf8',
  )
  const defaultArm = workflow.match(/\*\)\s+printf 'begin;\\n([^']*)'/)?.[1] ?? ''
  assert.ok(defaultArm.includes('\\ir %s'), 'wrapper must still execute each contract file')
  assert.ok(defaultArm.includes('rollback;'), 'wrapper must still roll every contract back')
  assert.doesNotMatch(
    defaultArm,
    /ci_authorize_licensing_contract_test/,
    'a default authorization makes guard-refusal contracts pass without exercising the guard',
  )
})

test('blanket helper is opt-in only in the known legacy contract', () => {
  const testsDir = path.join(root, 'supabase/tests')
  const callers = fs.readdirSync(testsDir)
    .filter(name => name.endsWith('.sql'))
    .filter(name => /select\s+public\.ci_authorize_licensing_contract_test\s*\(\s*\)/i.test(
      fs.readFileSync(path.join(testsDir, name), 'utf8'),
    ))
  assert.deepEqual(callers, ['clickup_task_import_contracts.sql'])
})
