# Contribution Workflow — All Apps Use This Repo For Database Changes

This is the canonical rule for every app that uses the shared POP Supabase
database (CRM `popcrm-web`, PM/PIM `poppim-web`, DAM `popdam3`, and the
`popcre/designflow-*` services). Read it before adding any schema change.

## The Rule

**All database changes — schemas, tables, columns, RLS policies, `api` views,
RPCs, triggers, realtime publication, indexes — live in this repo
(`u2giants/shared-db`), under `supabase/migrations/`.**

Do **not**:

- Put permanent DDL only in an app repo (`popcrm-web`, `poppim-web`, etc.).
- Hand-write production SQL in the Supabase dashboard SQL editor.
- Create an app-specific Supabase project for CRM/PM/DAM. There is one shared
  project; the apps share `core` identity/reference objects.
- Edit the mirrored `shared-db/` copy inside a consumer repo — it is read-only and
  overwritten on the next sync (see the README banner and `.github/workflows/sync.yml`).

Why: `shared-db` is the single source of truth. Its contents are auto-mirrored
into every consumer repo's `shared-db/` folder, so all four apps can see each
other's schema. Production promotion is migration-file based and must replay the
exact files committed here.

## How To Contribute A Migration (every app, every session)

1. Clone the canonical repo (not the mirror):

   ```bash
   git clone https://github.com/u2giants/shared-db.git
   cd shared-db
   ```

2. Create a branch — never commit straight to `main`:

   ```bash
   git checkout -b <app>-<short-description>     # e.g. crm-supabase-migration
   ```

3. Add timestamped migration files under `supabase/migrations/`, named with the
   app and purpose so parallel app sessions don't collide:

   ```text
   supabase/migrations/YYYYMMDDHHMMSS_crm_<short_description>.sql
   supabase/migrations/YYYYMMDDHHMMSS_pim_<short_description>.sql
   ```

   Keep changes additive (nullable columns, `add column if not exists`, new views)
   so they are safe for the shared preview branch and the other apps.

4. Validate locally before touching shared infrastructure:

   ```bash
   scripts/check-sql.sh
   # optional but recommended: run the full chain on a throwaway Postgres
   #   docker run -d -e POSTGRES_PASSWORD=pass -p 55432:5432 postgres:15
   #   (bootstrap auth.users/auth.uid()/auth.jwt()/authenticator role, then psql -f each migration)
   ```

5. Apply to the **preview branch only** (never production while developing):

   ```bash
   supabase link --project-ref tcscehehgeiijilylezv     # preview, not production
   supabase db push --dry-run
   supabase db push
   supabase migration list
   ```

   If `db push` fails with a login-role/connection error, set
   `SUPABASE_DB_PASSWORD` for the preview branch (do not commit it). If the branch
   DB is unreachable from your environment, use the Supabase MCP / management API
   to apply, or hand off the exact migration list to someone who can reach it.

6. Open a Pull Request against `u2giants/shared-db`:

   ```bash
   git push -u origin <app>-<short-description>
   gh pr create --fill
   ```

   The PR is the review record. Once merged to `main`, the sync workflow mirrors
   the migrations into every consumer repo's `shared-db/` folder automatically.

7. Commit the matching app frontend/worker changes in the app repo (generated
   types, client code) — but not the DDL.

8. Leave a handoff note under `docs/app-migration-notes/<app>-YYYYMMDD.md`
   (tables/views/RPCs each screen uses, new migrations, RLS changes, realtime,
   reconciliation, preview test results, exact production migrations to apply).

## Schema Ownership (where a change belongs)

| Schema | Use |
|---|---|
| `app` | profiles, roles, app access, comments, activity, notifications, files |
| `core` | shared companies, contacts, licensors, properties, characters, factories, taxonomy, SKU refs |
| `crm` | CRM-only operational tables |
| `pim` | PM/PIM product/project/design/workflow/order tables |
| `dam` | DAM assets/style groups/style guides/queues |
| `plm` | item master, production order, licensing/RFQ operational records |
| `ingest` | raw imports, snapshots, sync runs, dedupe candidates |
| `api` | browser-facing views and RPC contracts |

Shared identity/reference objects (company, contact, factory, project, taxonomy)
belong in `core`/`pim`. Do **not** create duplicate `crm.company` / `pim.company`
etc. If an app needs an app-specific attribute on a shared object, add an explicit
nullable column (or use `metadata`) on the canonical table, with a comment.

## Browser Exposure

The browser only reaches schemas listed in the PostgREST exposed-schemas setting
(`alter role authenticator set pgrst.db_schemas = ...`). Today that is
`public, graphql_public, api, crm, pim, core`. If your app needs another schema
reachable from the browser, change it in a migration (additively) and reload
PostgREST (`notify pgrst, 'reload config'`), and say so in your PR.
