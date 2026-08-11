# Batch B2 production promotion — evidence (2026-08-11)

Issues: #730, #710. Claim: #740. Target: **production `qsllyeztdwjgirsysgai`** (confirmed live via
`get_project_url` → `https://qsllyeztdwjgirsysgai.supabase.co` before every action). Preview
`rjyboqwcdzcocqgmsyel` was never touched.

**STATUS AT TIME OF WRITING: NOT APPLIED. Blocked on the `production` environment approval,
which only Albert can click.** All automated gates are green. See §6.

---

## 1. The batch

| Version (exact, 14-digit) | File |
|---|---|
| `20260728171500` | `20260728171500_db_data_admin_tree_plm_division_names.sql` |
| `20260728174500` | `20260728174500_clickup_incremental_task_import_reissue.sql` |
| `20260728181500` | `20260728181500_clickup_incremental_task_import_fixes.sql` |

`20260728181500` is a legal resting point per
`docs/production-promotion-app-tolerance-contract.md` §6. `20260728171500` and `20260728174500`
are both on the never-rest list, so this batch is all-or-nothing.

## 2. Baseline, re-verified live (not copied from any brief)

- `origin/main` at dispatch: `d0a832c5c380fe5b997d436786c330ec9ce988de` (PR #742).
- Production ledger immediately before dispatch: **373 rows**, max version `20260810140000`.
- All three B2 versions absent from the ledger (`b2_applied = 0`).
- The ledger is applied out of order; the high max does not imply the range below it is complete.

## 3. Trap 1 — the string-patch anchors, VERIFIED PRESENT IN THE LIVE BODY

`20260728171500` reads the live catalog body of
`api.db_data_admin_licensor_property_tree(text, boolean, text, integer)` via `pg_get_functiondef`,
counts two anchors, string-patches both, and `execute`s the result. It raises if the counts are
wrong. Measured directly against production:

| Anchor | Required | Found in live body |
|---|---|---|
| `'division_code', pi.division_code,` | exactly 2 | **2** |
| `'division_code', li.division_code,` | exactly 1 | **1** |
| `division_name` (must be ABSENT — not already patched) | 0 | **0** (position 0) |

Live function body length: 13,802 characters. The patch will apply as designed; it will neither
raise nor silently patch nothing.

## 4. Trap 2 — `plm."divisionCode"`, VERIFIED PRESENT

The tolerance contract §7.3 flags that this table is created nowhere in the backlog. It **does
exist in production**:

- `to_regclass('plm."divisionCode"')` → `plm."divisionCode"`
- Columns present and correctly typed for the migration's three reads:
  `divCode_id` (integer), `divCode_code`, `division_name`, `company_name_fk`,
  `external_divisoncode`, `is_divcode_active`.

The migration casts `divCode_id::text` to compare against `division_code`, which is consistent
with the integer column type. No blocker.

## 5. Other preconditions checked directly against production before dispatch

| Precondition | Required by | Live result |
|---|---|---|
| `pim.product` duplicate `btrim(clickup_task_id)` | `181500` §2 pre-guard raises on any duplicate | 17,909 rows with a task id, **17,909 distinct** — zero duplicates, guard will pass |
| Untrimmed clickup `external_id` | `181500` §1 trim repair | **0** — repair is a clean no-op, records no audit row |
| `pim.product` rows with `external_source IS NULL` | `174500` §2 backfill | **0** — backfill claims nothing and (by its idempotency guard) writes no `ingest.sync_run` row |
| `external_source` distribution | `181500` defect 6 premise | `directus_product` 17,859 / `clickup` 50 — matches the migration's stated production shape exactly |
| `ingest.raw_record`, `ingest.sync_run` | importer writes | both exist |
| `app.has_role` | `174500` §5 `api.clickup_task_sync_run_list` body | exists as `app.has_role(app.app_role)`; `administrator` is a valid `app.app_role` label, so the unknown literal resolves |
| Target objects already present? | idempotency | `pim.sync_clickup_tasks`, `pim_product_clickup_task_id_uidx`, `pim_product_clickup_list_updated_idx` all **absent** — this is a genuine first application |

## 6. Lane runs

### 6.1 Production dry-run — GREEN
Run <https://github.com/u2giants/shared-db/actions/runs/31450106237> (SHA `383d37c`).

```
BOUNDED OK: 376 migration files on disk, all within remote-ledger | allowlist (3 allowlisted).
Would push these migrations:
 • 20260728171500_db_data_admin_tree_plm_division_names.sql
 • 20260728174500_clickup_incremental_task_import_reissue.sql
 • 20260728181500_clickup_incremental_task_import_fixes.sql
```

376 on disk = 373 already-applied + the 3 allowlisted. Exactly the batch, nothing else.

### 6.2 First apply dispatch — FAILED SAFELY, NOTHING WRITTEN
Run <https://github.com/u2giants/shared-db/actions/runs/31450186206> (SHA `383d37c`).

PR #742 merged at 01:43Z and moved `main` to `d0a832c` roughly one minute before this dispatch.
The `Verify exact main commit` step in `production-apply-review` refused with exit 1. **This is the
guard working correctly** — it fails before any credential is used, before any checkout of the
bounded set, and long before any push. Production was not touched.

Diff `383d37c..d0a832c` was checked before re-dispatch: it touches only
`docs/production-promotion-app-tolerance-contract.md` and `scripts/post_batch_app_verification.py`.
**Zero changes to any migration file and zero changes to
`scripts/production_migration_guard.py`**, so the §6.1 dry-run evidence remains valid for the new
SHA. The ledger was re-read at that moment and was still 373 / `20260810140000` / B2 unapplied.

### 6.3 Second apply dispatch — ALL GUARDS GREEN, AWAITING HUMAN APPROVAL
Run <https://github.com/u2giants/shared-db/actions/runs/31450243224> (SHA `d0a832c`).

- `SQL migration guards` — success
- `Production apply review (advisory model verdict + hard guards)` — **success**
  - `PREFLIGHT OK: 3 migrations, no missing non-deferrable dependency.`
    (Per contract §7.5 a green preflight is not an approval; it is recorded, not relied on.)
- `Production apply (requires Albert's approval)` — **`waiting`** on `environment: production`.
  `pending_deployments` reports the sole eligible reviewer is `u2giants`.

**Albert approved this run, but by the time he clicked, `main` had moved from `d0a832c` to
`0365f44` (five PRs merged in between). `Verify exact main commit` refused. The run FAILED SAFELY:
production was NOT written.** Re-confirmed directly afterwards — ledger still 373 rows, max
`20260810140000`, and the live tree body still 13,802 chars with `division_name` absent.

### 6.4 Re-stage at `0365f44` — full re-verification from scratch

A merge freeze was put in force (PRs #746, #751, #752, #753 held unmerged) so `main` would stop
moving. Work was done in a dedicated worktree cut from a freshly fetched `origin/main`.

Every precondition in §2–§5 above was **re-measured live against production** at the new SHA, and
every number was identical: ledger 373 / `20260810140000`; tree body 13,802 chars with `pi.` = 2,
`li.` = 1, `division_name` absent; `plm."divisionCode"` present with all six columns;
`pim.product` 17,909 rows / 17,909 distinct task ids / 0 untrimmed / 0 null `external_source` /
17,859 `directus_product` + 50 `clickup`; all three target objects still absent.

**Re-staged dry run — GREEN.** Run <https://github.com/u2giants/shared-db/actions/runs/31496831439>
(SHA `0365f44`):

```
BOUNDED OK: 376 migration files on disk, all within remote-ledger | allowlist (3 allowlisted).
Would push these migrations:
 • 20260728171500_db_data_admin_tree_plm_division_names.sql
 • 20260728174500_clickup_incremental_task_import_reissue.sql
 • 20260728181500_clickup_incremental_task_import_fixes.sql
```

**Re-staged apply dispatch.** Run <https://github.com/u2giants/shared-db/actions/runs/31496978455>
(SHA `0365f441b693a445d15049e21c1530fa5ba867c2`):

- `SQL migration guards` — success
- `Production apply review (advisory model verdict + hard guards)` — success
- `Production apply (requires Albert's approval)` — `waiting`

`origin/main` was re-derived immediately before the apply dispatch and was still `0365f44`, so the
`Verify exact main commit` step will pass provided the freeze holds until he clicks.

### 6.5 Atomicity note

`supabase db push` is atomic **per file**, not per batch (AGENTS.md §5.1-A,
`docs/verification/issue-611-db-push-atomicity-20260810.md`). A mid-batch failure would leave the
earlier files applied *and* ledgered. The resulting position is recorded in §9 whatever it turns
out to be.

## 7. Finding — the #709 User-Agent path did NOT execute

The brief expected this run to be the first real production exercise of the User-Agent fix in
`scripts/production_apply_model_review.py` (commit 6578935). **It did not execute.** The advisory
model review step reported:

> **NOT RUN** — `ANTHROPIC_API_KEY` is not configured on this repository, so no model review was
> performed.

The step logged `ANTHROPIC_API_KEY:` empty and exited without calling the Anthropic API, so no
HTTP request was made and the User-Agent header was never sent. **The #709 fix therefore remains
unproven against production.**

This is a correct, loud failure rather than a silent skip — the script states NOT RUN in the job
summary and tells the approver to rely on the deterministic guards instead. But two things follow:

1. The advisory model review is currently a permanent no-op on every production apply. It is
   `continue-on-error: true`, so it will never fail a run; the only signal is that sentence in the
   summary. Anyone assuming a silent review job means "the model found nothing" would be wrong.
2. #709 cannot be closed on the strength of this run.

## 8. Post-apply verification plan (to be filled in after approval)

Not run yet. When the write lands, verification will be by object and behaviour, not by the ledger,
and each item will be labelled harness-derived vs directly inspected:

- `pg_get_functiondef` on `api.db_data_admin_licensor_property_tree` — assert `division_name` and
  `division_external_code` now appear, and that the two `pi.`/one `li.` blocks each gained the
  subqueries. Then call the RPC and assert a `plm_context` entry carries a real division name.
- `to_regprocedure` on `pim.sync_clickup_tasks(jsonb,text)` and `public.sync_clickup_tasks(jsonb,text)`;
  `pg_get_functiondef` to confirm the **`181500`** body won (resolve-by `btrim(clickup_task_id)`
  first, `fetch_started_at` watermark, `watermark_advanced` flag) and not the `174500` body.
- `to_regclass('pim.pim_product_clickup_task_id_uidx')` plus `pg_get_indexdef` — unique, on
  `btrim(clickup_task_id)`, partial on non-null/non-blank.
- `to_regclass('pim.pim_product_clickup_list_updated_idx')`.
- `information_schema.columns` — all 11 new `clickup_*` columns on `pim.product`.
- `pg_proc.proacl` — `service_role` holds EXECUTE on both `sync_clickup_tasks`; `public` does not.
- `ingest.sync_run` — assert **no** new backfill or trim-repair row was written (both were
  predicted no-ops in §5; a row appearing would mean production differed from the dry-run reading).
- `pim.product` row count still 17,909 and `external_source` split still 17,859/50 — the migrations
  must not re-key or duplicate a single product row.
