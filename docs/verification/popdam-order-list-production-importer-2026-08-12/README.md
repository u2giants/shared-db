# PopDAM OrderList production importer — gate design and row-count finding

Issue: [#852](https://github.com/u2giants/shared-db/issues/852). Claim: [#856].
Requirements source: `docs/verification/popdam-order-list-production-approval-2026-08-12/README.md`, "Required importer change before an approval can be exact".

This document contains counts, hashes, object names and command shapes only. No workbook rows, customer, vendor, SKU or order text, and no credentials.

## What this change did NOT do

- **No production import was run. Nothing was written to `qsllyeztdwjgirsysgai` by this work, in any mode, for any reason.** The `--production` path has never been executed.
- **No preview import was run either.** The existing preview evidence is unchanged.
- No database object was created, altered or dropped. No migration was authored.
- No SQL of any kind was executed.
- The licensed workbook was not present on this machine and was not needed. Every test is offline and synthetic; the checksum was stubbed only in the tests that exercise gates sitting *after* the checksum gate.

## The gates, in the order they fire

Everything that can refuse the run is checked **before the connection string is read**, so a wrong invocation never touches a credential.

| # | Gate | Function | Refusal proof |
|---:|---|---|---|
| 1 | `--preview` and `--production` mutually exclusive | argparse mutually-exclusive group | `test_preview_and_production_are_mutually_exclusive_in_argparse` |
| 2 | `--replace-source` refused with `--production` | `main()` | `test_replace_source_with_production_is_refused_by_the_cli` |
| 3 | Workbook SHA-256 pinned to the approved constant; `--expected-sha256` / `ORDER_LIST_SHA256` cannot relax it | `main()` | `test_expected_sha256_cannot_relax_production` |
| 4 | Full 40-character `--reviewed-commit` required | `assert_reviewed_commit` | `test_reviewed_commit_must_be_a_full_sha`, `test_production_without_reviewed_commit_is_refused` |
| 5 | `--expected-populated-rows` required, un-defaulted | `main()` | `test_expected_populated_rows_is_required_for_production`, `test_it_is_a_checked_input_not_a_hard_coded_number` |
| 6 | Workbook hash actually matches | `assert_source_checksum` | `test_wrong_workbook_hash_aborts_before_any_write` |
| 7 | Project ref proved from `supabase/.temp/project-ref` | `assert_write_target` | `test_wrong_target_aborts_the_whole_run_before_any_write` and three ref-value tests |
| 8 | Confirmation matches, bound to commit + hash + ref | `assert_production_confirmation` | five `ProductionConfirmationTests` cases |
| 9 | Project ref **re-proved** immediately before the transaction opens | `main()` | `test_a_drifted_target_never_reaches_the_first_batch_from_main` |
| 10 | Project ref **re-proved before every batch** | `apply_plan(target_guard=…)` | `test_drift_after_the_first_batch_aborts_and_writes_no_more`, `test_guard_runs_before_every_batch_not_just_the_first` |
| 11 | `allow_replace=False` — the second, independent replacement lock | `apply_plan` | `test_apply_plan_refuses_replace_when_allow_replace_is_false` |

`--replace-source` is impossible in production two independent ways: the CLI refuses the combination, and the production call site passes `allow_replace=False`, which raises inside `apply_plan` before the first batch opens. Deleting either lock still leaves the other.

Mid-run drift behaviour is deliberate: the guard runs **before** `begin_batch`, so batches already committed stay committed and no partial batch is left open. A later run resumes safely because every canonical row is addressed by its deterministic Google source ref.

## The exact production command — recorded, NOT run

Substitute the merge commit of this PR into both placeholders. The command is not executable as written and must not be run without the owner approving this exact wording.

```
python scripts/import-order-list-xlsx.py \
  --workbook /path/to/OrderList.xlsx \
  --production \
  --reviewed-commit <MERGE_COMMIT_SHA> \
  --expected-populated-rows 12354 \
  --batch-size 500 \
  --verify-idempotency \
  --confirm "I approve one production import of OrderList.xlsx SHA-256 68c9b03a0ec183e08b3a8f2344397e1bc4f61e73457849e7bf8c0cf7fb2409fe into Supabase project qsllyeztdwjgirsysgai using reviewed shared-db commit <MERGE_COMMIT_SHA>"
```

`PRODUCTION_DATABASE_URL` supplies the connection string; it is never passed on the command line, never logged, and never reaches the report. A `--dry-run` rehearsal (which writes nothing and needs no credential) must precede it and must reproduce the approved baseline counts.

## Balance checks: 10 becomes 11 in production

The preview path runs 10 checks. A production run supplying `--expected-populated-rows` runs those same 10 plus one more — "staged rows equal the operator-declared expected populated rows". The final approval package should say **11 of 11**, not 10 of 10.

## The five-row question: what is knowable, and what is not

The owner's ruling asks why the sheet shrank by five rows (12,328 → 12,323) and what those rows were. Here is the honest state of the record.

| Count | Workbook SHA-256 | Bytes | How the count was produced |
|---:|---|---:|---|
| 12,328 | `4958b4b7…fc6abbe4` | 10,677,903 | 2026-08-09 Phase 0 audit of the then-approved export |
| 12,323 | `b9b282dc…ffba30` (whole workbook) and `904b2cb9…0b2845` (`gid=0` tab) | 10,690,991 / 2,762,055 | 2026-08-11 browser exports of the live sheet, counted by a method that was not preserved |
| 12,354 | `68c9b03a…2409fe` (**the approved workbook**) | 10,679,199 | 2026-08-12 re-profile using this importer's own `is_populated` (any mapped cell non-empty) |

What is established:

1. The 12,328 → 12,323 move is a **real content change**. Two independently taken exports agreed at 12,323, and the same out-of-range date serials were still present, so it was the same sheet, edited by a human between 2026-08-09 and 2026-08-11.
2. The 12,323 → 12,354 move is **not only a re-definition**. The prevailing note in `docs/app-migration-notes/popdam-order-list.md` explains it as a narrower manual count versus the importer's populated definition — and that is part of the answer, since the same approved file yields 12,349 under a PO-Status definition. But the files also differ: 12,323 was measured on `b9b282dc…` / `904b2cb9…`, and the approved workbook is `68c9b03a…` at a different byte size. **The 12,323 figure was never measured on the approved workbook at all.** Any account that treats the gap as purely definitional is incomplete.
3. The 2026-08-09 and 2026-08-12 profiles also disagree on direct-only rows (8,412 vs 8,438), which is a further sign of genuine content movement rather than a pure counting-rule change.

What is **not** knowable, and why:

- **Which five rows changed cannot be determined from this repository.** The workbook is licensed business data and was correctly never committed. Neither the `4958b4b7…` export nor either `b9b282dc…` / `904b2cb9…` export was retained. There is no row-level artifact anywhere in the repo to diff.
- Only the Google Sheets revision history for spreadsheet `1i1da5J0qy5a0EvsO1CvfyQ6Xijn4678LG7TFqbwxwUk`, tab `Order` (gid `0`), can answer it. That is an owner action in a browser; an agent cannot and should not take it.

How the code handles this instead of guessing:

- `--expected-populated-rows` has **no default** and is **required** for production. The approver states the number; the importer asserts it as a balance check and fails the run if the workbook disagrees.
- The rendered reconciliation report prints all three counts, their hashes, and an explicit statement that the five-row question is unresolved. The report does not claim otherwise.

## Test evidence

`python -m unittest discover -s scripts/tests -p "test_import_order_list.py"` — **118 tests, OK**. One pre-existing test (`test_there_is_no_production_flag`) was replaced, because the behaviour it asserted is exactly what issue #852 directed to change; it was replaced with a mutual-exclusion test plus 29 new production-gate tests, every one of which proves a refusal happens before any write.
