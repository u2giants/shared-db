import assert from 'node:assert/strict'
import test from 'node:test'
import { buildRehearsalSql, PRODUCTION_PROJECT_REF, validateRehearsal } from './run-preview-rehearsal-transaction.mjs'

const good={projectRef:'mvpkijzfmfcxhnzqogzs',fixtureId:'AI-PERF-20260830-inventory',databaseUrl:'postgresql://postgres.mvpkijzfmfcxhnzqogzs:redacted@host/postgres',sql:'insert into dflow.sample (sample_name) values (current_setting(\'app.fixture_id\'));\nselect count(*) from dflow.sample;'}

test('a preview rehearsal is wrapped in one rollback-only transaction',()=>{
  validateRehearsal(good)
  const wrapped=buildRehearsalSql(good)
  assert.match(wrapped,/TARGET_PROOF preview=mvpkijzfmfcxhnzqogzs/)
  assert.ok(wrapped.indexOf('BEGIN;') < wrapped.indexOf(good.sql) && wrapped.indexOf(good.sql) < wrapped.indexOf('ROLLBACK;'))
  assert.match(wrapped,/set_config\('app.fixture_id', 'AI-PERF-20260830-inventory', true\)/)
})

test('production and an unproved connection are hard-refused',()=>{
  assert.throws(()=>validateRehearsal({...good,projectRef:PRODUCTION_PROJECT_REF,databaseUrl:`postgresql://postgres.${PRODUCTION_PROJECT_REF}:x@host/postgres`}),/refusing production/)
  assert.throws(()=>validateRehearsal({...good,databaseUrl:'postgresql://postgres.somewhereelse:x@host/postgres'}),/does not prove/)
  assert.throws(()=>validateRehearsal({...good,databaseUrl:`postgresql://postgres.${PRODUCTION_PROJECT_REF}:mvpkijzfmfcxhnzqogzs@host/postgres`}),/names production/)
  assert.throws(()=>validateRehearsal({...good,databaseUrl:'https://postgres.mvpkijzfmfcxhnzqogzs:x@host/postgres'}),/not a PostgreSQL URL/)
})

test('SQL cannot escape or weaken the rollback boundary',()=>{
  for (const sql of ['commit;','rollback;','begin; select 1;','\\i unsafe.sql','vacuum dflow.sample','alter system set work_mem=1']) {
    assert.throws(()=>validateRehearsal({...good,sql}),/cannot|not allowed/)
  }
})

test('fixture identity is explicit and bounded',()=>{
  for (const fixtureId of ['inventory','AI-PERF-inventory','AI-PERF-20260830-x;drop','AI-PERF-20260830-']) assert.throws(()=>validateRehearsal({...good,fixtureId}),/fixture id/)
})

test('the secret URL is inherited by psql and never placed in its command arguments',()=>{
  const source=new URL('./run-preview-rehearsal-transaction.mjs',import.meta.url)
  return import('node:fs').then(({readFileSync})=>{
    const text=readFileSync(source,'utf8')
    assert.match(text,/PGDATABASE:databaseUrl/)
    assert.doesNotMatch(text,/spawnSync\('psql',[^\n]*databaseUrl/)
  })
})
