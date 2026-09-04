#!/usr/bin/env node
// GUARD (issue #2037): refuse a pull request that EDITS a migration file whose
// version has already been applied to preview or production.
//
// WHY THIS EXISTS
// ---------------
// On 2026-09-01 `20260831234750_hts_rag_durable_precedent_contract.sql` was
// applied to preview by run 33454217961, and eight minutes later a second
// session pushed a commit to the same pull request that REWROTE that same file:
// CHECK regexes widened, constraints added, an index dropped, grants widened, a
// policy split. The pull request then merged.
//
// A version can be applied only once. Supabase's ledger keys on the version
// alone, so the edited body is never replayed anywhere it has already run.
// Preview permanently held the PRE-edit body; `main` held the POST-edit body;
// and the preview rehearsal pinned to that run had rehearsed SQL that no longer
// existed. AGENTS.md 6.x rule 4 has always forbidden this ("never edit a
// migration that has already been applied anywhere") -- but nothing MECHANICAL
// refused the push, so the rule was enforced only by whoever happened to be
// reading. That is the gap this closes.
//
// WHAT COUNTS AS AN EDIT
// ----------------------
// Any change to an existing migration file: modified, deleted, or renamed. A
// rename is an edit because the ledger keys on the version, so renaming the file
// detaches the applied version from the only record of what it ran. ADDING a new
// migration is the normal case and is never flagged.
//
// COST, AND WHY THE LEDGER READ IS CONDITIONAL
// --------------------------------------------
// The ledgers are read ONLY when the diff actually touches an existing migration
// file. On every other pull request -- the overwhelming majority -- this guard
// makes no network call at all and cannot fail for an unrelated reason. In the
// rare case where it does have to look, it FAILS CLOSED: an unreadable ledger
// exits 2, because "we could not check" must never be reported as "not applied".
//
// READ-ONLY. It runs the same single constant SELECT as the drift check and has
// no code path that can issue any other statement.
//
//   node scripts/check-applied-migration-edit.mjs --base origin/main

import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { fetchAppliedVersions, PROJECT_REFS, Unknown } from './orchestrator-flow/read-preview-ledger.mjs'
export { fetchAppliedVersions, PROJECT_REFS, Unknown }

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

export const MIGRATIONS_DIR = 'supabase/migrations'

// `A` is an added file -- the normal way a migration arrives, and never a
// finding. Everything else changes a file that already existed on the base.
export const EDIT_STATUSES = Object.freeze({ M: 'modified', D: 'deleted', R: 'renamed', C: 'copied', T: 'type-changed' })

export function versionOf(file) {
  const match = /^(\d{14})_/.exec(path.basename(String(file ?? '')))
  return match ? match[1] : null
}

/**
 * Pure. Parses `git diff --name-status -z` output into the edits this guard
 * cares about. NUL-delimited so a path with a space, a quote or a newline in it
 * cannot split into two fields and disappear from the finding list.
 */
export function parseEditedMigrations(nameStatusZ) {
  const fields = String(nameStatusZ ?? '').split('\0').filter((field) => field !== '')
  const edits = []
  for (let index = 0; index < fields.length; index += 1) {
    const status = fields[index]
    if (!/^[A-Z]\d*$/.test(status)) continue
    const letter = status[0]
    // A rename or copy carries TWO paths: the old one, then the new one.
    const pathCount = letter === 'R' || letter === 'C' ? 2 : 1
    const paths = fields.slice(index + 1, index + 1 + pathCount)
    index += pathCount
    if (paths.length !== pathCount) break
    const subject = paths[0]
    if (!subject.startsWith(`${MIGRATIONS_DIR}/`) || !subject.endsWith('.sql')) continue
    const kind = EDIT_STATUSES[letter]
    if (!kind) continue
    const version = versionOf(subject)
    if (!version) continue
    edits.push({ version, file: subject, kind, ...(pathCount === 2 ? { renamedTo: paths[1] } : {}) })
  }
  return edits
}

export function editedMigrations(baseRef, { executor = execFileSync, cwd = repoRoot } = {}) {
  let raw
  try {
    raw = executor('git', ['diff', '--name-status', '-z', '--find-renames', `${baseRef}...HEAD`, '--', MIGRATIONS_DIR], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (error) {
    throw new Unknown(`could not diff ${MIGRATIONS_DIR} against ${baseRef}: ${error.message}`)
  }
  return parseEditedMigrations(raw)
}

/**
 * Pure. Given the edits and each ledger's applied versions, say which edits are
 * forbidden and where each was already applied.
 */
export function findingsFor(edits, ledgers) {
  const findings = []
  for (const edit of edits) {
    const appliedIn = Object.entries(ledgers).filter(([, versions]) => versions.has(edit.version)).map(([name]) => name)
    if (appliedIn.length > 0) findings.push({ ...edit, appliedIn })
  }
  return findings
}

export function formatReport(edits, findings) {
  const lines = []
  if (edits.length === 0) return ['No existing migration file was modified, deleted or renamed by this change.']
  lines.push(`This change touches ${edits.length} existing migration file(s):`)
  for (const edit of edits) lines.push(`  ${edit.kind.padEnd(12)} ${edit.file}${edit.renamedTo ? ` -> ${edit.renamedTo}` : ''}`)
  lines.push('')
  if (findings.length === 0) {
    lines.push('None of those versions is present in the preview or production ledger, so no applied migration was edited.')
    return lines
  }
  lines.push(`REFUSED: ${findings.length} of them have ALREADY BEEN APPLIED and can never be replayed:`)
  for (const finding of findings) lines.push(`  ${finding.version}  applied in: ${finding.appliedIn.join(', ')}  (${finding.kind})`)
  lines.push('')
  lines.push('A version is applied only once. The database keeps the body it ran; this branch would leave')
  lines.push('a different body on main, and any rehearsal evidence for that version would describe SQL that')
  lines.push('no longer exists (AGENTS.md 6.x rule 4, incident issue #2037).')
  lines.push('')
  lines.push('FIX FORWARD: restore the file to its base-branch body and put the change in a NEW migration at a')
  lines.push('newly reserved version, written to be a no-op where the applied shape already matches.')
  return lines
}

export const defaultIo = {
  editedMigrations,
  async appliedVersions(projectRef) { return new Set(await fetchAppliedVersions(projectRef)) },
}

export async function runCheck({ baseRef = 'origin/main', io = defaultIo } = {}) {
  const edits = io.editedMigrations(baseRef)
  // The whole point of the conditional read: an ordinary pull request never
  // touches the network here, so this guard cannot go red for a reason that has
  // nothing to do with it.
  if (edits.length === 0) return { edits, findings: [], ledgersRead: [] }
  const ledgers = {}
  for (const [name, projectRef] of Object.entries(PROJECT_REFS)) {
    ledgers[name] = await io.appliedVersions(projectRef)
    if (!(ledgers[name] instanceof Set) || ledgers[name].size === 0) throw new Unknown(`the ${name} ledger came back empty, so nothing was compared`)
  }
  return { edits, findings: findingsFor(edits, ledgers), ledgersRead: Object.keys(ledgers) }
}

export function parseArgs(argv) {
  const options = { baseRef: 'origin/main', help: false }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--base') options.baseRef = argv[index += 1]
    else if (arg === '--help' || arg === '-h') options.help = true
    else return { ...options, error: `unrecognised argument ${JSON.stringify(arg)}` }
  }
  if (!options.baseRef) return { ...options, error: '--base requires a ref' }
  return options
}

export async function main(argv, { run = runCheck, log = console.log, error = console.error } = {}) {
  const options = parseArgs(argv)
  if (options.error) { error(`UNKNOWN: ${options.error}`); return 2 }
  if (options.help) { log('Usage: node scripts/check-applied-migration-edit.mjs [--base <ref>]'); return 0 }
  let result
  try { result = await run({ baseRef: options.baseRef }) } catch (problem) {
    error(`UNKNOWN: the applied-migration-edit guard COULD NOT RUN — ${problem.message}`)
    error('Nothing was compared. Do not read this as "no applied migration was edited".')
    return 2
  }
  for (const line of formatReport(result.edits, result.findings)) log(line)
  return result.findings.length > 0 ? 1 : 0
}

const invokedDirectly = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedDirectly) process.exitCode = await main(process.argv.slice(2))
