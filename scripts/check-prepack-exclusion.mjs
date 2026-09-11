#!/usr/bin/env node
// Issue #2611: guard the prepack exclusion so it cannot silently regress.
//
// Owner ruling (docs/business-rules/product-items-and-identifiers.md, 2026-09-06):
// prepacks "must be excluded from any population being assessed for missing
// Licensor or Property, not chased for attribution." That rule lived only in
// prose for months and was never implemented; this script exists so that if the
// implementation is weakened or reverted, a check goes red instead of a known
// assortment head quietly reappearing in a missing-attribution population.
//
// This repository's check scripts validate repository artifacts offline -- none
// of them opens a database connection, and this one does not either. It
// therefore guards the DEFINITION: the newest migration that defines the
// missing-attribution population must route its assortment test through
// plm.prepack_role, and plm.prepack_role must keep testing both roles against
// ColdLion. A live-data assertion belongs to the promotion run, not to CI.
//
// Named fixture, re-derived against production on 2026-09-11 and recorded with
// its query in docs/verification/prepack-exclusion-20260911.md: seven prepack
// heads sit in a LICENSED division and are missing attribution today. A head in
// EH001/EP001 would prove nothing, because the non-licensed-division rule
// removes it whether or not the prepack filter works.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const MIGRATIONS = path.join(ROOT, 'supabase/migrations')
const VERIFICATION = 'docs/verification/prepack-exclusion-20260911.md'

export const POPULATION_VIEW = 'plm.item_missing_attribution'
export const ROLE_FUNCTION = 'plm.prepack_role'

// Prepack heads in a licensed division, missing attribution on 2026-09-11.
export const KNOWN_LICENSED_DIVISION_HEADS = [
  'AA814DYCR01',
  'AAH62NBEX01',
  'AAH62WBLB01',
  'VF122FKFK01',
  'VF122FKFK02',
  'VF122FKFK03',
  'VFS22FKFK01',
]

// The exclusions that must survive, in the order they bite. Non-licensed
// divisions first: see unmapped-licensor-population.md.
const NON_LICENSED_DIVISIONS = ['EH001', 'EP001']

const strip = (sql) =>
  sql
    .split('\n')
    .map((line) => line.replace(/--.*$/, ''))
    .join('\n')

/**
 * Pure inspection of one migration's SQL text. Exported so the test can feed it
 * a known-dirty variant: a guard that has never been shown to fail is not
 * evidence that anything passed.
 */
export function inspect(sqlText) {
  const failures = []
  const sql = strip(sqlText).toLowerCase()

  const viewMatch = sql.match(
    new RegExp(`create\\s+(or\\s+replace\\s+)?view\\s+${POPULATION_VIEW}\\b[\\s\\S]*?;`),
  )
  if (!viewMatch) {
    failures.push(`no definition of view ${POPULATION_VIEW} found`)
    return failures
  }
  const body = viewMatch[0]

  if (!body.includes(ROLE_FUNCTION)) {
    failures.push(
      `${POPULATION_VIEW} does not call ${ROLE_FUNCTION}: a known assortment head ` +
        `(e.g. ${KNOWN_LICENSED_DIVISION_HEADS[0]}) would reappear as a missing-attribution row`,
    )
  } else if (!/plm\.prepack_role\s*\([\s\S]*?\)\s*is\s+null/.test(body)) {
    failures.push(
      `${POPULATION_VIEW} calls ${ROLE_FUNCTION} but does not require it to be null; ` +
        'both heads and members must be excluded',
    )
  }

  for (const division of NON_LICENSED_DIVISIONS) {
    if (!body.includes(division.toLowerCase())) {
      failures.push(
        `${POPULATION_VIEW} does not exclude non-licensed division ${division} ` +
          '(owner ruling 2026-09-06)',
      )
    }
  }

  if (body.includes('erp_items_current')) {
    failures.push(
      `${POPULATION_VIEW} references public.erp_items_current, which is a frozen ` +
        'DesignFlow snapshot whose prepack rows are members, not heads (#2611), and ' +
        'is being retired by #2482',
    )
  }

  const fnMatch = sql.match(
    new RegExp(`create\\s+(or\\s+replace\\s+)?function\\s+${ROLE_FUNCTION}\\b[\\s\\S]*?\\$\\$;`),
  )
  if (fnMatch) {
    const fn = fnMatch[0]
    if (!fn.includes('coldlion.prod_history_component')) {
      failures.push(
        `${ROLE_FUNCTION} no longer tests heads against ` +
          'coldlion.prod_history_component, the transaction-attested head source',
      )
    }
    if (!fn.includes('coldlion.item_detail')) {
      failures.push(
        `${ROLE_FUNCTION} no longer tests members against coldlion.item_detail`,
      )
    }
    for (const role of ['head', 'member']) {
      if (!fn.includes(`'${role}'`)) {
        failures.push(`${ROLE_FUNCTION} no longer returns '${role}'`)
      }
    }
  }

  return failures
}

function migrationsDefiningPopulation() {
  return fs
    .readdirSync(MIGRATIONS)
    .filter((name) => name.endsWith('.sql'))
    .sort()
    .filter((name) =>
      strip(fs.readFileSync(path.join(MIGRATIONS, name), 'utf8')).includes(POPULATION_VIEW),
    )
}

function main() {
  const failures = []
  const defining = migrationsDefiningPopulation()

  if (defining.length === 0) {
    failures.push(
      `no migration defines ${POPULATION_VIEW}; the prepack exclusion is prose again (#2611)`,
    )
  } else {
    // The newest definition is the one the database ends up with.
    const newest = defining[defining.length - 1]
    const sql = fs.readFileSync(path.join(MIGRATIONS, newest), 'utf8')
    for (const failure of inspect(sql)) failures.push(`${newest}: ${failure}`)
  }

  const note = path.join(ROOT, VERIFICATION)
  if (!fs.existsSync(note)) {
    failures.push(`${VERIFICATION} is missing; the fixture heads lose their provenance`)
  } else {
    const text = fs.readFileSync(note, 'utf8')
    const missing = KNOWN_LICENSED_DIVISION_HEADS.filter((item) => !text.includes(item))
    if (missing.length > 0) {
      failures.push(
        `${VERIFICATION} no longer records fixture head(s) ${missing.join(', ')}`,
      )
    }
  }

  if (failures.length > 0) {
    for (const failure of failures) console.error(`FAIL: ${failure}`)
    process.exit(1)
  }

  console.log(
    `Prepack exclusion check passed: ${defining[defining.length - 1]} excludes both prepack ` +
      `roles and the non-licensed divisions, and ${KNOWN_LICENSED_DIVISION_HEADS.length} ` +
      'fixture heads keep their recorded provenance.',
  )
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main()
}
