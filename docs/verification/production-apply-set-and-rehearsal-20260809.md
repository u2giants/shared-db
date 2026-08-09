# A2 — The rebuilt production apply set, and the first rehearsal of the bounded lane

**Plan item:** `plan_orchestrator-workflow-gaps.md` § A2 (rebuilt; the original 11-only allowlist was wrong)
**Measured:** 2026-08-09, by a dispatched sub-agent of orchestrator session `5e1ab3af` (marker issue #601).
**Input:** `docs/verification/orphan-migrations-classification-20260809.md` (A1, PR #604) — **verified, not inherited.**
**Nothing was written to any database.** Every production statement below is a `select`. The
rehearsal used the existing dry-run job, whose first step refuses `mode: apply`.

---

## 0. Headline

Three things, in order of how much they matter.

1. **The apply set is 50 migrations, not 11 and not 44.** 49 APPLY + 1 RETIRE.
2. **`20260729120000` must be RETIRED, and the reason is stronger than "superseded":
   applying it would REGRESS a security control that is live on production today.**
   It sorts *below* `20260729180000`, which is already in the ledger and will therefore
   never re-run to repair the damage. This is the one place where pure version order is
   actively wrong, and it is the single most valuable finding here.
3. **The rehearsal could not reach the Supabase CLI. It failed on a defect in
   `scripts/production_migration_guard.py` — a parsing fault, not a migration fault.**
   The defect is fixed in this PR with 8 regression tests. **A second, structural blocker
   sits behind it** (§6) and is NOT fixed here.

---

## 1. Target confirmed before any measurement

`AGENTS.md` §12 standing fact 6: the Supabase MCP takes no project parameter, so the target
is confirmed first, every time.

```
mcp__supabase__get_project_url  ->  https://qsllyeztdwjgirsysgai.supabase.co
```

**Production ref: `qsllyeztdwjgirsysgai`.** Preview (`rjyboqwcdzcocqgmsyel`) was not touched.

## 2. Counts, re-derived from scratch

The plan and A1 both say counts go stale within the hour and no document wins by date, so
nothing below is quoted from either.

| Measure | A1 (2026-08-09, earlier) | This pass | Note |
|---|---|---|---|
| Production ledger rows | 361 | **361** | unchanged |
| Ledger head | `20260802194100` | **`20260802194100`** | unchanged — production last received a migration **2026-08-02** |
| Migration files on `main` | 405 | **411** | **+6**: PR #606 merged `20260809170000`…`20260809170500` |
| Missing below the head ("orphans") | 33 | **33** | unchanged |
| Missing above the head ("pending") | 11 | **17** | 11 + the 6 new |
| **Total missing** | 44 | **50** | |
| Ledger rows with no file on `main` | 0 | **0** | no phantom ledger entries |

`origin/main` tip at measurement: `77c15acf8840f275c56c2a2199b860f1776cafe7`.

Re-derive:

```sql
select count(*), min(version), max(version) from supabase_migrations.schema_migrations;
-- 361 | 20260220125350 | 20260802194100
select string_agg(version, E'\n' order by version) from supabase_migrations.schema_migrations;
```

```bash
git ls-tree -r --name-only origin/main supabase/migrations | sed 's#.*/##' | cut -c1-14 | sort
# 411 versions; set-difference against the ledger gives the 50 below.
```

**The plan's §A2 allowlist of 11 is wrong twice over:** it omits the 33 that several of the
11 depend on, *and* it predates the 6 migrations merged today.

## 3. The ordered apply set — 50 migrations

Order is **version order**, and version order is correct for all 49 APPLY rows (proved in
§5). The one row where version order would do damage is retired rather than reordered,
because reordering cannot fix it (§4.1).

| # | Version | vs head | Action | File |
|---|---|---|---|---|
| 1 | `20260724060000` | below | APPLY | `coldlion_licensor_property_phase2a_mirror_importer.sql` |
| 2 | `20260724061000` | below | APPLY | `coldlion_licensor_property_phase2a_guard_corrections.sql` |
| 3 | `20260726030000` | below | APPLY | `coldlion_licensor_property_phase4_link_approved.sql` |
| 4 | `20260726031000` | below | APPLY | `coldlion_licensor_property_phase4_null_shape_guard.sql` |
| 5 | `20260726032000` | below | APPLY | `coldlion_licensor_property_phase4_browser_execute_revoke.sql` |
| 6 | `20260726180000` | below | APPLY | `coldlion_licensor_property_phase6_parallel_run.sql` |
| 7 | `20260727221500` | below | APPLY | `coldlion_licensor_property_readiness_and_breaker.sql` |
| 8 | `20260727223000` | below | APPLY | `coldlion_breaker_blocked_attempt_logging_fix.sql` |
| 9 | `20260727224500` | below | APPLY | `coldlion_identity_verifier_reason_cast_fix.sql` |
| 10 | `20260727230000` | below | APPLY | `core_style_guide_axis.sql` |
| 11 | `20260728134500` | below | APPLY | `coldlion_breaker_autotrip_and_gap_closure.sql` |
| 12 | `20260728171500` | below | APPLY | `db_data_admin_tree_plm_division_names.sql` |
| 13 | `20260728174500` | below | APPLY | `clickup_incremental_task_import_reissue.sql` |
| 14 | `20260728181500` | below | APPLY | `clickup_incremental_task_import_fixes.sql` |
| **15** | **`20260729120000`** | below | **RETIRE** | `lock_down_public_security_definer_execute.sql` |
| 16 | `20260729230000` | below | APPLY | `coldlion_licensor_property_recurring_promotion.sql` |
| 17 | `20260729234500` | below | APPLY | `coldlion_recurring_promotion_collision_rule_fix.sql` |
| 18 | `20260729235500` | below | APPLY | `coldlion_recurring_promotion_ambiguous_column_fix.sql` |
| 19 | `20260730000500` | below | APPLY | `coldlion_recurring_promotion_absence_detection_fix.sql` |
| 20 | `20260731150000` | below | APPLY | `popsg_property_resolution_contracts.sql` |
| 21 | `20260731153000` | below | APPLY | `popsg_property_alias_redundancy_trigger_fix.sql` |
| 22 | `20260731163000` | below | APPLY | `coldlion_recurring_promotion_drop_dead_failure_recording.sql` |
| 23 | `20260731180000` | below | APPLY | `coldlion_recurring_promotion_serialization_lock.sql` |
| 24 | `20260731190000` | below | APPLY | `coldlion_promotion_crosscheck_provenance_coverage.sql` |
| 25 | `20260731200000` | below | APPLY | `coldlion_recurring_promotion_fanin_name_tiebreak.sql` |
| 26 | `20260731210000` | below | APPLY | `core_licensor_alias.sql` |
| 27 | `20260731220000` | below | APPLY | `licensor_alias_owner_approval_remaining_five.sql` |
| 28 | `20260802140000` | below | APPLY | `acknowledge_taxonomy_sync_alert_rpc.sql` |
| 29 | `20260802141000` | below | APPLY | `taxonomy_alert_ack_comment_correction.sql` |
| 30 | `20260802150000` | below | APPLY | `taxonomy_alert_actor_heuristic_word_anchors.sql` |
| 31 | `20260802160000` | below | APPLY | `taxonomy_alert_ack_effective_role_is_current_user.sql` |
| 32 | `20260802170000` | below | APPLY | `plm_import_preserve_curated_licensor_property_status.sql` |
| 33 | `20260802171000` | below | APPLY | `owner_ruling_friends_tv_frida_kahlo.sql` |
| 34 | `20260803150000` | above | APPLY | `itemdetail_coldlion_item_identity_and_upc_contract.sql` |
| 35 | `20260803200000` | above | APPLY | `temp_status_watch_snapshot_and_change_log.sql` |
| 36 | `20260803201000` | above | APPLY | `temp_status_watch_hardening.sql` |
| 37 | `20260804120000` | above | APPLY | `taxonomy_baseline_pins_table.sql` |
| 38 | `20260804120100` | above | APPLY | `taxonomy_breaker_environment_and_provenance.sql` |
| 39 | `20260807030000` | above | APPLY | `owner_ruling_coco_is_a_disney_license.sql` |
| 40 | `20260807170000` | above | APPLY | `opa_property_character_landing.sql` |
| 41 | `20260807170100` | above | APPLY | `opa_property_character_importer.sql` |
| 42 | `20260807180000` | above | APPLY | `opa_sync_reentrancy_fix.sql` |
| 43 | `20260807190000` | above | APPLY | `opa_security_and_view_corrections.sql` ← **security fix, not optional** |
| 44 | `20260807200000` | above | APPLY | `opa_comment_corrections.sql` |
| 45 | `20260809170000` | above | APPLY | `core_product_size_and_depth_foundation.sql` |
| 46 | `20260809170100` | above | APPLY | `core_product_depth_seed_from_designflow.sql` |
| 47 | `20260809170200` | above | APPLY | `core_product_size_seed_from_legacy_mg04.sql` |
| 48 | `20260809170300` | above | APPLY | `coldlion_product_size_guarded_importer.sql` |
| 49 | `20260809170400` | above | APPLY | `api_product_size_and_depth_pickers.sql` |
| 50 | `20260809170500` | above | APPLY | `db_data_admin_product_depth_mutations.sql` |

**The allowlist string** (49 entries, `20260729120000` removed) is exactly rows 1–14 and
16–50 above, comma-separated in this order.

## 4. The three delegated decisions

### 4.1 `20260729120000` — **RETIRE.** Confirmed, and for a bigger reason than A1 gave.

A1 recommended retire because the migration's end state is already on production, produced
by `20260729130000` and `20260729180000`. **That attribution is correct and I re-derived it
independently rather than inheriting it.** Live, read-only:

```sql
select md5(p.prosrc), length(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='lock_down_new_public_function_execute';
-- 735985606362e0321231dc77a5863ec4 | 750
```

Against the repo, CRLF-normalised (`scripts/verify/migration_body_md5.py`, added by A1 —
**the CRLF trap is real; an LF md5 mismatches every applied function**):

| File | body md5 | len |
|---|---|---|
| `20260729120000` | `fdbf72e787af65ac139c40b1fed4f6d2` | 722 |
| `20260729180000` | **`735985606362e0321231dc77a5863ec4`** | **750** |

The live body is `20260729180000`'s, byte for byte. And the `alter default privileges`
end state:

```sql
select array_to_string(d.defaclacl,' | ') from pg_default_acl d
 join pg_namespace n on n.oid=d.defaclnamespace where n.nspname='public' and d.defaclobjtype='f';
-- postgres=X/postgres | service_role=X/postgres      <- anon + authenticated already gone
```

`20260729130000` (in the ledger) carries that identical statement at its line 52.

**The new and decisive finding.** A1 stopped at "superseded". The stronger fact is that
applying `20260729120000` would **actively regress production security**:

| | `20260729120000` (would apply) | `20260729180000` (live now) |
|---|---|---|
| event-trigger `when tag in` | `('CREATE FUNCTION')` | `('CREATE FUNCTION', 'CREATE PROCEDURE')` |
| loop filter | `command_tag = 'CREATE FUNCTION'` | `command_tag in ('CREATE FUNCTION','CREATE PROCEDURE')` |
| revoke statement | `revoke execute on function` | `revoke execute on routine` |

Both statements are `create or replace` / `drop event trigger ... create event trigger`, so
they overwrite unconditionally. `20260729120000` sorts **below** `20260729180000`, which is
already in the ledger and therefore **will not re-run to repair it**. Applying it in version
order would permanently narrow the public-schema execute lockdown so that newly created
**procedures** are no longer locked down at all.

Note that A1's own supporting argument — "its revokes target `sync_clickup_tasks`, which does
not exist, so it would abort" — **does not survive the full batch.** `20260728174500` (row 13)
creates `pim./public.sync_clickup_tasks` earlier in the same run, so in this batch the file
would *succeed*, and cause the regression quietly. The abort argument holds only for an
11-only or lone promotion. **This is exactly the kind of conclusion that must not be inherited.**

*Systematic check that this is the only one of its kind.* For every one of the 50, I listed
the objects it creates or replaces and looked for an **already-applied ledger migration with a
higher version** that writes the same object:

```
20260729120000 -> public.lock_down_new_public_function_execute  also written by applied ['20260729180000']
total hits: 1
```

**Exactly one hit.** (Limit of the scan, stated honestly: it cannot see objects created inside
`do $$` blocks via dynamic `execute`. The two known such cases —
`20260728171500` → `api.db_data_admin_licensor_property_tree` and `20260802170000` →
`plm.import_master_data` — were checked by hand and are *forward* moves over lower-versioned
applied creators (`20260727154500`, `20260723140000`), so they are intended, not regressions.)

### 4.2 `20260724060000` and `20260724061000` — **APPLY.** A1 left these UNKNOWN.

The measurement A1 could not make is a judgement, so here is the judgement with its reasoning.

**What they contribute to the end state: exactly nothing.** `20260726030000` (row 3, in the
same batch) re-issues every single object, grant and comment:

| Object | 060000 / 061000 | `20260726030000` |
|---|---|---|
| `plm.sync_coldlion_licensors_properties(jsonb,text)` | create | **`drop function if exists`** (L674), re-created at `(jsonb,text,jsonb)` |
| `public.sync_coldlion_licensors_properties(jsonb,text)` | create + wrapper | **`drop function if exists`** (L673), re-created at `(jsonb,text,jsonb)` |
| `api.coldlion_licensor_property_run_list(integer)` | create + revoke + grant | `create or replace`, **same signature**, same revoke + grant (L1402–1421) |

So retiring them loses nothing, and applying them costs two function bodies that are dropped
seconds later in the same push.

**Decision: APPLY. Three reasons, worst-case first.**

1. **Retiring them would manufacture two brand-new permanent ledger orphans** — two holes
   below the head, in a ledger whose 33 existing holes are the entire reason this plan exists.
   Fixing an orphan problem by creating orphans is the wrong direction.
2. **There is no retire mechanism yet.** A3 has not been built. `20260729120000` *forces* one
   to be invented, because it must never be applied. These two do not: they can simply run.
   Inventing an exception for files that need none adds a mechanism with no requirement.
3. **Skipping is the `--include-all`-shaped decision, not applying.** A1 says this itself.
   "Everything in version order" needs no judgement; "everything except these two" is a
   curated subset that a future reader has to re-justify.

**And unlike `20260729120000`, there is no regression risk.** Nothing already applied to
production is overwritten by them; their replacement is *inside the same batch*, so the
intermediate state never outlives the run. The one transient effect is that
`public.sync_coldlion_licensors_properties(jsonb,text)` exists for the duration of a few
files, granted to `service_role` only — and the live event trigger
`lock_down_new_public_function_execute_trg` fires on its creation and revokes execute from
`public`/`anon` immediately.

`20260726030000`'s drops are `drop function if exists`, so the batch is correct whichever way
this is decided. **This is a preference for ledger fidelity, not a correctness requirement**,
and it should be recorded as such.

## 5. Dependency order vs version order — they agree, for all 49

Run against the live ledger with the repo's own whole-batch checker (the same code path
`prepare` uses), after the fix in §6.1:

```
PREFLIGHT OK: 49 migrations, no missing non-deferrable dependency.
```

The 50-entry variant (i.e. `20260729120000` kept) also passes, which is the point: **the
static checker cannot see the `20260729120000` problem at all**, because a regression is not a
missing dependency. §4.1 is the only thing standing between that file and production.

Two orderings the plan calls out are satisfied by plain version order and were re-checked:
`20260728174500` before `20260729120000`; `20260807180000` before `20260807190000`.

⚠️ The preflight is a **pre-filter that may REJECT and must never be read as APPROVAL** — the
script says so itself, and that framing is correct.

## 6. The rehearsal

**Run:** https://github.com/u2giants/shared-db/actions/runs/31327934569
`workflow_dispatch` · `target: production` · `mode: dry-run` · `commit_sha`
`77c15acf8840f275c56c2a2199b860f1776cafe7` · `confirmation: DRY-RUN 77c15ac…` ·
`production_allowlist` = the 49.

**Result: `validate` succeeded; `production-dry-run` FAILED at "Build bounded checkout".**
The gate — "the dry-run output lists exactly the allowlist and nothing else" — was **not
reached**, so it is neither passed nor failed. It is untested. Nothing was written.

What the run *does* prove, and it is not nothing:

- `Refuse production apply` behaved (skipped, `mode` was `dry-run`).
- `Check exact confirmation` and `Verify exact main commit` both passed.
- **`Capture production migration record` succeeded** — the production credentials, the
  `supabase login`, and the `supabase link` all work. That was previously unproven.
- `parse_allowlist` accepted the 49: no `HARD_BLOCKED` collision, correct order, and the
  AGENTS.md §6.8 four-version ColdLion bundle is present in full.

### 6.1 Blocker 1 — a PARSING fault, fixed in this PR

The prompt warned the verifier is coupled to the Supabase CLI's output wording and that such a
failure would *look* like a migration fault. **This failure is of that family but at a
different site**, and the distinction matters:

```
BLOCKED: whole-batch preflight failed; the batch cannot run end to end:
  20260728174500 references missing pim.sync_clickup_tasks (query target);
  created by 20260728181500 which is not applied and not earlier in the batch
```

**This is false. `20260728174500` creates `pim.sync_clickup_tasks` itself, at its own line
216.** The batch is correctly ordered; the scanner is wrong.

**Root cause.** `strip_sql` ran three independent regex passes, and stripped dollar-quoted
bodies *before* comments. `20260728174500` line 46 contains, inside a `--` comment:

```sql
-- `create index if not exists`, `create or replace function`, guarded `do $$` block)
```

Postgres never sees that `$$`. The regex did: it became the opening half of a pair, matched
the next genuine `$$` at line 235, and **deleted every statement in between** — including the
`create or replace function pim.sync_clickup_tasks` at line 216. `created_objects()` returned
an **empty set** for a file that creates three functions.

**Blast radius: 8 of 411 files.** The worst is `20260727154500`, which is **already applied**;
its 17 objects were invisible in the `available` set that every later file is judged against.

**Fix (this PR):** `strip_sql` is now a single left-to-right lexer using Postgres's own token
precedence — line comments, nestable block comments, single-quoted literals, then dollar
quotes. String literals are skipped over but **kept**, because `REFERENCE_RES` deliberately
matches `'plm.seq'::regclass` inside a literal. 8 regression tests added
(`scripts/test_production_migration_guard.py`), including the exact false rejection above and
the real migration file. Suite: **32 tests, all pass.** A false REJECT was the safe direction,
but it blocked the lane completely.

### 6.2 Blocker 2 — STRUCTURAL, not fixed here, and it needs an owner/orchestrator decision

⚠️ **Even with §6.1 fixed, this rehearsal cannot pass as the workflow is written today**, and
this should be stated plainly rather than discovered on the next attempt.

33 of the 49 sort **below** the ledger head. `supabase db push --dry-run` refuses out-of-order
files without `--include-all`, and the workflow's dry-run step does not pass it. This is
**already documented and already observed**:
`docs/coldlion-production-migration-manifest-20260731.md` §4.2 and §5 record run
**30660298837** (2026-07-31) failing at the push step for exactly this reason.

**Two corrections to the plan follow from that:**

- The plan's "**nobody has ever run it**" is **stale.** It has been run, and it failed
  structurally. That is a stronger and more useful statement.
- That manifest also argues — correctly, in my reading — that `--include-all` **inside the
  guard's bounded checkout** is safe *by construction*, because `prepare` has already deleted
  every file that is neither already-applied nor allowlisted, so in that directory "all"
  means exactly the allowlist, and `verify-dry-run` then demands an exact match anyway.

**I did not act on that.** Adding `--include-all` anywhere is outside this task's hard limits,
and it is a change to the production lane that belongs to A3 and to the owner. It is
**recommended and flagged, not decided.**

One caveat worth carrying into that decision: with an allowlist of 49, `prepare`'s
`keep = remote | allowlist` covers all 411 files, so the bounded checkout deletes **nothing**.
The "bounded" property here comes entirely from the fact that the allowlist happens to equal
every unapplied file — not from the pruning. That is fine, but it means the safety argument
for a bounded `--include-all` rests wholly on `verify-dry-run`'s exact-match check, and that
should be said out loud before anyone relies on it.

## 7. What was NOT done

- **No production apply, no DDL, no DML, no ledger insert, no `--include-all`, no `--create`.**
  Every production statement was a `select`. The only workflow run was `mode: dry-run`.
- **`supabase/migrations/` was not touched.** No migration was added, edited, retired or deleted.
  "RETIRE" here is a *recommendation about the allowlist*, not an action on a file.
- `AGENTS.md`, `HANDOFF.md`, `HANDOFF.d/**` and `plan_orchestrator-workflow-gaps.md` were not
  touched — the orchestrator owns the plan file and records drift itself.
- Preview (`rjyboqwcdzcocqgmsyel`) was not queried or modified.
- **No PR was merged.**
- **Blocker 2 (§6.2) was not fixed.** The lane still cannot complete a dry-run of this set.
- The A2 gate — "the dry-run output lists exactly the allowlist" — is **still unproven.**
