---
issue: 1184
status: OPEN
owner: claude/plan-coldlion-landing-phases-2-6
---

# OPEN — ColdLion landing phases 2-6: plan written, no code started

**Opened:** 2026-08-19 · **Machine:** al8960ofc · **Agent:** Claude (Opus 5)
**Repo:** `u2giants/shared-db` · **Branch:** `plan-coldlion-landing-phases-2-6`

## 1. What this workstream is

Build the ColdLion landing tables — phases 2 to 6 of issue
[#1184](https://github.com/u2giants/shared-db/issues/1184). Phase 1 (the spine) is already merged.

**The plan is the deliverable of this session and it is complete:**
[`../docs/plan_coldlion-landing-phases-2-6.md`](../docs/plan_coldlion-landing-phases-2-6.md).
Read its STATUS table first. Do not re-plan or re-derive its numbers.

## 2. Why it exists

Albert asked which product categories each division sells. Answering it needs an item's division.
Our stored item copy has the division column empty on all 17,703 rows, because the loader was
pointed at DesignFlow rather than ColdLion. That exposed a wider problem: the ingest tables are not
shaped to receive ColdLion's data at all — wrong identity key, wrong grain on production orders, and
sales history missing entirely.

## 3. State right now

| Thing | State |
|---|---|
| `docs/plan_coldlion-landing-phases-2-6.md` | Written, committed on the branch. Not merged yet |
| `docs/coldlion-field-decisions-20260819.csv` | Albert's per-field ingest/ignore decisions, sanitised of sample values |
| Two owner rulings (D1 all-14 slots, D3 division letter code) | Committed on the branch |
| Any migration or loader code | **None. Nothing built.** |

**Nothing is deployed. No database object was created or changed by this session.** Every database
call was read-only.

## 4. Decisions Albert made this session (all locked, all in §8 of the plan)

- Land all 14 merch-group slots even though 11-14 measure 0% populated.
- Drop merch-group codes and their `Desc` twins from both history feeds — they are item attributes.
  Verified identical on 519 of 519 order lines.
- Division identity is the letter code (`CW001`), never a number.
- Only fields marked `ingest` get a typed column.
- **No raw JSON archive.** He weighed this against the planner's recommendation and rejected it on
  query-performance grounds. Accepted consequence, stated to him explicitly: an `ignore` decision on
  the history feeds is effectively permanent.
- `dimCode` on itemDetails: ignore.

## 5. What did NOT work — do not repeat these

- **`gh pr merge` in a retry loop.** `main` has 9 required checks and other sessions merge often, so
  the branch kept going stale and the loop burned ~35 minutes. Use
  `gh api -X PUT repos/u2giants/shared-db/pulls/<n>/update-branch`, then poll `mergeStateStatus`
  until `CLEAN`. Do not `git checkout` to update the branch — the working tree may belong to another
  session, and it did change underneath this one mid-task.
- **Per-item ColdLion lookups** to compare order fields against the item master. Many returned no
  rows and it wasted calls. Pull the full item master per division (`size=2000`) and join locally.
- **Reading stored payloads to decide what a feed contains.** That is how this session initially and
  wrongly concluded division was absent from the item feed. Albert corrected it. Read
  `GET /EhpApi/v2/api-docs` — it also disagreed with our own docs about writable endpoints.
- **Trusting `pg_stat_user_tables.n_live_tup` for row counts.** It reported 0 for tables holding
  17,703 rows. Use `count(*)`.

## 6. Open items for the next session

1. Start at **step 1** of the plan: supersede the design doc for the 2026-08-19 rulings. It is
   documentation only and unblocks steps 2-6, which are independent of each other.
2. **Grok review of the plan is in flight** as of this writing. Check for its findings before
   building, and fold anything real into the plan first.
3. This branch is not merged. Merge it before or alongside step 1.
4. Unresolved with ColdLion: Albert wants write-back on vendor FEMA/NBC expiry dates, but ColdLion
   exposes no vendor write endpoint. Asking them is plausible — they added the 7-day cap and
   `prodLineSeq` on our request. Not blocking.

## 7. Where the evidence lives

All measurements are in §6 of the plan with the method to re-derive them. The sample-bearing CSVs
Albert marked up are **not in the repo** — this repo is public and they carry licensor names, item
descriptions, vendor emails and customer names. They are in Albert's Dropbox at `ai/`.

## 8. Delete this file when

Steps 1-7 of the plan are done and its STATUS table shows every row complete with an artifact. If
the plan is abandoned instead, say so here with the reason before deleting.
