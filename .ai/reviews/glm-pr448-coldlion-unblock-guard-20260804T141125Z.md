# GLM review — pr448-coldlion-unblock-guard

| field | value |
|---|---|
| model | zai-coding-plan/glm-5.2 |
| opencode | 1.18.12 (pinned) |
| session | pr448-coldlion-unblock-guard |
| session id | `ses_032e5652affeYXHK7Wakr7XmRp` |
| repository | /worksp/shared-db/.claude/worktrees/coordinator-handoff-intake-7e55cb |
| branch | claude/coordinator-handoff-intake-7e55cb |
| caller | claude |
| requested | 2026-08-04T14:11:25Z |
| tokens | `{"input":31184,"output":1286,"reasoning":9350,"cache":{"read":0,"write":0}}` |

---

## Q1 — Does the preflight do what it claims for the 14→18 ordering?

Yes, for the *specific* failure it targets. The ordering logic is sound: `available` is seeded from remote-applied files, then each allowlisted version adds its `created_objects` before its own `hard_references` are checked. Because `parse_allowlist` enforces ascending order, "earlier in the batch" = "already in `available`". So 20260727221500's `references plm.taxonomy_sync_alert(id)` (matched by the `references` regex) is flagged when 20260726180000 is absent (BATCH_14) and cleared when it's present (BATCH_18). The mechanism is correct; the coverage is not (Q2/Q3).

## Q2 — What is wrong or missing

**A. Bundle integrity is NOT enforced — the central claim is only a comment.** `UNBLOCKED_20260804` is documentary; nothing in `parse_allowlist`, `validate_candidates`, or `preflight_batch` requires the four to travel together. Passing `--allowlist 20260726030000` alone parses fine (no longer HARD_BLOCKED), and since 30000 is the dependency *root* of phase 4 (31000/32000 depend on it, not vice versa), a lone `{30000}` or `{30000,31000,32000}` subset would pass `preflight_batch` too. The "NEVER unblock … on its own" warning is prose, not code, and ships a half-composable unit to a forward-only lane.

**B. Nameless `CREATE INDEX` is a silent false negative.** The index regex requires an explicit name token `[^\s(]+\s+on`. `create index on plm.foo (col)` (valid, common) parses as index-name=`on`, then demands a second `on` → no match. An index on a not-yet-created table passes the preflight and fails 42P01 in prod.

**C. View / materialized-view SELECT dependencies are not scanned at all.** REFERENCE_RES covers only FK, trigger target, alter table, index target. But `CREATE VIEW` resolves its query at DDL time — `create view api.x as select * from plm.missing` aborts 42P01, and the scanner never sees `from plm.missing`. The whole-batch claim ("reject … 42P01") is overbroad.

**D. Trigger regex has a 400-char cap.** `[\s\S]{0,400}?\bon\s+` misses triggers with a long `WHEN (...)` clause → false negative.

**E. Dollar-quote stripping runs BEFORE comment stripping.** `strip_sql` does DOLLAR→BLOCK→LINE. A `$$` appearing inside a `-- comment` or `/* */` is consumed by `DOLLAR_QUOTE_RE` first and can swallow intervening SQL (false rejection) or mis-terminate a real body. Needs a single-pass lexer.

**F. Other DDL-time deps not modeled:** `create domain`, `create rule`, `create foreign table`, `partition of`, `create cast/operator`; CHECK constraints calling `plm.fn(...)`; `collate`; `default nextval('seq'::regclass)`/serial; `create extension`-provided types. Each can 42P01 at apply time and is invisible to the scanner.

**G. Discrepancy between docstring and test.** The `preflight_batch` docstring says 20260728134500 "fails … on `create trigger … on plm.taxonomy_sync_alert`", but `test_real_14_file_batch_is_rejected_at_file_3_and_file_10` asserts the message contains `plm.taxonomy_parallel_observation`. One of them names the wrong table; verify against the real migration text.

**H. Over-flag (safe direction):** `alter table if exists` is treated as a hard reference even though `IF EXISTS` makes it survivable — noisy but not dangerous.

## Q3 — What fails in production but passes here

Anything in Q2 B–F: a batch containing `create index on plm.later(...)`, `create view … select from plm.later`, `check (plm.fn(x))`, a long-WHEN trigger, or a regclass default — all resolve at DDL time, all 42P01, all pass this preflight. Plus the partial-bundle case: `{30000,31000,32000}` ships clean, then a future batch carrying 27221500 still needs 180000, which is the exact "half-composable batch to a forward-only lane" the comment warns about and nothing prevents.

## Q4 — Tests that cannot fail (would still pass if production code were broken)

- **`test_local_migration_versions_are_unique`** asserts only `len(...) > 300`. It does *not* exercise duplicate-version rejection; if `local_migrations`'s dedup broke, it still passes as long as the live repo happens to contain no duplicate. The comment claims it tests the silent-skip hazard; it doesn't.
- **`test_the_four_coldlion_versions_are_unblocked`** asserts set equality and that the four parse together. It never asserts a *subset* is rejected, so the bundle property (Q2 A) has no failing test. Inverting the enforcement would leave this green.
- **`test_real_18_file_batch_passes`** is one-directional: it fails only on false *rejection*. If the scanner drifted toward false *acceptance* (the dangerous direction — Q3), this test stays green. The positive direction has no assert.

The genuinely failing-capable tests are `test_real_14_file_batch_is_rejected…` (assertRaises + message substrings), `test_creator_later_in_the_batch_is_rejected`, the two `if not exists`/`drop trigger` negatives, and the `production_ledger_versions()` 359-row self-check.
