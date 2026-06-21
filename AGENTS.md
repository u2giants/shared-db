# AGENTS.md — shared-db cross-app coordination playbook

This repo (`u2giants/shared-db`) is the **single source of truth** for the unified
POP Supabase database used by four apps: CRM (`popcrm-web`), PM/PIM (`poppim-web`),
DAM (`popdam3`), and the `popcre/designflow-*` services. Its contents are
auto-mirrored into each consumer repo's read-only `shared-db/` folder by
`.github/workflows/sync.yml` on every push to `main`.

Read this before making any shared database, schema, migration, or cross-app
change. Detailed steps live in [`docs/contribution-workflow.md`](docs/contribution-workflow.md).

## Non-negotiable rules

1. **All database changes live here**, under `supabase/migrations/` — schemas,
   tables, columns, RLS, `api` views, RPCs, triggers, indexes, realtime. Never
   keep permanent DDL only in an app repo, and never hand-write production SQL in
   the Supabase dashboard.
2. **One shared project.** Do not create an app-specific Supabase project. Apps
   share `core` identity/reference objects (company, contact, factory, project,
   taxonomy). Do not create duplicate `crm.company` / `pim.company` etc. — add a
   nullable column (or `metadata`) on the canonical table instead, with a comment.
3. **Branch + PR, never commit straight to `main`.** Use
   `git checkout -b <app>-<short-description>`, add timestamped
   `YYYYMMDDHHMMSS_<app>_<desc>.sql` migrations, open a PR.
4. **The AI owns the merge.** Unlike the consumer app repos (which are `main`-only,
   no branches), `shared-db` changes go through a branch + PR that the AI author
   reviews and merges. Merging `main` triggers the sync workflow that propagates
   the change to every consumer's `shared-db/` folder — so merge deliberately,
   only after the migrations are validated and (where reachable) applied to the
   preview branch.
5. **Preview first, never develop against production.** Apply to the shared
   preview branch (`tcscehehgeiijilylezv`); production (`qsllyeztdwjgirsysgai`,
   live PopDAM) is promoted only by replaying committed migration files during an
   approved window.
6. **Keep changes additive** (nullable columns, `add column if not exists`, new
   views) so the shared preview and the other apps stay safe.
7. **Leave a handoff** under `docs/app-migration-notes/<app>-YYYYMMDD.md`.

## Schema ownership

`app` (identity/profiles/files/activity) · `core` (shared companies, contacts,
factories, taxonomy, SKU refs) · `crm` · `pim` · `dam` · `plm` · `ingest` ·
`api` (browser-facing views + RPC contracts). Browser code only reaches schemas
in the PostgREST exposed list (`alter role authenticator set pgrst.db_schemas`);
today: `public, graphql_public, api, crm, pim, core`.

## Where to look

- [`docs/contribution-workflow.md`](docs/contribution-workflow.md) — the exact clone → branch → migrate → validate → preview → PR → merge steps.
- [`docs/ai-session-instructions/`](docs/ai-session-instructions/) — per-app rewrite guides (CRM, PM/PIM) and the shared branch workflow.
- [`docs/unified-supabase-schema-map.md`](docs/unified-supabase-schema-map.md) — canonical entity/table ownership.
- [`supabase/migrations/`](supabase/migrations/) — the migration package itself.
