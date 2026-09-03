// Plan section 10: the 19 required synthetic tests, plus the cutoff lock.
//
// Every test here proves a guard can FAIL. A guard that has only ever been seen
// green is not evidence, so each case feeds a known-bad input and asserts the
// specific refusal, not merely that something threw.

import test from 'node:test';
import assert from 'node:assert/strict';

import { ABSTAIN, HISTORICAL_CUTOFF_ISO, assertCutoff } from './lib/constants.mjs';
import {
  buildDivisionIndex, buildTaxonomyIndex, qualifyCandidate, reconcile, resolveItemDivision,
} from './lib/classify.mjs';
import {
  assertAuthorization, assertManifestWritable, manifestDigest, serializeManifest,
} from './lib/manifest.mjs';
import { assertTarget, projectRefFromConnectionString } from './lib/target.mjs';
import { runBatch, runRollback } from './lib/execute.mjs';
import { nonCandidateDigest, assertCategoryContract } from './lib/verify.mjs';
import { evaluateRetirementGate, RESIDUAL_CLASSES } from './lib/retirement-gate.mjs';
import {
  DIVISIONS, MERCH_GROUPS, fakeClient, item, manifestOf, sourceRow,
} from './fixtures.mjs';

const divisionIndex = buildDivisionIndex(DIVISIONS);
const taxonomyIndex = buildTaxonomyIndex(MERCH_GROUPS, divisionIndex);

const qualify = (source, live) => qualifyCandidate({
  source, liveMatches: live, divisionIndex, taxonomyIndex,
});

const PREVIEW_URI = 'postgresql://postgres.rjyboqwcdzcocqgmsyel:x@aws-1-us-east-1.pooler.supabase.com:6543/postgres';
const PROD_URI = 'postgresql://postgres.qsllyeztdwjgirsysgai:x@aws-1-us-east-1.pooler.supabase.com:6543/postgres';

// ---------------------------------------------------------------- cutoff lock

test('the May 14, 2025 cutoff is locked and cannot be parameterised away', () => {
  assert.equal(assertCutoff(HISTORICAL_CUTOFF_ISO), HISTORICAL_CUTOFF_ISO);
  assert.throws(() => assertCutoff('2025-06-01T00:00:00'), /cutoff is locked/);
  assert.throws(() => assertCutoff(null), /cutoff is locked/);
});

// 1 -------------------------------------------------------------------------

test('1: mutating the live old codes leaves the proposal unchanged', () => {
  const a = qualify(sourceRow(), [item()]);
  const b = qualify(sourceRow(), [item({
    udf_merchgroup01: 'SENTINEL', udf_merchgroup02: 'SENTINEL', udf_merchgroup03: 'SENTINEL',
    udf_merchgroup01_id: 1, udf_merchgroup02_id: 2, udf_merchgroup03_id: 3,
  })]);
  assert.equal(a.status, 'candidate');
  assert.equal(b.status, 'candidate');
  assert.deepEqual(a.record.after, b.record.after);
  assert.notDeepEqual(a.record.before, b.record.before);
});

// 2 -------------------------------------------------------------------------

test('2: a duplicate item number refuses both, and a unique one resolves', () => {
  const dup = qualify(sourceRow(), [item({ item_id_pk: 1 }), item({ item_id_pk: 2 })]);
  assert.equal(dup.status, 'abstain');
  assert.equal(dup.reason, ABSTAIN.AMBIGUOUS_TARGET);
  assert.equal(dup.live_match_count, 2);
  assert.equal(qualify(sourceRow(), [item()]).status, 'candidate');
});

test('2b: no live row at all abstains rather than inventing one', () => {
  assert.equal(qualify(sourceRow(), []).reason, ABSTAIN.NO_LIVE_TARGET);
});

// 3 -------------------------------------------------------------------------

test('3: a source/production division mismatch abstains', () => {
  const r = qualify(sourceRow({ division: 'CW001' }), [item()]);
  assert.equal(r.reason, ABSTAIN.DIVISION_MISMATCH);
  assert.equal(r.live_division, 'EH001');
});

test('3b: the two division encodings must agree on the item itself', () => {
  const r = qualify(sourceRow(), [item({ div_code: 'EH001', div_code_fk: 2 })]);
  assert.equal(r.reason, ABSTAIN.DIVISION_ENCODING_CONFLICT);
  assert.equal(
    resolveItemDivision({ div_code: null, div_code_fk: null }, divisionIndex).abstain,
    ABSTAIN.DIVISION_UNRESOLVED,
  );
});

// 4 -------------------------------------------------------------------------

test('4: null, post-cutoff, and unparsable creation dates all abstain', () => {
  assert.equal(qualify(sourceRow(), [item({ created_time_date: null })]).reason,
    ABSTAIN.NULL_TARGET_DATE);
  assert.equal(qualify(sourceRow(), [item({ created_time_date: 'not a date' })]).reason,
    ABSTAIN.NULL_TARGET_DATE);
  assert.equal(qualify(sourceRow(), [item({ created_time_date: '2025-05-14 00:00:01' })]).reason,
    ABSTAIN.NON_HISTORICAL_TARGET);
  assert.equal(qualify(sourceRow(), [item({ created_time_date: '2025-05-13 23:59:59' })]).status,
    'candidate');
});

// 5 -------------------------------------------------------------------------

test('5: an inactive or missing level abstains with a distinguishable reason', () => {
  const inactive = qualify(sourceRow({ proposed_mg03: 'X' }), [item()]);
  assert.equal(inactive.reason, ABSTAIN.TAXONOMY_INACTIVE);
  assert.equal(inactive.failed_level, 'MG03');
  const missing = qualify(sourceRow({ proposed_mg03: 'ZZZ' }), [item()]);
  assert.equal(missing.reason, ABSTAIN.TAXONOMY_MISSING);
});

test('5b: a merchGroup row whose own division encodings disagree is refused', () => {
  const cw = qualify(sourceRow({ division: 'CW001' }),
    [item({ div_code: 'CW001', div_code_fk: 2 })]);
  assert.equal(cw.reason, ABSTAIN.TAXONOMY_DIVISION_CONFLICT);
});

// 6 -------------------------------------------------------------------------

test('6: a code duplicated under two parents selects only the exact chain', () => {
  const viaB = qualify(sourceRow({ proposed_mg02: 'B', proposed_mg03: 'C' }), [item()]);
  const viaB2 = qualify(sourceRow({ proposed_mg02: 'B2', proposed_mg03: 'C' }), [item()]);
  assert.equal(viaB.record.after.udf_merchgroup03_id, 120);
  assert.equal(viaB2.record.after.udf_merchgroup03_id, 140);
  const wrongParent = qualify(sourceRow({ proposed_mg02: 'B', proposed_mg03: 'C' }), [item()]);
  assert.notEqual(wrongParent.record.after.udf_merchgroup03_id, 140);
});

// 7 -------------------------------------------------------------------------

test('7: EP001 has no active taxonomy, so it abstains and is never remapped', () => {
  const r = qualify(sourceRow({ division: 'EP001' }),
    [item({ div_code: 'EP001', div_code_fk: 9 })]);
  assert.equal(r.reason, ABSTAIN.TAXONOMY_INACTIVE);
  assert.equal(r.record, undefined);
});

// 8 -------------------------------------------------------------------------

test('8: partial levels never enter the writable manifest', () => {
  assert.equal(qualify(sourceRow({ matched_level: '2', proposed_mg03: '' }), [item()]).reason,
    ABSTAIN.NOT_LEVEL_3);
  assert.equal(qualify(sourceRow({ matched_level: '1', proposed_mg02: '', proposed_mg03: '' }), [item()]).reason,
    ABSTAIN.NOT_LEVEL_3);
  assert.equal(qualify(sourceRow({ proposed_mg03: '   ' }), [item()]).reason,
    ABSTAIN.BLANK_PROPOSAL);
});

test('8b: the manifest guard refuses a hand-edited partial candidate', () => {
  const good = qualify(sourceRow(), [item()]).record;
  assert.equal(assertManifestWritable(manifestOf([good])), true);
  const partial = JSON.parse(JSON.stringify(good));
  partial.after.udf_merchgroup03 = '';
  assert.throws(() => assertManifestWritable(manifestOf([partial])), /blank udf_merchgroup03/);
  const notLevel3 = JSON.parse(JSON.stringify(good));
  notLevel3.evidence.level = 2;
  assert.throws(() => assertManifestWritable(manifestOf([notLevel3])), /not level 3/);
  const brokenParent = JSON.parse(JSON.stringify(good));
  brokenParent.taxonomy.mg03.parent_id = 999;
  assert.throws(() => assertManifestWritable(manifestOf([brokenParent])), /not a child/);
  assert.throws(() => assertManifestWritable(manifestOf([good, good])), /duplicate item_id_pk/);
});

// 9 -------------------------------------------------------------------------

test('9: a manifest digest mismatch refuses the apply', async () => {
  const rec = qualify(sourceRow(), [item()]).record;
  const manifest = manifestOf([rec]);
  const client = fakeClient([item()]);
  await assert.rejects(
    runBatch(client, manifest, {
      target: 'preview', mode: 'apply', expectedDigest: 'deadbeef',
    }),
    /digest mismatch/,
  );
  assert.equal(client.log.includes('UPDATE'), false);
});

test('9b: the canonical serialization is byte-stable under key reordering', () => {
  const a = { b: 1, a: { d: 2, c: 3 }, candidates: [] };
  const b = { a: { c: 3, d: 2 }, candidates: [], b: 1 };
  assert.equal(serializeManifest(a), serializeManifest(b));
  assert.equal(manifestDigest(a), manifestDigest(b));
});

// 10 ------------------------------------------------------------------------

test('10: a target mismatch refuses before any statement is issued', () => {
  assert.equal(projectRefFromConnectionString(PROD_URI), 'qsllyeztdwjgirsysgai');
  assert.equal(
    projectRefFromConnectionString('postgresql://postgres:x@db.qsllyeztdwjgirsysgai.supabase.co:5432/postgres'),
    'qsllyeztdwjgirsysgai',
  );
  assert.equal(
    assertTarget({ target: 'preview', connectionString: PREVIEW_URI, expectedRef: 'rjyboqwcdzcocqgmsyel' }),
    'rjyboqwcdzcocqgmsyel',
  );
  assert.throws(
    () => assertTarget({ target: 'preview', connectionString: PROD_URI, expectedRef: 'rjyboqwcdzcocqgmsyel' }),
    /target proof failed/,
  );
  assert.throws(
    () => assertTarget({ target: 'preview', connectionString: PREVIEW_URI }),
    /expect-project-ref is required/,
  );
  assert.throws(
    () => assertTarget({ target: 'staging', connectionString: PREVIEW_URI, expectedRef: 'x' }),
    /unknown target/,
  );
});

// 11 ------------------------------------------------------------------------

test('11: compare-and-swap drift rolls back the entire batch', async () => {
  const a = qualify(sourceRow(), [item({ item_id_pk: 1 })]).record;
  const b = qualify(sourceRow({ item_num: 'SYN-0002' }),
    [item({ item_id_pk: 2, item_num_id: 'SYN-0002' })]).record;
  const manifest = manifestOf([a, b]);
  // row 2 drifted since the manifest was built
  const client = fakeClient([
    item({ item_id_pk: 1 }),
    item({ item_id_pk: 2, item_num_id: 'SYN-0002', udf_merchgroup01: 'CHANGED' }),
  ]);
  await assert.rejects(
    runBatch(client, manifest, { target: 'preview', mode: 'apply' }),
    /drifted from the manifest before-state/,
  );
  assert.equal(client.log.includes('UPDATE'), false);
  assert.equal(client.log.at(-1), 'ROLLBACK');
  assert.equal(client.table.get(1).udf_merchgroup01, 'OLD1');
});

test('11b: plan mode always rolls back and never updates', async () => {
  const rec = qualify(sourceRow(), [item()]).record;
  const client = fakeClient([item()]);
  const r = await runBatch(client, manifestOf([rec]), { target: 'preview' });
  assert.equal(r.mode, 'plan');
  assert.equal(r.to_change.length, 1);
  assert.equal(r.changed, 0);
  assert.equal(client.log.includes('UPDATE'), false);
  assert.equal(client.table.get(1).udf_merchgroup01, 'OLD1');
});

test('11c: an unknown mode is refused', async () => {
  const rec = qualify(sourceRow(), [item()]).record;
  await assert.rejects(
    runBatch(fakeClient([item()]), manifestOf([rec]), { target: 'preview', mode: 'force' }),
    /unknown mode/,
  );
});

// 12 ------------------------------------------------------------------------

test('12: raw codes and normalized IDs update together, under a lock', async () => {
  const rec = qualify(sourceRow(), [item()]).record;
  const client = fakeClient([item()]);
  const r = await runBatch(client, manifestOf([rec]), { target: 'preview', mode: 'apply' });
  assert.equal(r.changed, 1);
  assert.equal(client.log.includes('LOCK'), true);
  const row = client.table.get(1);
  assert.deepEqual(
    [row.udf_merchgroup01, row.udf_merchgroup02, row.udf_merchgroup03,
      row.udf_merchgroup01_id, row.udf_merchgroup02_id, row.udf_merchgroup03_id],
    ['A', 'B', 'C', 100, 110, 120],
  );
  assert.equal(client.log.at(-1), 'COMMIT');
});

// 13 ------------------------------------------------------------------------

test('13: a row already carrying the proposal is a counted no-op', async () => {
  const already = item({
    udf_merchgroup01: 'A', udf_merchgroup02: 'B', udf_merchgroup03: 'C',
    udf_merchgroup01_id: 100, udf_merchgroup02_id: 110, udf_merchgroup03_id: 120,
  });
  const q = qualify(sourceRow(), [already]);
  assert.equal(q.status, 'noop');
  const rec = qualify(sourceRow(), [item()]).record;
  const client = fakeClient([already]);
  const r = await runBatch(client, manifestOf([rec]), { target: 'preview', mode: 'apply' });
  assert.equal(r.already_equal.length, 1);
  assert.equal(r.to_change.length, 0);
  assert.equal(r.changed, 0);
});

// 14 ------------------------------------------------------------------------

test('14: non-candidate rows stay byte-equivalent across the apply', async () => {
  const rec = qualify(sourceRow(), [item({ item_id_pk: 1 })]).record;
  const rows = [item({ item_id_pk: 1 }), item({ item_id_pk: 2, item_num_id: 'SYN-0002' })];
  const client = fakeClient(rows);
  const before = await nonCandidateDigest(client, [1]);
  await runBatch(client, manifestOf([rec]), { target: 'preview', mode: 'apply' });
  const after = await nonCandidateDigest(client, [1]);
  assert.equal(after.digest, before.digest);
  assert.equal(after.row_count, 1);
  // and the digest must be able to move, or it proves nothing
  client.table.get(2).udf_merchgroup01 = 'TOUCHED';
  assert.notEqual((await nonCandidateDigest(client, [1])).digest, before.digest);
});

test('14b: the category function contract is asserted, not assumed', () => {
  assert.equal(assertCategoryContract(["... '2025-05-14' ... udf_merchgroup01 ..."]), true);
  assert.throws(() => assertCategoryContract(['... udf_merchgroup01 ...']), /no longer carries/);
  assert.throws(() => assertCategoryContract(["... '2025-05-14' ... udf_merchgroup02 ..."]),
    /MG01-only contract is broken/);
  assert.throws(() => assertCategoryContract([]), /is missing/);
});

// 15 ------------------------------------------------------------------------

test('15: reconciliation fails closed on any mismatch', () => {
  assert.equal(reconcile({ attempted: 10, candidates: 4, noops: 3, abstentions: 3 }), true);
  assert.throws(
    () => reconcile({ attempted: 10, candidates: 4, noops: 3, abstentions: 2 }),
    /RECONCILIATION FAILED/,
  );
});

// 16 ------------------------------------------------------------------------

test('16: rollback restores only the exact batch after-state', async () => {
  const rec = qualify(sourceRow(), [item({ item_id_pk: 1 })]).record;
  const rec2 = qualify(sourceRow({ item_num: 'SYN-0002' }),
    [item({ item_id_pk: 2, item_num_id: 'SYN-0002' })]).record;
  const manifest = manifestOf([rec, rec2]);
  const digest = manifestDigest(manifest);
  const client = fakeClient([item({ item_id_pk: 1 }), item({ item_id_pk: 2, item_num_id: 'SYN-0002' })]);
  await runBatch(client, manifest, { target: 'preview', mode: 'apply' });

  const backup = {
    target: 'preview',
    manifest_sha256: digest,
    rows: [rec, rec2].map((c) => ({ item_id_pk: c.item_id_pk, before: c.before, after: c.after })),
  };
  // somebody edited row 2 after our apply
  client.table.get(2).udf_merchgroup02 = 'THEIRS';

  const r = await runRollback(client, backup, {
    target: 'preview', expectedDigest: digest, mode: 'apply',
  });
  assert.equal(r.restored, 1);
  assert.deepEqual(r.abstained, [{ item_id_pk: 2, reason: 'INTERVENING_EDIT' }]);
  assert.equal(client.table.get(1).udf_merchgroup01, 'OLD1');
  assert.equal(client.table.get(2).udf_merchgroup02, 'THEIRS');
});

test('16b: a rollback refuses a backup from another target or another manifest', async () => {
  const backup = { target: 'preview', manifest_sha256: 'aaa', rows: [] };
  await assert.rejects(
    runRollback(fakeClient([]), backup, { target: 'production' }),
    /backup was taken against "preview"/,
  );
  await assert.rejects(
    runRollback(fakeClient([]), backup, { target: 'preview', expectedDigest: 'bbb' }),
    /backup names manifest aaa/,
  );
});

// 17 ------------------------------------------------------------------------

test('17: preview authorization cannot satisfy production', () => {
  const previewAuth = { target: 'preview', manifest_sha256: 'abc' };
  assert.equal(assertAuthorization({
    target: 'preview', actualDigest: 'abc', authorization: previewAuth,
  }), true);
  assert.throws(
    () => assertAuthorization({ target: 'production', actualDigest: 'abc', authorization: previewAuth }),
    /authorization is for target "preview"/,
  );
  assert.throws(
    () => assertAuthorization({ target: 'production', actualDigest: 'abc' }),
    /requires a production authorization artifact/,
  );
});

// 18 ------------------------------------------------------------------------

test('18: a production authorization for one digest cannot authorize another', () => {
  const auth = { target: 'production', manifest_sha256: 'abc' };
  assert.equal(assertAuthorization({ target: 'production', actualDigest: 'abc', authorization: auth }), true);
  assert.throws(
    () => assertAuthorization({ target: 'production', actualDigest: 'xyz', authorization: auth }),
    /authorization names manifest abc/,
  );
});

// 19 ------------------------------------------------------------------------

const cleanMeasurements = () => ({
  null_or_unresolved_creation_dates: 0,
  historical_items: 100,
  ledger_distinct_item_id_pk: 100,
  historical_items_with_complete_agreeing_triplet: 100,
  historical_items_with_active_division_qualified_chain: 100,
  residuals: Object.fromEntries(RESIDUAL_CLASSES.map((c) => [c, 0])),
  reconciles_to_current_live_population: true,
  independent_review_confirmed: true,
  owner_authorized_retirement: true,
});

test('19: the retirement gate passes only on an exhaustive complete population', () => {
  assert.equal(evaluateRetirementGate(cleanMeasurements()).pass, true);
  for (const cls of RESIDUAL_CLASSES) {
    const m = cleanMeasurements();
    m.residuals[cls] = 1;
    const r = evaluateRetirementGate(m);
    assert.equal(r.pass, false, `residual class ${cls} must hold the gate closed`);
    assert.match(r.failures.join('\n'), new RegExp(cls));
  }
  for (const [key, bad] of [
    ['null_or_unresolved_creation_dates', 127],
    ['ledger_distinct_item_id_pk', 99],
    ['historical_items_with_complete_agreeing_triplet', 99],
    ['historical_items_with_active_division_qualified_chain', 99],
    ['reconciles_to_current_live_population', false],
    ['independent_review_confirmed', false],
    ['owner_authorized_retirement', false],
  ]) {
    const m = cleanMeasurements();
    m[key] = bad;
    assert.equal(evaluateRetirementGate(m).pass, false, `${key} must hold the gate closed`);
  }
});

test('19b: the gate is closed against the live population measured 2026-09-03', () => {
  const m = cleanMeasurements();
  m.null_or_unresolved_creation_dates = 127;
  const r = evaluateRetirementGate(m);
  assert.equal(r.pass, false);
  assert.match(r.failures[0], /127 live item\(s\) have a null or unresolved creation date/);
});

// ------------------------------------------------------- source reader safety

test('20: the CSV reader survives quotes, commas, newlines, CRLF and a BOM', async () => {
  const { parseCsv } = await import('./lib/csv.mjs');
  const text = '﻿a,b,c\r\n1,"two, and a half","line\nbreak"\r\n4,"say ""hi""",6\r\n';
  const rows = parseCsv(text);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].a, '1');
  assert.equal(rows[0].b, 'two, and a half');
  assert.equal(rows[0].c, 'line\nbreak');
  assert.equal(rows[1].b, 'say "hi"');
  assert.equal(parseCsv('').length, 0);
});

// ------------------------------------------------------ live driver data types

test('21: a pg Date creation date qualifies (regression: the first production run)', async () => {
  const { canonicalTimestamp } = await import('./lib/classify.mjs');
  // `pg` returns JS Date objects for timestamp columns. Stringifying one gives
  // "Mon May 13 2024 ...", which the old space-to-T rewrite turned into an
  // invalid date, so every real candidate abstained as NULL_TARGET_DATE and the
  // manifest came back with zero candidates and a clean-looking reconciliation.
  const r = qualify(sourceRow(), [item({ created_time_date: new Date('2024-01-15T10:00:00Z') })]);
  assert.equal(r.status, 'candidate');
  assert.equal(r.record.created_time_date, '2024-01-15T10:00:00.000Z');
  assert.equal(canonicalTimestamp(new Date('nope')), null);
  const post = qualify(sourceRow(), [item({ created_time_date: new Date('2025-06-01T00:00:00Z') })]);
  assert.equal(post.reason, ABSTAIN.NON_HISTORICAL_TARGET);
});

test('5c: a RETIRED conflicted row does not poison a clean active sibling code', async () => {
  const { RETIRED_CONFLICTED } = await import('./fixtures.mjs');
  const idx = buildTaxonomyIndex([...MERCH_GROUPS, RETIRED_CONFLICTED], divisionIndex);
  const r = qualifyCandidate({
    source: sourceRow(), liveMatches: [item()], divisionIndex, taxonomyIndex: idx,
  });
  assert.equal(r.status, 'candidate');
  assert.equal(r.record.after.udf_merchgroup03_id, 120);
  // but an ACTIVE conflicted row with no clean sibling still abstains
  const cw = qualifyCandidate({
    source: sourceRow({ division: 'CW001' }),
    liveMatches: [item({ div_code: 'CW001', div_code_fk: 2 })],
    divisionIndex,
    taxonomyIndex: idx,
  });
  assert.equal(cw.reason, ABSTAIN.TAXONOMY_DIVISION_CONFLICT);
});
