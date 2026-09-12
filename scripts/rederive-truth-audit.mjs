#!/usr/bin/env node
// Re-derive docs/verification/throughput-guard-truth-audit-20260828.json after the
// base moves, WITHOUT hand-editing the count and WITHOUT reasoning out the digest.
//
// Both mechanical fields come from the checker's own exported discover(), so the
// number and the digest are computed by the same code that validates them.
//
// What this deliberately REFUSES to do: invent a disposition or a reason. Those
// are review judgements (the checker demands 'enriched'|'excluded' plus a reason
// of >= 20 chars per site). Surviving sites carry their existing judgement
// forward, keyed on semantic_key -- which is path:sha256(line):occurrence, i.e.
// line CONTENT, so pure line-number shifts preserve every disposition. A site
// whose line text is new or edited has no honest carry-forward, so this script
// stops and names it rather than writing a file that would pass the checker on a
// judgement nobody made.
//
// Usage:
//   node rederive-truth-audit.mjs <repo-root>            # dry run, reports only
//   node rederive-truth-audit.mjs <repo-root> --write    # writes when complete

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

const root = path.resolve(process.argv[2] ?? process.cwd());
const write = process.argv.includes('--write');
const AUDIT_REL = 'docs/verification/throughput-guard-truth-audit-20260828.json';

const checker = await import(pathToFileURL(path.join(root, 'scripts/check-throughput-truth-audit.mjs')).href);
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

const auditPath = path.join(root, AUDIT_REL);
const audit = JSON.parse(fs.readFileSync(auditPath, 'utf8'));

// discover() resolves its own relative ROOTS against process.cwd(), so run there.
process.chdir(root);
const found = checker.discover(root);
const semanticKeys = found.map((row) => row.semantic_key);
const digest = sha256(JSON.stringify(semanticKeys));

const priorByKey = new Map((audit.sites ?? []).map((row) => [row.semantic_key, row]));

const carried = [];
const unjudged = [];
for (const row of found) {
  const prior = priorByKey.get(row.semantic_key);
  if (!prior || !['enriched', 'excluded'].includes(prior.disposition)
      || typeof prior.reason !== 'string' || prior.reason.length < 20) {
    unjudged.push(row);
    continue;
  }
  carried.push({ ...prior, site: row.site, semantic_key: row.semantic_key, line_sha256: row.line_sha256 });
}

const dropped = (audit.sites ?? []).filter((row) => !semanticKeys.includes(row.semantic_key));

console.log(`recorded count : ${audit.call_site_count}`);
console.log(`derived  count : ${found.length}`);
console.log(`recorded digest: ${audit.call_site_sha256}`);
console.log(`derived  digest: ${digest}`);
console.log(`carried forward: ${carried.length}`);
console.log(`dropped (stale): ${dropped.length}`);
console.log(`NEEDS JUDGEMENT: ${unjudged.length}`);
for (const row of unjudged) console.log(`  unjudged site: ${row.site}  ${row.semantic_key}`);
for (const row of dropped) console.log(`  dropped  site: ${row.site}`);

if (unjudged.length) {
  console.error('\nREFUSING to write: the sites above have no carried-forward disposition.');
  console.error('Each needs a real reviewed disposition and a substantive reason.');
  console.error('Inventing one would fabricate a review judgement. Write them by hand, then re-run.');
  process.exit(2);
}

if (found.length === audit.call_site_count && digest === audit.call_site_sha256 && !dropped.length) {
  console.log('\nAlready consistent: nothing to re-derive.');
  process.exit(0);
}

if (!write) {
  console.log('\nDry run. Re-run with --write to apply.');
  process.exit(0);
}

const next = { ...audit, call_site_count: found.length, call_site_sha256: digest, sites: carried };
fs.writeFileSync(auditPath, `${JSON.stringify(next, null, 2)}\n`);
console.log(`\nWrote ${AUDIT_REL}. Now run: node scripts/check-throughput-truth-audit.mjs`);
