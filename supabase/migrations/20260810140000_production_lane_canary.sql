-- =============================================================================
-- PRODUCTION LANE CANARY  (issue #660 / #617)
--
-- WHAT THIS IS FOR, AND WHY IT IS DELIBERATELY BORING.
--
-- The production apply lane in `.github/workflows/shared-supabase-migrations.yml`
-- has never written to production. Not once. It was built, corrected twice, and
-- rehearsed, but the `db push` at the end of it has never executed against
-- qsllyeztdwjgirsysgai.
--
-- Four licensor features (Disney, Paramount, NBCU, Warner) are queued behind it.
-- Sending any of them through FIRST is a bad trade: if the run fails, you cannot
-- tell whether the LANE is broken or the MIGRATION is broken, and you find out
-- while a real feature is half-applied to a shared production database with no
-- undo. That confusion is not hypothetical -- this lane has already produced two
-- failures that looked like migration faults and were neither (a `$$`-inside-a-
-- comment lexer bug, and a prose-inside-a-string-literal lexer bug; see
-- `strip_sql` in scripts/production_migration_guard.py).
--
-- So this migration is customer #1. It exists to answer exactly one question --
-- "does the machinery work end to end?" -- and to answer it with a change whose
-- failure costs nothing and whose success is directly observable.
--
-- WHY A TABLE AND NOT A COMMENT. A comment leaves no queryable evidence, so a
-- successful run would be indistinguishable from a run that recorded a ledger
-- row without executing the SQL -- which is precisely the doubt issue #611 is
-- about. One row in one table is checkable:
--
--     select * from plm.production_lane_canary;   -- expect exactly 1 row
--
-- SAFETY PROPERTIES, each one intentional:
--   * Purely ADDITIVE. It creates one new table in an existing schema and
--     touches nothing that any app reads. AGENTS.md section 4 rule 3.
--   * No app reads it, no app writes it, nothing depends on it. Dropping it
--     later is a no-op for every consumer.
--   * RLS is ENABLED WITH NO POLICIES, and no role is granted anything. Under
--     PostgREST that makes it invisible and unwritable to `anon` and
--     `authenticated`. A canary must not become an accidental attack surface.
--   * `if not exists` so a re-run cannot fail.
--
-- DO NOT extend this table, do not add columns to it later, and do not build
-- anything on it. If you need a second canary, write a second migration.
-- =============================================================================

create table if not exists plm.production_lane_canary (
  id            bigint generated always as identity primary key,
  -- The lane that wrote the row. Recorded so a future reader can tell a real
  -- production apply from a hand-run statement.
  applied_by    text        not null default 'shared-supabase-migrations.yml production-apply',
  applied_at    timestamptz not null default now(),
  note          text        not null
);

comment on table plm.production_lane_canary is
  'No-op canary for the bounded production migration apply lane (issue #660). '
  'Written by migration 20260810140000 as the first change ever pushed through '
  'the production-apply job, so that a lane failure could never be confused '
  'with a licensor feature failure. No application reads or writes this table. '
  'Do not extend it and do not build on it.';

alter table plm.production_lane_canary enable row level security;

-- No policies and no grants, on purpose. See the header.

insert into plm.production_lane_canary (note)
values (
  'Canary for the bounded production apply lane. If this row exists on '
  'qsllyeztdwjgirsysgai, the lane executed migration SQL against production '
  'and recorded its ledger row -- the machinery works. Issue #617/#660.'
);
