#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const allowedMigration = 'supabase/migrations/20260827213010_eol_core_properties_and_characters.sql'
const guardedRoots = ['apps', 'scripts', 'tools', 'supabase/functions', 'supabase/migrations']

export function addedCoreCombinedTableReferences(diff) {
  const failures = []
  let currentPath = ''
  for (const line of diff.split(/\r?\n/)) {
    const header = line.match(/^\+\+\+ b\/(.+)$/)
    if (header) {
      currentPath = header[1]
      continue
    }
    if (!line.startsWith('+') || line.startsWith('+++')) continue
    if (currentPath === allowedMigration) continue
    if (currentPath === 'scripts/check-properties-and-characters-eol-references.mjs') continue
    if (/\.test\.[cm]?js$/.test(currentPath) || currentPath.startsWith('supabase/tests/')) continue
    if (/core\s*\.\s*["']?properties_and_characters\b/i.test(line.slice(1))) {
      failures.push(`${currentPath}: ${line.slice(1).trim()}`)
    }
  }
  return failures
}

export function checkRepositoryDiff(base = process.env.GITHUB_BASE_REF ? `origin/${process.env.GITHUB_BASE_REF}` : 'origin/main') {
  const diff = execFileSync(
    'git',
    ['diff', '--unified=0', '--no-ext-diff', base, '--', ...guardedRoots],
    { cwd: repoRoot, encoding: 'utf8' },
  )
  return addedCoreCombinedTableReferences(diff)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let failures
  try {
    failures = checkRepositoryDiff()
  } catch (error) {
    console.error(`ERROR: could not compare EOL references with the base branch: ${error.message}`)
    process.exit(2)
  }
  if (failures.length) {
    console.error('ERROR: new runtime or migration references to core.properties_and_characters are forbidden by issue #1684:')
    for (const failure of failures) console.error(`  ${failure}`)
    console.error(`Only the exact EOL staging migration is allowlisted: ${allowedMigration}`)
    process.exit(1)
  }
  console.log('Issue #1684 EOL reference guard passed: no new dependency was introduced.')
}
