#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'

export const PRODUCTION_PROJECT_REF = 'qsllyeztdwjgirsysgai'

export function validateRehearsal({ projectRef, fixtureId, databaseUrl, sql }) {
  if (!/^[a-z]{20}$/.test(projectRef ?? '')) throw new Error('project ref must be exactly 20 lowercase letters')
  if (projectRef === PRODUCTION_PROJECT_REF) throw new Error(`refusing production project ${PRODUCTION_PROJECT_REF}`)
  if (!/^AI-PERF-[0-9]{8}-[A-Za-z0-9][A-Za-z0-9_-]{2,80}$/.test(fixtureId ?? '')) throw new Error('fixture id must use AI-PERF-YYYYMMDD-name')
  let parsed
  try { parsed=new URL(databaseUrl) } catch { throw new Error('SUPABASE_DB_URL is not a valid PostgreSQL URL') }
  if (!['postgres:','postgresql:'].includes(parsed.protocol)) throw new Error('SUPABASE_DB_URL is not a PostgreSQL URL')
  const identity=`${decodeURIComponent(parsed.username)} ${parsed.hostname}`
  if (identity.includes(PRODUCTION_PROJECT_REF)) throw new Error(`refusing a connection identity that names production ${PRODUCTION_PROJECT_REF}`)
  const exactRef=new RegExp(`(^|[^a-z])${projectRef}([^a-z]|$)`)
  if (!exactRef.test(identity)) throw new Error('SUPABASE_DB_URL does not prove the requested preview project ref in its host or user identity')
  if (typeof sql !== 'string' || !sql.trim()) throw new Error('rehearsal SQL is empty')
  const stripped = sql.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, ' ')
  if (/^\s*\\/m.test(stripped)) throw new Error('psql meta-commands are not allowed in rehearsal SQL')
  if (/\b(begin|start\s+transaction|commit|rollback|savepoint|release\s+savepoint|prepare\s+transaction)\b/i.test(stripped)) throw new Error('rehearsal SQL cannot control its transaction')
  if (/\b(vacuum|alter\s+system|create\s+database|drop\s+database|reindex\s+[^;]*\bconcurrently)\b/i.test(stripped)) throw new Error('rehearsal SQL contains a statement that cannot be safely rolled back')
}

export function buildRehearsalSql({ projectRef, fixtureId, sql }) {
  const safeFixture = fixtureId.replaceAll("'", "''")
  return `\\set ON_ERROR_STOP on
\\echo TARGET_PROOF preview=${projectRef} production_refused=${PRODUCTION_PROJECT_REF}
BEGIN;
SET LOCAL statement_timeout = '30min';
SET LOCAL lock_timeout = '10s';
SELECT set_config('app.fixture_id', '${safeFixture}', true);
${sql.trim()}
ROLLBACK;
\\echo REHEARSAL_ROLLED_BACK fixture=${fixtureId}
`
}

export function parseArgs(argv) {
  const out = {}
  for (let i=0;i<argv.length;i++) {
    const arg=argv[i]
    if (arg==='--project-ref') out.projectRef=argv[++i]
    else if (arg==='--fixture-id') out.fixtureId=argv[++i]
    else if (arg==='--sql-file') out.sqlFile=argv[++i]
    else throw new Error(`unknown argument ${arg}`)
  }
  if (!out.projectRef || !out.fixtureId || !out.sqlFile) throw new Error('--project-ref, --fixture-id, and --sql-file are required')
  return out
}

export function main(argv=process.argv.slice(2), env=process.env) {
  const options=parseArgs(argv)
  const sql=readFileSync(options.sqlFile,'utf8')
  const databaseUrl=env.SUPABASE_DB_URL
  validateRehearsal({...options,databaseUrl,sql})
  const wrapped=buildRehearsalSql({...options,sql})
  console.log(`TARGET PROOF: preview ${options.projectRef}; production ${PRODUCTION_PROJECT_REF} refused; fixture ${options.fixtureId}`)
  const childEnv={...env,PGDATABASE:databaseUrl}
  delete childEnv.SUPABASE_DB_URL
  const result=spawnSync('psql',['--no-psqlrc','--file','-'],{input:wrapped,stdio:['pipe','inherit','inherit'],env:childEnv})
  if (result.error) throw result.error
  if (result.status!==0) throw new Error(`rehearsal failed with exit ${result.status}; PostgreSQL rolled back the open transaction`)
  return 0
}

if (import.meta.url===pathToFileURL(process.argv[1]).href) {
  try { process.exitCode=main() } catch (error) { console.error(`REFUSED: ${error.message}`); process.exitCode=1 }
}
