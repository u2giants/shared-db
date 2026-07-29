# HANDOFF — `u2giants/shared-db`: ClickUp importer + duplicate-timestamp remediation

**Written:** 2026-07-29. **Author:** AI session working from `/worksp/poppim-web`.
**Read this whole file before touching anything.** Two of the items below are blocking, and one of them is a data-loss risk on a database three live apps depend on.

---

## 1. What this application is

`u2giants/shared-db` is the **canonical repository for a single Supabase Postgres database that four applications share**:

| App | What it is | Status |
|---|---|---|
| **Poppim** (`poppim-web`) | Product information manager, `pm.designflow.app` | in development, not launched |
| **PopCRM** (`popcrm-web`) | CRM | live |
| **PopDAM** (`popdam3`) | Digital asset manager, `dam.designflow.app` | live |
| **DesignFlow PLM** (`designflow-*`) | Product lifecycle management | live |

Supabase project refs:
- **production** `qsllyeztdwjgirsysgai`
- **preview** `rjyboqwcdzcocqgmsyel` (branch `shared-db-schema-rehearsal`, a **persistent clone of production including data** — treat its data and credentials as production-sensitive)

Because the database is shared, a bad migration breaks all four apps at once. That is why `AGENTS.md` in this repo mandates: branch + PR + timestamped migration + preview-first, never edit a landed migration, one schema change in flight.

Consumer repos (e.g. `poppim-web`) carry a **read-only mirror** at `<repo>/shared-db/`. Never author schema changes there; CI (`.github/workflows/shared-db-guard.yml` in the consumer repo) enforces it. All schema work happens in the canonical repo, then flows back to consumers via `chore: sync shared-db @ <sha>` commits.

**Key table for this work:** `pim.product`. Its identity/dedupe key is `unique nulls not distinct (external_source, external_id)`. It also carries legacy `clickup_task_id`, `clickup_parent_id`, `clickup_status` columns and a `metadata jsonb` blob from a one-time historical import.

---

## 2. What we set out to do, and why

**Business goal:** Poppim's product data came from a one-time historical ClickUp import. There was no ongoing sync, so anything changed in ClickUp since then never reached Poppim. The owner asked to "pull in everything from the ClickUp API since the last time we imported."

**Technical objective:** a repeatable, incremental importer — pull only ClickUp tasks changed since the last successful run, upsert into `pim.product`, track the watermark durably, never clobber curated Poppim data.

**Scope deliberately excluded:** mapping ClickUp custom fields (buyer / licensor / customer / factory) into first-class product relationships. Raw task payloads are stored in `ingest.raw_record`, so a later pass can map them **without re-pulling from ClickUp**.

---

## 3. Current state — what is true right now

### Open PRs from this session

| PR | Branch | State | Blocking? |
|---|---|---|---|
| [#311](https://github.com/u2giants/shared-db/pull/311) | `fix/clickup-importer-correctness` | open, **BLOCKED** | yes — see §6 step 2 |
| [#307](https://github.com/u2giants/shared-db/pull/307) | `docs/local-replay-unsupported` | open, mergeable | no |
| [#300](https://github.com/u2giants/shared-db/pull/300) | `claude/clickup-incremental-import-20260728` | **closed**, superseded by #311 | no |

(#238 is open but unrelated to this session — not ours.)

`fix/clickup-importer-correctness` is pushed, 2 commits ahead of `main`:
- `cab6813` forward migration fixing 5 correctness defects
- `0783254` fix the legacy-row matching (the duplicate-products bug)

Nothing from this session has been applied to preview or production. **Zero database writes were made.** Every database interaction was read-only.

### What is on `main` right now, and it is wrong

`supabase/migrations/20260728160000_clickup_incremental_task_import.sql` — the **original, defective** ClickUp importer — is merged to `main`. It got there via **unrelated PR #305** ("feat(db-data-admin): name the PLM divisions instead of printing raw ids"), which swept in all three ClickUp files without them being reviewed as ClickUp changes. It carries all 5 correctness defects listed in §5.

### The migration on `main` never actually executed

`20260728160000` is a **duplicate timestamp**. Two files share it:

- `20260728160000_clickup_incremental_task_import.sql` (added by `8a7197f`, via PR #305)
- `20260728160000_popdam_user_tables_foreign_keys.sql` (added by `0b8425b`)

Supabase's ledger (`supabase_migrations.schema_migrations`) keys on the **version** (the leading 14-digit timestamp), not the filename. It recorded the version once and executed **one** file. Verified read-only against preview on 2026-07-29:

- PopDAM side **ran**: `profiles_user_id_fkey`, `user_roles_user_id_fkey`, `app_access_user_id_fkey` all present (3/3); `user_roles_user_id_idx`, `app_access_user_id_idx` present (2/2).
- ClickUp side **did not run**: `pim.sync_clickup_tasks` does not exist (0 rows in `pg_proc`); 0 of the 7 new `clickup_*` columns exist on `pim.product`.
- The ledger nonetheless reports `20260728160000` as applied, so it will **never be retried**.

This is currently the **only** duplicate in the repo — verified with
`ls supabase/migrations/ | awk -F_ '{print $1}' | sort | uniq -d` (returns exactly one value).

### Verified working (local only)

On the `fix/clickup-importer-correctness` branch:
- `node --test tools/sync-clickup-tasks.test.mjs` → **40 pass, 0 fail**
- `scripts/check-sql.sh` → clean, exit 0
- `supabase/tests/clickup_task_import_contracts.sql` → **7/7 PASS** against a throwaway Postgres with the fix applied

Critically, the same contract suite was run against the **pre-fix** state to prove the tests actually catch the bugs:
```
C1 PASS  C2 PASS
ERROR:  C3: watermark advanced on partial failure
ERROR:  C4: unchanged row bumped updated_at
C5 PASS
ERROR:  C6: DUPLICATE PRODUCT — expected exactly 1 row for clickup_task_id dir9001, got 2
ERROR:  C7: unique index on btrim(clickup_task_id) is missing
```
A test suite that passes both before and after a fix proves nothing. These fail before, pass after.

**Never rehearsed against hosted Supabase.** All runs were stock Postgres 15/16 with an `auth`/roles shim. The preview apply is still the real gate and has not happened.

---

## 4. Everything we tried that did NOT work

Read this section. It is the difference between a two-hour session and a two-day one.

### 4.1 A code review that returned zero findings, and was wrong

The first adversarial review of the importer (Grok, default non-reasoning model) read all 1,354 lines and returned **zero findings**, declaring every area correct — backfill, watermark, locking, tests, conventions.

A second pass at the same task (`grok-4.5`, `--reasoning-effort medium`), explicitly told not to anchor on the first result and to assume at least one defect existed, found **five real defects**, two of which were then confirmed by reading the code directly.

**Lesson:** a zero-finding review on a large diff touching a shared production database is evidence of a weak reviewer, not of good code. Do not accept "all clear" without spot-checking the claims yourself.

### 4.2 Three reviews missed the biggest bug entirely

The duplicate-products bug (§5.1) — the one that would have inserted 17,859 junk rows — was missed by:
1. the implementing agent,
2. the zero-finding review,
3. the thorough adversarial review that found five other defects,
4. and this session's own verification of all of the above.

Every one of them reasoned about the logic against the **assumed** data shape. The bug only surfaced when the actual preview database was queried. **Reason about schemas from the data, not from the DDL.**

### 4.3 Trying to replay all migrations locally

Applying every migration in filename order against an empty Postgres fails. Two separate sessions independently diagnosed this as "an ordering bug in the `assets` migrations" and reported it as a defect. **That diagnosis is wrong and was retracted.**

Roughly **170 of the 366 migration files are intentionally empty markers** for objects created before `shared-db` became canonical. Nothing in the repo ever creates those objects, so on a from-scratch database every later migration referencing one fails — ~63 failures, all of that class. The two `assets` files that look misordered are both empty and cannot fail.

Deploys are unaffected: CI links to a live project and `supabase db push` applies only migrations missing from that project's ledger. The markers are already recorded there.

**This is documented in PR #307.** Merge it so nobody rediscovers this a third time.

**To test a migration locally**, apply only the dependency closure:
```
supabase/migrations/20260621150714_foundation.sql
supabase/migrations/20260621150815_app_core.sql
supabase/migrations/20260621151024_domain_tables.sql
supabase/migrations/20260621151155_api_rls_realtime.sql
<your migration>
```
plus this shim (stock Postgres lacks what hosted Supabase provides):
```sql
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, raw_app_meta_data jsonb default '{}'::jsonb, created_at timestamptz default now());
create or replace function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true),'')::jsonb,'{}'::jsonb) $$;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true),''),'authenticated') $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='supabase_admin') then create role supabase_admin; end if;
end $$;
create extension if not exists dblink;  -- needed for contract test C5
```
Without `dblink`, contract case C5 (advisory lock) SKIPs rather than fails. Install it, or verify the lock by hand with two connections.

### 4.4 `op read` secret references that silently fail to parse

`op://vibe_coding/<item title>/<field>` **fails to resolve** when the item title contains parentheses — e.g. `Supabase Preview Branch Credentials - shared POP database (shared-db-schema-rehearsal)`. The error is a generic parsing failure that looks like a permissions problem.

**Use the item ID instead:** `op://vibe_coding/qbvfk7umc3n75ejekd65zwd4ty/DB_PASSWORD`. Also note the field is `DB_PASSWORD`, not `password`.

### 4.5 Merging `main` into the original ClickUp branch

Produced add/add conflicts on our own files, which looked like corruption. Cause: PR #305 had already put identical copies of those files on `main`. Aborted the merge and branched fresh from `main` instead. Do not try to reconcile `claude/clickup-incremental-import-20260728` — it is abandoned and its PR is closed.

---

## 5. Root causes and key findings

### 5.1 The importer would have created 17,859 duplicate products (fixed in #311)

**This is the most important finding of the session.**

The original design upserts on `(external_source, external_id)` and relied on a backfill to first claim legacy rows by setting `external_source='clickup', external_id=clickup_task_id` **where `external_source IS NULL`**.

Actual preview data (read-only query, 2026-07-29):

| `external_source` | rows | have `clickup_task_id` | `external_id = clickup_task_id` |
|---|---|---|---|
| `directus_product` | 17,859 | 17,859 | **0** |
| `clickup` | 50 | 50 | 50 |
| `NULL` | **0** | — | — |

There are **no** rows with a null `external_source`. The backfill claimed nothing. The 17,859 legacy products are keyed to Directus and were unreachable by the ClickUp key — so the importer would have **inserted a duplicate row for every one of them**.

Data quality made the fix safe: **17,909 distinct `clickup_task_id` values over 17,909 rows, zero duplicates, and no id appearing under more than one `external_source`.**

**Fix (commit `0783254`):** resolve each incoming task by trimmed `clickup_task_id` **first** and update that row in place, leaving `external_source`/`external_id` untouched (the Directus key stays as the historical record). The ClickUp-key upsert remains but only as the new-task path. The dead backfill is removed. New counters `rows_matched_by_clickup_task_id`, `rows_matched_by_clickup_key`, `rows_matched_foreign_source` plus a per-source breakdown make legacy matching **visible** rather than inferred.

Also adds a **unique index on `btrim(clickup_task_id)`** (non-null, non-blank) so this cannot silently recur. **This is a shared-schema change affecting all four apps** — see §7.

### 5.2 Five correctness defects in the original importer (fixed in #311)

1. **Watermark stamped after the fetch.** `v_started_at := now()` was evaluated *inside* the SQL function, which runs only after the Node script finishes pulling every list (minutes). Anything edited mid-run was stamped as already-synced and **never re-fetched**. Fix: script passes a pre-fetch `fetch_started_at`, used minus a 60s overlap (`date_updated_gt` is strict; the upsert is idempotent so re-reading a boundary task is harmless).
2. **Partial failure advanced the watermark.** A task that failed once fell behind the cutoff forever; a total-failure batch still reported `succeeded`. Fix: watermark does not advance when `rows_failed > 0`; run marked `outcome='succeeded_with_failures'` / `partial_failure=true` (the `ingest.sync_status` enum has no `partial` value). `snapshot.skip_task_ids` is the explicit escape hatch so a permanently-malformed id cannot wedge the sync — that was the original author's legitimate concern, now handled without silent data loss.
3. **Backfill wrote untrimmed ids.** Guard used `btrim(...)` but the assignment wrote the raw value, so `'123 '` and `'123'` could coexist and fork a product.
4. **No-op upserts bumped `updated_at`**, making every task look freshly edited and poisoning the `(clickup_list_id, updated_at)` index.
5. **Runner exited 0 when nothing happened** — on `locked = true` and on `rows_failed > 0`. A cron job would report green while data did not move.

### 5.3 Duplicate migration timestamps silently skip a migration

Root cause of §3. `20260728160000_popdam_user_tables_foreign_keys.sql` landed first (`0b8425b`); the ClickUp migration was authored on a branch cut **before** that commit and merged later via PR #305. Nothing caught the collision: `scripts/check-sql.sh` has no duplicate-version check, and no workflow in `.github/workflows/` does either.

**Symptom to recognise:** objects missing from the database while the ledger reports the version as applied.

### 5.4 PR #305 swallowed files from an unrelated branch

PR #305 was titled "name the PLM divisions instead of printing raw ids" and its commit `8a7197f` added `tools/sync-clickup-tasks.mjs`, `tools/sync-clickup-tasks.test.mjs`, and the ClickUp migration. **Not investigated.** This is a process defect that will recur — see §6 step 6.

---

## 6. Exact next steps

Execute in this order. Steps 1–3 are sequential and blocking.

### Step 1 — Confirm production's actual state (READ-ONLY)

Everything in §3 was measured on **preview**. Production has not been checked. Determine whether it shows the same split.

```sql
-- does the PopDAM half exist?
select count(*) from pg_constraint
 where conname in ('profiles_user_id_fkey','user_roles_user_id_fkey','app_access_user_id_fkey');
-- does the ClickUp half exist?
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'pim' and p.proname = 'sync_clickup_tasks';
select count(*) from information_schema.columns
 where table_schema='pim' and table_name='product'
   and column_name in ('clickup_creator_id','clickup_folder_id','clickup_list_id',
                       'clickup_space_id','clickup_status_type','clickup_time_estimate_ms',
                       'clickup_orderindex');
-- and the real data shape, which drives everything in 5.1
select external_source, count(*),
       count(*) filter (where clickup_task_id is not null) as with_task_id,
       count(*) filter (where external_id = clickup_task_id) as id_matches_taskid
  from pim.product group by 1 order by 2 desc;
select count(*) from (select btrim(clickup_task_id) t from pim.product
  where clickup_task_id is not null group by 1 having count(*) > 1) x;  -- must be 0
```

**Reads only. No writes, no apply, no `migration repair`.** Use the read-only AI identity per the standing infrastructure rule; never Owner/Editor or Terraform-admin credentials.

**You'll know it worked when:** you can state, with numbers, whether production matches preview (PopDAM applied / ClickUp skipped) and whether the zero-duplicate-`clickup_task_id` precondition holds there. If it does **not** hold, **stop** — the unique index in #311 will fail and §5.1's fix needs rethinking.

### Step 2 — Re-issue the skipped ClickUp migration (unblocks #311)

**Do not rename `20260728160000_clickup_incremental_task_import.sql`.** It is landed on `main`, `AGENTS.md` forbids editing prior migrations, and renaming changes a version the ledger already holds.

**Do not use `supabase migration repair`.** It rewrites ledger state on a shared production database to paper over a repo-side naming mistake. Forward migrations are auditable; ledger surgery is not.

Add a **new** migration carrying the skipped file's DDL, fully idempotent:
- Timestamp **between `20260728171500` and `20260728181500`** — e.g. `20260728174500` — so it lands before #311 without renumbering #311.
- Every statement guarded: `add column if not exists`, `create index if not exists`, `create or replace function`. It must be a clean no-op where the original somehow did run.
- Header comment stating it re-issues `20260728160000`, why (duplicate version → silently skipped), and how the ledger behaves — so nobody later "cleans up" the apparent redundancy.

**You'll know it worked when:** applied to the local dependency closure it creates all 7 `clickup_*` columns and `pim.sync_clickup_tasks`; applying it a second time prints no changes and errors nothing; and the PopDAM foreign keys and indexes are still present afterwards.

### Step 3 — Land #311, then rehearse on preview

1. Merge Step 2's migration to `main`.
2. Rebase `fix/clickup-importer-correctness` on `main`. Remove the "blocked" comment on #311.
3. `supabase db push --dry-run --linked` (must be linked to preview `rjyboqwcdzcocqgmsyel`, confirm via `cat supabase/.temp/project-ref`).
4. `supabase db push --linked`.
5. Run `supabase/tests/clickup_task_import_contracts.sql` against preview.
6. Run the importer `--dry-run` against preview, review the snapshot.
7. Run `--apply --linked`. Confirm from `ingest.sync_run` metadata: `rows_matched_by_clickup_task_id` is large, `rows_inserted` is near zero, product row count is unchanged.
8. Re-run immediately — expect `rows_unchanged` high and `rows_updated` ≈ 0, proving the incremental watermark works.

**You'll know it worked when:** `pim.product` row count before and after the first `--apply` is identical, and step 8 shows a near-empty second run.

### Step 4 — Merge docs PR #307

Independent of everything above, mergeable now. Documents why clean-slate local replay cannot work (§4.3), so the next session does not burn an hour re-diagnosing it.

**You'll know it worked when:** `AGENTS.md` on `main` contains the `## 10.1` section.

### Step 5 — Add CI guards against duplicate timestamps

Implement in `scripts/check-sql.sh` (already the repo's static gate, referenced throughout `AGENTS.md`) so it runs locally and in CI:
- **Guard A:** extract the leading `\d{14}` from every filename in `supabase/migrations/`; fail on any repeated value and print both offending filenames.
- **Guard B (recommended, catches the actual cause):** fail when a PR adds a migration whose timestamp is **earlier than the newest already on `main`**. That is precisely how this bug arose — a branch cut before another migration landed. Legal for Supabase, but dangerous in a repo with several parallel AI sessions.
- Add a unit test following the existing `scripts/*.test.mjs` pattern: no duplicates → pass; one duplicate → fail and name both files.
- Wire `check-sql.sh` into `.github/workflows/shared-supabase-migrations.yml` on `pull_request` if not already invoked there.

**You'll know it worked when:** deliberately duplicating a timestamp makes `scripts/check-sql.sh` exit non-zero and name both files; removing it passes.

### Step 6 — Investigate PR #305

Find out how a PR titled "name the PLM divisions instead of printing raw ids" came to add three unrelated ClickUp files in commit `8a7197f`. Likely candidates: a branch cut from another session's branch instead of `main`, a bad rebase, or an over-broad `git add`. This is a process defect that will recur and it is how unreviewed code reached `main`.

**You'll know it worked when:** you can state the mechanism and either fix the process or document the trap in `AGENTS.md`.

### Step 7 — Production sign-off (owner decision, not yours)

Only after Steps 1–3 are green on preview. Production apply requires the owner's **explicit** go-ahead naming the exact resource and action. "Fix deploys" or "apply the migration" is not approval.

### Step 8 — Downstream sync

After the migration merges, regenerate `poppim-web/src/lib/database.types.ts` so the new columns are typed, and land the usual `chore: sync shared-db @ <sha>` mirror commit in `poppim-web`.

---

## 7. Constraints and gotchas in force

- **Never edit a landed migration.** Forward migrations only (`AGENTS.md`).
- **Never author schema changes in a consumer repo's `shared-db/` mirror** (e.g. `/worksp/poppim-web/shared-db/`). CI enforces this.
- **Preview-first, always.** Production is dry-run + allowlist bounded. Never push straight to `qsllyeztdwjgirsysgai`.
- **AI sessions are read-only against production and shared cloud infrastructure by default.** No `terraform apply`, no mutating `gcloud`, no ledger surgery. Never disable/delete/recreate a `*-prod` Cloud Build trigger unless the owner names the exact resource and action in the current chat.
- **Preview contains a full production data clone.** Treat its data and credentials as production-sensitive. Never paste values into chat, files, logs, or commits.
- **Land shared-db PRs promptly.** The preview branch is shared and persistent; a stuck unmerged push blocks every other workstream.
- **The unique index added by #311 affects all four apps**, not just Poppim. Any app inserting a `pim.product` row with an already-used `clickup_task_id` will now get a unique violation instead of silently forking the product. That is the intent, but PopCRM / PopDAM / DesignFlow owners should be aware.
- **Curated Poppim fields must never be overwritten by the importer:** `project_id`, `licensor_id`, `property_id`, `factory_id`, `company_id`, `stage`, `cover_url`. They are excluded from the upsert `SET` list. `metadata` is **merged**, not replaced.
- **Git author must be** `Albert Hazan <u2giants@users.noreply.github.com>` — GitHub blocks the gmail address.
- **Commit style:** short imperative subject (`add`/`fix`/`update`/`remove`), no trailing period; body only for non-obvious rationale. No force push.
- **`date_updated_gt` is strict (`>`)**, hence the deliberate 60s watermark overlap. Re-reading a boundary task is harmless because the upsert is idempotent.

---

## 8. Access and environment

- **Repos on this machine:** canonical at `/worksp/shared-db`; consumer at `/worksp/poppim-web` (its `shared-db/` subdir is the read-only mirror).
- **`gh` CLI:** authenticated for `u2giants`. Used to open PRs #307 and #311 and close #300.
- **1Password MCP:** connected. Vault `vibe_coding` (id `pimcaogmxxzoafh7lsluj6uxkq`). Relevant items — **reference by location, never paste values**:
  - Supabase CLI PAT — item `3t2xoqk5luyz7ffgdhj24gvtpq`, field `credential`
  - Preview branch credentials — item `qbvfk7umc3n75ejekd65zwd4ty`, field `DB_PASSWORD` (see §4.4: use the **item ID**, the title has parentheses that break `op://` parsing)
  - ClickUp API credentials — item `vd5q2ryp7rm3fytxl65pkx5ysu`
  - xAI / Grok key — item `w62tejbutu42ryo6d3pr62a3iy`, field `api key` (note: `credential` is stale/invalid)
- **Supabase CLI** 2.98.2, currently linked to **preview** `rjyboqwcdzcocqgmsyel` (`cat supabase/.temp/project-ref` to confirm before any push).
- **Docker** 29.6.0 available for throwaway Postgres.
- **ClickUp list IDs** (discovered live from the API, already the documented default in `tools/sync-clickup-tasks.mjs`, overridable via `CLICKUP_LIST_IDS`): Licensing Management `13194624`, Sourcing/Sampling Projects `901104141567`, New Prod Development `901103451188`, Edge Generic `15061776`, Sprint 1 `901113451000`.
- **Untracked file** `/worksp/shared-db/.ai/reviews/clickup-import-fixes-glm.md` — a GLM implementation report, left uncommitted deliberately. Commit or delete as you prefer.

---

## 9. Open questions and risks

| Item | Detail | Dated |
|---|---|---|
| **Production state unknown** | All measurements are from preview. Production may differ. Step 1 resolves this and must run first. | 2026-07-29 |
| **Zero-duplicate precondition** | The unique index in #311 requires no duplicate `btrim(clickup_task_id)` in `pim.product`. Verified on preview (0). **Unverified on production.** If it fails there, #311's migration will abort — by design, it raises and names up to 50 offending ids. | 2026-07-29 |
| **Never rehearsed on hosted Supabase** | All verification was stock Postgres with an `auth`/roles shim. Hosted Supabase differs (RLS, roles, PostgREST schema exposure, pooler behaviour). Preview apply remains the real gate. | 2026-07-29 |
| **Ledger completeness unverified** | The claim that ~170 marker migrations are all recorded in the production ledger comes from the migration files' own comments and is consistent with CI behaviour, but was never confirmed against the live ledger. | 2026-07-29 |
| **PR #305 mechanism unknown** | How unrelated files entered that PR is not established. Until it is, assume it can happen again. | 2026-07-29 |
| **Disaster-recovery gap** | Because ~170 migrations are empty markers, this repo **alone cannot rebuild the shared database from nothing**. Closing that needs a checked-in baseline schema dump (a new file outside `migrations/`, so it would not violate the no-editing rule). Not done. | 2026-07-29 |
| **No ClickUp rate-limit backoff** | `fetchListTasks` has no 429 retry. Judged acceptable at current volume (5 lists, low change rate); a single 429 aborts the run **without** advancing the watermark, so it fails safe. Revisit if task counts grow. | 2026-07-29 |
| **Decision: match on `clickup_task_id`, do not re-key** | Owner chose to leave the 17,859 Directus keys intact rather than re-key them to ClickUp, to avoid rewriting the identity of every existing product. | 2026-07-29 |
| **Decision: `succeeded_with_failures` rather than a new enum value** | `ingest.sync_status` has no `partial`. Adding an enum value to a shared type was judged riskier than marking `metadata`. Revisit if the distinction needs to be queryable. | 2026-07-29 |

---

## Self-audit

**1. Could a brand-new developer with no project knowledge pick up and not skip a beat?**
Yes. §1 defines the apps, the shared-database risk, and the project refs. §2 gives the business goal. §3 gives exact PR/branch/commit state and what is on `main`. §6 gives numbered steps with verification gates. §8 names every credential by vault location and the exact CLI state.

**2. Could they continue as effectively as this session can right now?**
Yes. The non-obvious, hard-won findings are all written down: the real `external_source` data distribution that invalidated the design (§5.1), the duplicate-timestamp ledger behaviour and how to recognise it (§5.3), the `op://` parenthesis parsing trap (§4.4), the empty-marker migrations and the correct local test recipe including the `dblink` requirement (§4.3), and the fact that three prior reviews missed the biggest bug (§4.2).

**3. Is every detail needed for flawless execution present?**
Yes. Background §1–2; current state §3; failures §4; root causes with evidence §5; ordered next steps with gates §6; constraints §7; access §8; risks and dated decisions §9. Verification evidence is quoted verbatim, including the **pre-fix** contract-test failures that prove the tests are meaningful.

**Gaps found and fixed during audit:** added the `dblink` requirement for contract case C5; added the explicit "do not use `migration repair`" rationale to §6 step 2; added the unique-index cross-app impact to §7; added the stale `credential` field note for the xAI item to §8.
