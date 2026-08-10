All work is committed on `claude/clickup-incremental-import-20260728` (commit `2f57c27`, author `Albert Hazan <u2giants@users.noreply.github.com>`, not pushed). Here is the report.

## Summary

Fixed all five confirmed defects in the ClickUp incremental importer and added SQL contract tests that actually execute the importer function (the existing 30 JS tests never did). Committed on the branch. No push, no PR.

## Per-defect changes

**Defect 1 — watermark pre-fetch (CRITICAL)**
- `tools/sync-clickup-tasks.mjs:571` captures `fetchStartedAt = new Date().toISOString()` **before** the first ClickUp API call; passed into the snapshot at `:617`/`:229` (`fetch_started_at`).
- Migration `:273` reads `fetch_started_at` from the snapshot; `:471-473` computes the returned watermark as `v_fetch_started - interval '60 second'` on a clean run (60s overlap because `date_updated_gt` is strict and the upsert is idempotent). `started_at` is kept only for run accounting.

**Defect 2 — partial failure non-advance + escape hatch (CRITICAL)**
- Migration `:471`: when `rows_failed > 0`, `v_watermark_out := v_watermark_in` (do **not** advance → failed rows retried next run; null input → full pull, which also retries).
- Status stays `succeeded` (`ingest.sync_status` has no `partial` value) but metadata flags it unmistakably: `:489-490` `watermark_advanced=false`, `outcome='succeeded_with_failures'`, `partial_failure=true`.
- Escape hatch: migration `:279-286` reads `skip_task_ids`; `:323` skips them before the upsert (counted `rows_skipped`, never `rows_failed`) so a permanently-bad task can't wedge the watermark. Wired from `CLICKUP_SKIP_TASK_IDS` (`tools/sync-clickup-tasks.mjs:87,109`).

**Defect 3 — backfill trim + record claimed skips (HIGH)**
- Migration `:127` `external_id = btrim(p.clickup_task_id)`; ambiguity detected on the **trimmed** id (`:113` `<> all (v_ambiguous)`). Note: I initially wrote `<> any`, which silently claims nothing when there are no ambiguous ids — the contract test caught it; fixed to `<> all`.
- `:155` records `already_claimed_clickup_task_ids` (ids skipped because another row owns `(clickup, id)`) in addition to the ambiguous list.

**Defect 4 — don't rewrite unchanged rows (HIGH)**
- Migration `:432-433` gates the upsert with `where pim.product.metadata ->> 'clickup_source_hash' is distinct from excluded.metadata ->> 'clickup_source_hash'`. Unchanged rows skip the write entirely (so `pim.product`'s `set_updated_at` BEFORE-UPDATE trigger never fires either); `rows_unchanged` stays accurate. *(Verified there IS a `set_updated_at` trigger on `pim.product`; the skip is what protects `updated_at` in production.)*

**Defect 5 — runner exit codes (MEDIUM)**
- `tools/sync-clickup-tasks.mjs:58-59` defines `EXIT_LOCKED=2`, `EXIT_PARTIAL_FAILURE=1`. `:638` parses the result (`parseImportResult`, reusing the Phase 6 CLI parser for the Go `map[…]` form + psql fallback); `:643`/`:652` exit non-zero with distinct messages for locked vs. partial-failure. Dry-run path unchanged (exits 0). `buildImportSql` now emits a single `to_jsonb` cell so `locked`/`rows_failed` parse reliably across CLI output shapes.

New file `supabase/tests/clickup_task_import_contracts.sql` — 5 rollback-safe cases (per-case transactions; dblink-guarded case 5).

## Verification — real output

**Gate 1 — `node --test tools/sync-clickup-tasks.test.mjs`:** `tests 40 / pass 40 / fail 0`.

**Gate 2 — `scripts/check-sql.sh`:** `Static checks passed.` (exit 0).

**Gate 3 — `supabase db push --dry-run`:** ran clean (exit 0, `Finished supabase db push`) against a throwaway local PG via `--db-url` with `PGSSLMODE=disable` (the CLI forces TLS otherwise). Migration is additive by inspection: only `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `GRANT/REVOKE`, `COMMENT` — **no DROP/RENAME/ALTER of existing objects** (the only `drop` match was a comment). My migration appears in the plan and parses.

**Gate 4 — local Docker Postgres 16 + contract tests** (fresh DB: auth/role shim → 4 foundation migrations → my migration → contract file):
```
NOTICE:  C1 PASS: curated fields + non-clickup metadata survive an update upsert
NOTICE:  C2 PASS: legacy whitespace id matched+updated, no duplicate
NOTICE:  C3 PASS: failed row did not advance the watermark
NOTICE:  C4 PASS: unchanged row did not bump updated_at (changed row did)
NOTICE:  C5 PASS: advisory-lock path returns locked=true with no side effects
NOTICE:  clickup_task_import_contracts: all cases evaluated
exit=0
```
Object-existence checks (AGENTS: confirm objects, not just ledger) all passed: both functions, the index `pim_product_clickup_list_updated_idx`, the 11 new columns, the backfill `sync_run` row with the `already_claimed_clickup_task_ids` key, and the ON-CONFLICT WHERE present in the function body.

## ⚠️ Critical finding I could not fix (needs owner action on `main`)

A **timestamp collision exists on `main`** (AGENTS §5 hazard — a duplicate timestamp silently skips one migration in production):
- `20260728160000_clickup_incremental_task_import.sql` was swept onto `main` by PR #305 (`8a7197f`, another session) — with the **original buggy** content.
- `20260728160000_popdam_user_tables_foreign_keys.sql` (`0b8425b`, another session) shares the same timestamp.

Both are other sessions' commits on `main`, which I'm forbidden to rewrite. I deliberately did **not** re-timestamp my migration: because the stray copy already lives on `main`, re-timestamping my branch would produce a *worse* duplicate-on-merge (buggy backfill from the stray + my fixed copy). Keeping `20260728160000` means my PR's merge replaces the stray with my fixed version (good for the importer), but the `clickup`-vs-`popdam` collision on `main` remains and must be resolved there (re-timestamp `popdam`, or remove the stray `clickup` file from `main`) — otherwise at the next promote one of them is silently skipped. **My branch itself is clean** (`uniq -d` empty; only the one `clickup` file, no `popdam`).

## What I could not do (honest)

- **Gate 3 preview-diff (AGENTS §5.2 style)** — the constraint forbids touching preview/prod, and the local `supabase start` stack fails to full-reset on a pre-existing *unrelated* migration (`20260702220336_ai_sentinel_stats_exact_match.sql` → `relation "assets" does not exist`). I substituted a `--dry-run` against a fresh local PG (clean) + additive-by-inspection. The migration was proven to apply cleanly in sequence against PG16 (gate 4).
- **Full 367-migration local apply** — blocked by the same unrelated `assets` ordering failure, so I applied my migration's actual dependency closure (foundation + app_core + domain_tables + api_rls + mine) with a minimal `auth`/`roles` shim. This is the faithful set for the importer + contract tests.
- Did not run against preview/production (forbidden), did not push/open/merge a PR (forbidden), did not touch the `main` collision (not my commits).

One implementation note worth surfacing: there is a pre-existing `BEFORE UPDATE set_updated_at()` trigger on `pim.product` (from `20260621151155`). Defect 4 relies on the ON-CONFLICT WHERE *skipping the update entirely* so that trigger never fires on unchanged rows — which gate-4 case C4 proves. If that trigger were ever changed to fire on a no-op write, defect 4 would need a different mechanism.
