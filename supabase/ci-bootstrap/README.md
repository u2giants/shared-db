# `supabase/ci-bootstrap/` — what a from-empty replay needs that the migrations do not supply

**Nothing in this directory is a migration. Nothing in it is ever applied to preview or
production.** It exists for one consumer: the throwaway Supabase stack that
`.github/workflows/database-contract-tests.yml` creates inside a GitHub runner.

## The problem this closes (issue #754)

This repository was adopted on top of an already-populated database. So a set of
relations — `public.assets`, the legacy popdam tables, the `plm.*` legacy mirrors —
exist in preview and production with **no migration here that creates them**.

Measured on the first-ever CI execution of `supabase/tests/` (PR #741, issue #731):
replaying all 429 migrations into an empty database applied **363** and failed **66**.
Everything downstream of those 66 was missing from the ephemeral schema, so **26 of the
40 contract test files were quarantined** — they ran, their output was published, and
they could not pass. The lane proved only the subset of the contract provable from the
repository alone.

Two artifacts were missing. They are here.

## `010_pre_adoption_baseline.sql`

The **schema only** of every relation that exists in production but that no migration in
this repository creates. 126 tables, 1 view, 159 primary/unique/check constraints, 179
indexes, 58 foreign keys.

**No rows. Not one.** No production data, no personal data, no licensed data. Test data
belongs in `020_test_fixture_seed.sql` and is synthetic.

### Why it is not a migration, and must not become one

A new migration inserted at the **front** of an already-applied sequence cannot re-run
against preview or production: their ledgers are long past this point, and a back-dated
version is exactly what the Guard B backdating check exists to stop. The deployed
databases already contain every object in the file — applying it there would be a no-op
at best and a conflict at worst. The only consumer that needs it is a from-empty replay,
which only ever happens inside the CI runner. So it lives outside
`supabase/migrations/`, owns no version, and is applied only by the workflow.

### How to re-capture it

Read-only, from production, schema only. Nothing below writes anything.

1. **Compute the object set — do not hand-pick it.** Parse every
   `CREATE TABLE|VIEW <schema>.<name>` out of `supabase/migrations/*.sql`. The baseline
   set is every relation in `public`, `plm`, `dam`, `dflow`, `core` and `api` that this
   parse does **not** name.
2. **Generate the DDL** with a single `SELECT` against production that assembles
   `CREATE TABLE` from `pg_attribute` + `pg_attrdef`, `pg_get_constraintdef` for
   constraints, `pg_get_indexdef` for indexes and `pg_get_viewdef` for views — ordered
   tables → keys/checks → indexes → foreign keys → views.
3. **Run it read-only.** Use the Supabase Management API query endpoint
   (`POST /v1/projects/{ref}/database/query`) with `read_only: true`, authenticated with
   the *Supabase CLI Personal Access Token* item in the `vibe_coding` 1Password vault.
   Never `psql` into production, never `apply_migration`, never `supabase db push`.
4. **Emit only foreign keys whose target is also in the baseline set.** A key pointing at
   a table that a *migration* creates would be added twice.
5. **Scan the result before committing**: no `INSERT`/`COPY`, no email addresses, and
   read the distinct string literals — they must be nothing but column names and enum
   labels.

### When it is wrong

It is a snapshot of production's *current* shape for these objects, which is the shape a
from-empty replay must reach. If a future migration starts creating one of these objects
itself, **delete it from the baseline** — otherwise the workflow reports a duplicate. Every
run prints the baseline's statement-error count, so that drift is visible, never silent.

## `020_test_fixture_seed.sql`

Four active authenticated profiles, one Licensor, one Property, one Customer, one
Factory, one ColdLion source ref. That is the whole of it, and it is all the eleven
data-needing contract tests ask for.

**Every row is invented.** Names are prefixed `ZZ Fixture` so that a row escaping into a
real database is instantly recognisable as test scaffolding. Email addresses use the
RFC 2606 reserved `.invalid` top-level domain, which cannot resolve and cannot belong to
anyone. The workflow **fails the job** if any address outside `fixture.invalid` appears
in the file.

If you need another fixture row, **invent it**. Do not copy one from preview or
production "just to get the shape right" — the shape is in `supabase/migrations`, and the
PII forward guard will catch you.

Roles are not seeded here: `20260621150815_app_core.sql` already inserts all six.
`app.app_access` is not seeded here either: each test grants and revokes its own inside
its own transaction, which is the behaviour under test.

## How the workflow uses them

```
start empty stack
  PASS 1   replay all 429 migrations, record failures        <- unchanged
  BASELINE apply 010_pre_adoption_baseline.sql
  PASS 2   re-run ONLY the pass-1 failures
  SEED     apply 020_test_fixture_seed.sql
  TESTS    run every supabase/tests/*.sql
```

The baseline lands **between** the passes, not before pass 1. Some of its columns are
typed with enums that `20260621150714_foundation.sql` creates (`app.entity_status`).
Applied first, the baseline would have to create those types itself, and foundation's
unguarded `CREATE TYPE` would then fail — trading one gap for a worse one.

Both passes print their counts in the job summary, so what is still missing is a number
on every run rather than a footnote in a file nobody opens.
