import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const migration = readFileSync(
  new URL('../supabase/migrations/20260823232256_create_dflow_prod_and_audit_archive.sql', import.meta.url),
  'utf8',
);
const prior = readFileSync(
  new URL('../supabase/migrations/20260802194000_fix_style_tracker_rfq_groups_timeout.sql', import.meta.url),
  'utf8',
);

function viewBody(sql) {
  const start = sql.indexOf('create or replace view public.style_tracker_rows_with_bridge as');
  const end = sql.indexOf('\n) rfq on true;', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  return sql.slice(start, end + '\n) rfq on true;'.length);
}

test('migration is structure-only and uses the reserved version', () => {
  assert.doesNotMatch(migration, /^\s*(?:insert|update|delete|copy|truncate)\b/im);
  assert.match(migration, /20260823232256|Issue #1352/);
  assert.match(migration, /expected 103 tables/);
  assert.match(migration, /high-water is id, never actionDate/);
});

test('new Sample Tracking-only surface is excluded fail-closed', () => {
  for (const name of [
    'sample_import_job', 'sample_import_row', 'sample_movement',
    'sample_shipment_line', 'sample_stop_closeout', 'sample_visit',
    'sample_visit_event', 'sample_visit_plan',
  ]) {
    assert.match(migration, new RegExp(`table_name IN\\([^)]*${name}`));
  }
});

test('style tracker bridge body is preserved except for the RFQ schema', () => {
  const expected = viewBody(prior)
    .replaceAll('dflow."RFQItem"', 'dflow_prod."RFQItem"')
    .replaceAll('dflow."RFQGroup"', 'dflow_prod."RFQGroup"');
  assert.equal(viewBody(migration).replaceAll('\r\n', '\n'), expected.replaceAll('\r\n', '\n'));
});

test('audit live/archive search and export contract is indexed', () => {
  assert.match(migration, /CREATE VIEW dflow_prod\."AuditLogHistory"/);
  for (const field of ['"moduleName"', 'ref_id_fk', 'user_id_fk', 'username', '"actionType"', '"actionDate"']) {
    assert.match(migration, new RegExp(field.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(migration, /Indefinite archive/);
});
