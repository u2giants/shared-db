#!/usr/bin/env node
//
// Refuse ADDED migration verification blocks that read expensive data.
//
// WHY (issue #1285). A self-verification block runs inside the apply
// transaction. A `count(*)` over `api.source_capture_inventory` or any `plm`
// table holds that transaction open for as long as the scan takes, on
// production, with the migration lock held. Shape checks belong in the
// catalogue; data-scale checks belong in a bounded rehearsal outside the apply.
//
// WHAT CHANGED AFTER EXTERNAL REVIEW (grok-4.6, PR #1954)
// -------------------------------------------------------
// The first version matched the NAMES anywhere inside a verification block.
// That was wrong in both directions and the review proved it with this
// repository's own SQL:
//
//   * FALSE POSITIVES. `pg_get_viewdef('api.source_capture_inventory'::regclass)`,
//     `has_table_privilege(..., 'api.source_capture_inventory', 'select')`,
//     `to_regprocedure('plm.finalize_...')` and even
//     `raise exception 'no plm.wildbrain_* tables exist'` were all refused.
//     Those are exactly the catalogue-only shape the guard is supposed to
//     PERMIT -- migration 20260820004338 would not have been mergeable.
//     So the rule is now a READ CONTEXT, not a name: the object must appear
//     where a relation is read or written (`from`, `join`, `into`, `update`,
//     `delete from`, `truncate`, `analyze`, `copy`), or be CALLED as a routine.
//     A name inside a string handed to a catalogue function is a lookup, not a
//     scan.
//
//   * FALSE NEGATIVES. An unmatched dollar tag anywhere in the file made the
//     scan `break` and the file PASS; `do language plpgsql $verify$` was not
//     recognised as a block at all; a comment between `do` and the tag hid it;
//     and `set search_path to plm` made every bare name a plm read that no
//     `plm.` pattern could see.
//
// FAIL CLOSED. Anything this file cannot parse is refused, never passed. The
// one deliberate exception is an EMPTY added-version list, which legitimately
// means "this branch adds no migration" -- the overwhelming majority of pull
// requests -- and is established by `check-sql.sh` before this script runs.
//
// This is a text scanner, not a SQL executor.
// `docs/migration-verification-cost-guard.md` records what it still cannot see.

import { readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'

const DOLLAR_TAG = /^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/

// A string literal is real SQL only when something is about to run it.
const DYNAMIC_SQL_LEAD = /\b(?:execute|format)\s*\(?\s*$/i

// One pass that understands the four things a regex cannot: line comments,
// block comments, single-quoted strings and dollar-quoted bodies.
//
// It returns TWO views of the same text, both the same length as the input so
// every offset and line number stays exact:
//
//   masked    -- comments blanked. Used to decide what is a `do` block and
//                whether the block is signalled as verification, which is a
//                judgement that legitimately reads `raise notice 'verify ...'`.
//   scannable -- comments blanked AND the contents of every string literal
//                blanked, EXCEPT a string handed to `execute` or `format`.
//                Used for the prohibited-read patterns. This is what stops
//                `raise exception 'verify 7: plm.finalize_x(...) is missing'`
//                from being read as a call while keeping
//                `execute 'select count(*) from plm.big'` visible.
export function scanSql(sql) {
  const mask = [...sql]
  const scan = [...sql]
  const dollars = []
  const unterminated = []
  let i = 0
  while (i < sql.length) {
    if (sql.startsWith('--', i)) {
      while (i < sql.length && sql[i] !== '\n') { mask[i] = ' '; scan[i] = ' '; i += 1 }
      continue
    }
    if (sql.startsWith('/*', i)) {
      const end = sql.indexOf('*/', i + 2)
      const stop = end < 0 ? sql.length : end + 2
      for (let j = i; j < stop; j += 1) if (sql[j] !== '\n') { mask[j] = ' '; scan[j] = ' ' }
      if (end < 0) unterminated.push({ kind: 'block comment', offset: i })
      i = stop
      continue
    }
    if (sql[i] === "'") {
      const opened = i
      i += 1
      let closed = false
      while (i < sql.length) {
        if (sql[i] === "'" && sql[i + 1] === "'") { i += 2; continue }
        if (sql[i] === "'") { i += 1; closed = true; break }
        i += 1
      }
      if (!closed) unterminated.push({ kind: 'string literal', offset: opened })
      const dynamic = DYNAMIC_SQL_LEAD.test(mask.slice(Math.max(0, opened - 120), opened).join(''))
      if (!dynamic) for (let j = opened + 1; j < i - (closed ? 1 : 0); j += 1) if (sql[j] !== '\n') scan[j] = ' '
      continue
    }
    if (sql[i] === '"') {
      const opened = i
      i += 1
      let closed = false
      while (i < sql.length) {
        if (sql[i] === '"') { i += 1; closed = true; break }
        i += 1
      }
      if (!closed) unterminated.push({ kind: 'quoted identifier', offset: opened })
      continue
    }
    const tagMatch = sql[i] === '$' ? DOLLAR_TAG.exec(sql.slice(i)) : null
    if (tagMatch) {
      const tag = tagMatch[0]
      const bodyStart = i + tag.length
      const bodyEnd = sql.indexOf(tag, bodyStart)
      if (bodyEnd < 0) {
        unterminated.push({ kind: `dollar-quoted body ${tag}`, offset: i })
        break
      }
      // Scan the body too, and splice its views back in at the same offsets. A
      // nested dollar-quoted region (a function body inside a `do` block, a
      // `$q$` literal) would otherwise be skipped whole, leaving its comments
      // and its prose strings visible to the patterns.
      const nested = scanSql(sql.slice(bodyStart, bodyEnd))
      for (let j = 0; j < nested.masked.length; j += 1) {
        mask[bodyStart + j] = nested.masked[j]
        scan[bodyStart + j] = nested.scannable[j]
      }
      for (const open of nested.unterminated) unterminated.push({ ...open, offset: open.offset + bodyStart })
      dollars.push({ tag, tagStart: i, bodyStart, bodyEnd })
      i = bodyEnd + tag.length
      continue
    }
    i += 1
  }
  return { masked: mask.join(''), scannable: scan.join(''), dollars, unterminated }
}

// `do $verify$`, `do language plpgsql $verify$`, and the same with comments in
// between -- the lead is read from the COMMENT-BLANKED text, so a comment can
// neither hide the keyword nor forge one.
const DO_LEAD = /\bdo(?:\s+language\s+[A-Za-z_][A-Za-z0-9_]*)?\s*$/i

export function verifyBlocks(sql) {
  const { masked, scannable, dollars, unterminated } = scanSql(sql)
  const blocks = []
  for (const region of dollars) {
    if (!DO_LEAD.test(masked.slice(Math.max(0, region.tagStart - 200), region.tagStart))) continue
    const lead = sql.slice(Math.max(0, region.tagStart - 400), region.tagStart)
    const signalled = /verify|verification/i.test(region.tag)
      || /raise\s+(?:exception|notice|warning)[\s\S]{0,160}\bverif(?:y|ication)\b/i.test(masked.slice(region.bodyStart, region.bodyEnd))
      || /(?:self[- ]verification|verification(?:\s+block)?|verify(?:\s+block)?)[^\n]*$/im.test(lead)
    if (signalled) blocks.push({ body: scannable.slice(region.bodyStart, region.bodyEnd), offset: region.bodyStart })
  }
  return { blocks, unterminated }
}

// A relation name only costs anything when something READS or WRITES it. These
// are the contexts in which it does.
const READ_CONTEXT = String.raw`\b(?:from|join|into|update|delete\s+from|truncate|analyze|copy)\s+(?:only\s+)?`
const INVENTORY = String.raw`(?:"?api"?\s*\.\s*)?"?source_capture_inventory"?(?![A-Za-z0-9_])`
const PLM_OBJECT = String.raw`"?plm"?\s*\.\s*"?[A-Za-z_][A-Za-z0-9_]*"?`

export const PATTERNS = [
  {
    label: 'api.source_capture_inventory',
    regex: new RegExp(`${READ_CONTEXT}${INVENTORY}`, 'i'),
  },
  {
    label: 'a plm object',
    regex: new RegExp(`${READ_CONTEXT}${PLM_OBJECT}`, 'i'),
  },
  {
    // A routine call is a read too, and it is the one that does not need FROM.
    // The negative lookbehind keeps `to_regprocedure('plm.f(...)')` and every
    // other catalogue lookup out: there the name is opened by a quote.
    label: 'a plm routine',
    regex: /(?<!['"\w.])"?plm"?\s*\.\s*"?[A-Za-z_][A-Za-z0-9_]*"?\s*\(/i,
  },
  {
    // `set search_path to plm` makes every unqualified name a plm read that no
    // `plm.` pattern can see. Refuse the construct instead of guessing.
    label: 'plm through search_path',
    regex: /\bset\s+(?:local\s+)?search_path\s*(?:to|=)\s*[^;\n]*\bplm\b/i,
  },
]

export function inspectSql(name, sql) {
  const failures = []
  const { blocks, unterminated } = verifyBlocks(sql)
  for (const open of unterminated) {
    const line = sql.slice(0, open.offset).split(/\r?\n/).length
    failures.push(`${name}:${line}: unterminated ${open.kind}; this guard cannot read the file and refuses it`)
  }
  for (const block of blocks) {
    for (const pattern of PATTERNS) {
      const found = pattern.regex.exec(block.body)
      if (!found) continue
      const line = sql.slice(0, block.offset + found.index).split(/\r?\n/).length
      failures.push(`${name}:${line}: verification reads ${pattern.label}`)
    }
  }
  return failures
}

function main() {
  const [migrationDir, addedVersionsFile] = process.argv.slice(2)
  if (!migrationDir || !addedVersionsFile) {
    console.error('usage: check-migration-verify-cost.mjs <migration-dir> <added-versions-file>')
    process.exit(2)
  }

  const added = new Set(
    readFileSync(addedVersionsFile, 'utf8').match(/^\d{14}$/gm) ?? [],
  )

  // Fixture runs intentionally scan every file. In a real checkout only
  // migrations added by the branch are inspected, so immutable historical SQL
  // is not retroactively judged by a guard introduced later.
  const fixtureMode = Boolean(process.env.CHECK_SQL_MIGRATION_DIR)
  const files = readdirSync(migrationDir)
    .filter(name => /^\d{14}.*\.sql$/i.test(name))
    .filter(name => fixtureMode || added.has(name.slice(0, 14)))

  const failures = []
  for (const name of files) {
    failures.push(...inspectSql(name, readFileSync(path.join(migrationDir, name), 'utf8')))
  }

  if (failures.length) {
    console.error('ERROR: migration verification must not read source_capture_inventory or plm.* data:')
    for (const failure of failures) console.error(`  ${failure}`)
    console.error('Use catalogue metadata for shape checks. Put data-scale validation in a bounded rehearsal outside the apply transaction.')
    process.exit(1)
  }

  console.log(`Verify-cost guard passed: ${files.length} added migration(s) contain no prohibited verification read.`)
}

if (process.argv[1]?.endsWith('check-migration-verify-cost.mjs')) main()
