# Step 3 closeout — rebuild and projection churn

**Plan / issue:** `plan_database_efficiency_and_api_security.md` Step 3 / #2326
**Recorded:** 2026-09-10T14:09:13Z
**Scope of this closeout:** repository evidence reconciliation only. It performs no database interaction and contains no row values, credentials, or private source material.

## Result

Step 3 is complete. The original cross-repository call graph established every named caller, schedule, concurrency path, input size, read-side plan, and timestamped cost. The initially open changed-row and write-side-plan questions were then resolved through the separately governed, previewed, production-authorized changes that those measurements justified. This closeout makes that durable evidence chain explicit; it does not re-run production writes or invent a new structural change.

The former Step 3 blockers #2213, #2214, and #2215 are closed. Their outcomes are retained below as evidence, not reopened by this programme.

## Baseline call graph

The authoritative first-stage artifact is [the 2026-09-04 call graph](../../database-efficiency-callers/2026-09-04T2130Z/call-graph.md), with its companion [machine-readable caller inventory](../../database-efficiency-callers/2026-09-04T2130Z/callers.json) and [definition retrieval record](../../database-efficiency-callers/2026-09-04T2130Z/function-definitions.sql).

It established the following without a production write:

- The reported 181-second `asset_effective_tags` population was a one-off backfill, not recurring work. The recurring cost was trigger churn.
- `refresh_style_group_counts_batch` rewrote unchanged rows, which re-fired the DAM search projection.
- `clear_style_group_batch` was keyset/index bounded; its high time was a downstream trigger cascade, not a missing scan index.
- `refresh_style_guide_matviews` had a fifteen-minute cron caller, no observed overlap, and a non-concurrent folders refresh because the then-current view lacked a qualifying unique index.
- The five target operations had named callers, schedules or triggers, concurrency descriptions, input bounds, and timestamped production-read-only cost observations. The only named limits were changed-row counts and write-side plans, which the read-only role correctly refused to execute.

## Resolution of the named unknowns

| Operation | What the original call graph left open | Subsequent governed resolution | Durable evidence |
|---|---|---|---|
| Effective-tag projection | Distinguish true changes from delete/reinsert churn and prove a safe no-op path. | The evidence proved 6,762,623 delete/insert pairs after the one-off backfill with no net content change. PR #2399 changed only the assets branch to compare derived and stored sets, leaving an unchanged set unwritten. | [#2213 production measurement](https://github.com/u2giants/shared-db/issues/2213#issuecomment-5552480273); PR #2399 merge `22b6c2341169819491af8a18961b13bc4afb7b09`; `20260905143005_effective_tag_sync_set_comparison.sql` and its contract tests. |
| Style-group counts | Measure whether the nightly all-group call rewrote unchanged values. | The entry evidence found 10,864 of 10,868 groups already correct. PR #2397 added a complete null-safe change predicate, so unchanged groups are not updated and therefore do not re-fire the search projection. | [#2214 production measurement](https://github.com/u2giants/shared-db/issues/2214#issuecomment-5552465955); PR #2397 merge `da2335d6603a41e36119113b128a5a3323a134cd`; `20260905142725_style_group_counts_change_predicate.sql` and its contract tests. |
| Style-group rebuild | Identify a remaining write-side cause without assuming a scan problem. | A separately measured follow-on found whole-table re-stamping of already-correct assignments and a non-convergent ungroup case. PR #2423 guarded unchanged assignments and upserts and added the bounded ungroup path. | `20260906035323_style_group_rebuild_guard_and_ungroup.sql` and its contract tests; PR #2423 merge `cb085f37a68296ebe04ea25e5ee743d2c0a21f2e`. |
| Style-guide matviews | Prove the unique-index/freshness conditions before changing a blocking refresh. | The qualifying folders index and concurrent refresh were delivered by PR #2339. Read-only verification recorded zero aggregate drift; no further structural change was justified. The residual cadence is application scheduling and was retained because it was draining the bounded search-document backlog. | [#2215 closeout](https://github.com/u2giants/shared-db/issues/2215#issuecomment-5552470381); PR #2339 merge `9e83aa0460517613b44fd4bdf553b55f299b19ae`; `20260905104802_popsg_bounded_reconcile_pdf_text_and_search.sql` and its contract tests. |

## What this does and does not authorize

- The evidence satisfies Step 3. It supports the already-landed, narrowly scoped changes above and preserves their separate preview, review, promotion, and contract-test records.
- It does **not** make a further projection, scheduling, index, or policy change automatic. Step 4 remains the application-owned work gate; Steps 5–8 keep their own issue, preview, review, and production-authorization requirements.
- Issue #2662 remains open and unscheduled. Its documented cross-application read path is unrelated to this Step 3 closeout and is not remediated here.

## Acceptance check

Every Step 3 operation now has a named caller/trigger or schedule, input context, changed-versus-unchanged evidence, query-plan or explicit permission-boundary record, concurrency pattern, and timestamped cost source. Where a later change was justified, the precise migration, contract tests, PR, and merge commit are recorded above. No unknown was silently converted into a proposed fix.
