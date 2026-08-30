#!/usr/bin/env node

import { readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'

const [migrationDir, addedVersionsFile] = process.argv.slice(2)
if (!migrationDir || !addedVersionsFile) {
  console.error('usage: check-migration-verify-cost.mjs <migration-dir> <added-versions-file>')
  process.exit(2)
}

const added = new Set(
  readFileSync(addedVersionsFile, 'utf8').match(/^\d{14}$/gm) ?? [],
)

// Fixture runs intentionally scan every file. In a real checkout only migrations
// added by the branch are inspected, so immutable historical SQL is not
// retroactively judged by a guard introduced later.
const fixtureMode = Boolean(process.env.CHECK_SQL_MIGRATION_DIR)
const files = readdirSync(migrationDir)
  .filter(name => /^\d{14}.*\.sql$/i.test(name))
  .filter(name => fixtureMode || added.has(name.slice(0, 14)))

function stripComments(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, match => match.replace(/[^\n]/g, ' '))
    .replace(/--[^\r\n]*/g, '')
}

function verifyBlocks(sql) {
  const blocks = []
  const start = /\bdo\s+(\$[A-Za-z0-9_]*\$)/gi
  let match
  while ((match = start.exec(sql))) {
    const tag = match[1]
    const bodyStart = start.lastIndex
    const bodyEnd = sql.indexOf(tag, bodyStart)
    if (bodyEnd < 0) break
    const body = sql.slice(bodyStart, bodyEnd)
    const lead = sql.slice(Math.max(0, match.index - 400), match.index)
    const executable = stripComments(body)
    const signalled = /verify|verification/i.test(tag)
      || /raise\s+(?:exception|notice|warning)[\s\S]{0,160}\bverif(?:y|ication)\b/i.test(executable)
      || /(?:self[- ]verification|verification(?:\s+block)?|verify(?:\s+block)?)[^\n]*$/im.test(lead)
    if (signalled) blocks.push({ body: executable, offset: bodyStart })
    start.lastIndex = bodyEnd + tag.length
  }
  return blocks
}

const failures = []
for (const name of files) {
  const sql = readFileSync(path.join(migrationDir, name), 'utf8')
  for (const block of verifyBlocks(sql)) {
    const patterns = [
      { label: 'api.source_capture_inventory', regex: /(?<![A-Za-z0-9_])(?:"?api"?\s*\.\s*)?"?source_capture_inventory"?(?![A-Za-z0-9_])/i },
      { label: 'a plm object', regex: /(?<![A-Za-z0-9_])"?plm"?\s*\.\s*"?[A-Za-z_][A-Za-z0-9_]*"?/i },
    ]
    for (const pattern of patterns) {
      const found = pattern.regex.exec(block.body)
      if (!found) continue
      const line = sql.slice(0, block.offset + found.index).split(/\r?\n/).length
      failures.push(`${name}:${line}: verification reads ${pattern.label}`)
    }
  }
}

if (failures.length) {
  console.error('ERROR: migration verification must not read source_capture_inventory or plm.* data:')
  for (const failure of failures) console.error(`  ${failure}`)
  console.error('Use catalogue metadata for shape checks. Put data-scale validation in a bounded rehearsal outside the apply transaction.')
  process.exit(1)
}

console.log(`Verify-cost guard passed: ${files.length} added migration(s) contain no prohibited verification read.`)
