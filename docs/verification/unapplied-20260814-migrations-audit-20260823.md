# The six 2026-08-14 migrations that were never applied anywhere — audit

**Date:** 2026-08-23 · **Scope:** investigation only. **Nothing was applied, promoted or pushed.**
**Evidence:** the SQL on `main`, the merged PRs and their issues, and read-only queries against the
**production** ledger and catalog (`supabase_migrations.schema_migrations`, `information_schema`,
`pg_get_viewdef`, row counts).

---

## Bottom line for the owner

**Nothing in production is broken today because of these six, with one real exception (item 1).**
Everything else is latent risk: work that was reviewed, approved and merged, then never switched on.
Five of the six change how the *next* licensor capture behaves, and no such capture has run since.

The one thing that is **wrong on screen today**: two Warner data feeds (`api.wb_property_character`,
`api.wb_property_reconciliation`) point at retired, now-empty tables. Anything asking the database
"which Warner characters belong to which property?" through those feeds gets **zero rows**, while
**4,158 real relationships** sit in the current Warner table right next to them. That is not caused
by the unapplied migration — it is caused by the cleanup being *half done*: the data was moved, the
old feeds were never repointed, and the migration that finishes the job is one of the six.

**A seventh migration is in the same state and was not on the list:**
`20260814224937_source_resolution_durable_home`. Item 6 below cannot run without it, and — as of
today's Universe A change — **neither of them can run at all any more**. See item 6.

**Also true, and normal:** two migrations from 2026-08-19 (`popdam_bulk_operation_revision_lease`,
`wildbrain_inventory_classification_and_finalize_extra_key_sweep`) are applied to preview and are
waiting for a production window. That is the process working. They are not part of this problem.

**Why nobody noticed.** The drift alarm (issue #949, opened 2026-08-14) is deliberately *throttled*:
while it is open, no further alarm issues are filed. It went red the same day these merged, was left
open, and every drift since has been silent. All six issues (#958, #964, #965, #969, #970, #999) were
closed the moment their PR merged, so nothing tracked "merged" separately from "switched on". A
separate session is repairing the checker; this report does not touch it.

---

## Ordered by urgency

### 1. Warner legacy cleanup — `20260814170749_wb_retire_legacy_capture_paths` (issue #958)

**What it does.** Finishes retiring the first-generation Warner (STARLABS) tables after the data was
moved to the normalized tables. It tightens the capture contract so a new Warner scrape can only
write to the current tables, deletes the eight retired empty tables and their old loader functions,
and drops the two API views that read them.

**Additive or destructive?** **Destructive, but only of empty objects.** Verified in production today:
all eight tables hold **0 rows**; the 4,158 property→character rows live in
`plm.wb_property_character_normalized`, exactly as the repinning policy expects. It drops tables
`plm.wb_asset`, `wb_style_guide`, `wb_character`, `wb_franchise_property`, `wb_property_character`,
`wb_asset_character`, `wb_asset_style_guide`, `wb_asset_franchise_property`; functions
`public.sync_wb_*` and `plm.sync_wb_*` (eight each), plus the two legacy capture functions; and views
`api.wb_property_character`, `api.wb_property_reconciliation`. No data rewrite.

**Broken today by its absence?** **Yes — this is the live one.** The two API views still read the
empty legacy table, so they answer "no Warner property/character relationships exist". Second, the
old loader functions are still callable and the capture guard still accepts retired target names, so
a stale script could land a fresh Warner scrape into tables nothing reads.

**Still wanted / safe now?** Yes, and nothing changed underneath it — its own safety check (refuse if
any legacy row or in-flight legacy capture exists) passes on today's production: zero legacy rows and
no legacy-target capture in flight. **But applying it as written removes those two API feeds without
a replacement**: the only remaining API view of Warner property↔character
(`api.wb_inferred_property_character`, added 2026-08-16) is *inferred from asset co-occurrence* and
explicitly is **not** the direct assertions.

**Recommendation: needs owner decision — then apply.** Decide first whether a replacement view over
`plm.wb_property_character_normalized` ships with it. If yes, apply as a pair. If no, apply as-is and
accept that the direct Warner assertions have no API feed. Either way, rehearse on preview first.

### 2. Source-capture inventory counts — `20260814233342_source_capture_inventory_latest_complete` (issue #969)

**What it does.** Adds the columns that separate "rows we have ever retained" from "rows in the
latest complete capture" on `api.source_capture_inventory` — the report used to answer "how much of
this licensor have we actually captured?"

**Superseded? Yes, completely.** Later migrations that *are* applied (Sega 08-19, Peanuts 08-19,
WildBrain 08-19 and 08-20) each rebuild the whole view including this body. Production already has
`latest_complete_row_count`, `count_basis`, `latest_complete_status`, `count_note` and
`carries_resolution`. The business benefit is already live.

**⚠️ Applying it now would cause damage.** It is a whole-view replacement carrying the 2026-08-14
body, which has no Sega, Peanuts or WildBrain branches. Running it today would silently downgrade
those licensors' coverage reporting to "retained only". Nothing warns you.

**Broken today by its absence?** No — the opposite.

**Recommendation: retire.** Do not apply. Record it as superseded (a documented no-op ledger entry,
in the style the repo already uses for pure-state migrations) so the drift checker stops counting it
and nobody promotes it by reflex with `--include-all`.

### 3–5. The three Paramount migrations — apply only as an ordered set

All three rewrite the same loader function, `plm.load_pmt_capture_chunk`, each starting from the
previous one's body. Production still runs the 2026-08-11 version, and **no later applied migration
has touched it**, so the chain is intact. Applying them out of order, or only some of them, would
silently drop the earlier fixes. Paramount has exactly **one** complete capture (2026-08-13) and none
since, so **none of these affects any data on screen today** — they change what the *next* Paramount
capture writes.

**3. `20260814193351_pmt_duplicate_name_columns_deprecated` (issue #964, PR #981).** Stops storing a
second copy of the Paramount property name on two tables that already link to the real property
record. The copies agree today (zero mismatches measured), which is the safe moment to stop writing
them — before a future capture makes them disagree and nobody can say which is right.
*Destructive elements:* makes the two copy columns nullable (`DROP NOT NULL`), drops one index
(`plm.idx_pmt_atp_name`). **No column dropped, no data rewritten.** Nothing reads the copies.
**Recommendation: apply**, first of the three.

**4. `20260814213043_pmt_metadata_element_normalization` (issue #965, PR #1006).** Paramount repeats
the same six metadata heading labels on every value row — 207,522 rows in production carry them.
This creates one row per heading per capture and points the value rows at it. *Additive:* new table
`plm.pmt_metadata_element` with full security, backfill, immutability triggers, a foreign key, and
deprecation comments. **Deliberately does not drop the six heading columns** — that was staged to
wait for a proven preview capture. **Recommendation: apply**, second, and rehearse a Paramount
capture on preview so the deferred column drop can eventually proceed.

**5. `20260814223552_pmt_collection_paramount_term_normalization` (issue #970, PR #1032).** Paramount
calls something a "Collection"; POP presents it as a "Style Guide". That word was being stored on
1,928 rows; this states it once in the view instead. *Destructive element:* `DROP COLUMN
plm.pmt_collection.paramount_term`, and the view `api.pmt_style_guides` is dropped and recreated. The
consumer-visible column name is unchanged — the view still returns `paramount_term`, now as a fixed
label. Verified today that nothing else has redefined that view since. **Recommendation: apply**,
third and last of the set.

### 6. Durable source resolutions — `20260814233423_remaining_source_resolution_durable_home` (issue #999, PR #1038)

**What it does.** Moves human "this source record means this POP record" decisions out of the
capture-snapshot tables (where the next scrape wipes them) into one permanent home, and installs
triggers that refuse any future attempt to write a decision back onto a landing row.

**⚠️ Two blockers, and this is the finding that matters most here.**

1. **It cannot run without a seventh unapplied migration.** `20260814224937_source_resolution_durable_home`
   creates the permanent table. It is merged to `main` and **also unapplied** —
   `plm.source_resolution` does not exist in production. It was not on the original list of six.
2. **Nine days of merges broke it.** That permanent table declares a foreign key to `core.character`.
   `core.character` was **dropped from production today** (2026-08-23,
   `drop_empty_universe_a_character_tables`, issue #1374). As written, migration 224937 would now
   **fail outright**, and 233423 with it. Today's migration already anticipated this — it defensively
   removes that foreign key "if the table exists" — which is the same session noticing the problem
   from the other side.

**Broken today by its absence?** No decisions are lost: production holds **zero** resolved rows in
every landing table checked (OPA property, character and pair tables; Warner normalized). The
exposure is that the guard rails are not installed, so the *first* human decision anyone records can
still be written into a capture snapshot, where the next scrape erases it.

**Additive or destructive?** Mostly additive (staging, inserts into the new table, a rebuilt
`api.opa_property_reconciliation` view, twenty refusal triggers). It does **rewrite data**: it blanks
the resolution columns on the OPA and Warner landing tables after copying them across — harmless
today only because those columns are empty.

**Recommendation: needs owner decision — do not apply as written.** Both files need a small rework to
drop the `core.character` reference before either can ever be applied, then preview rehearsal. Until
then, treat "record a source-to-POP decision" as not yet supported.

---

## What I recommend, in order

1. Decide the Warner API-view question (item 1), then rehearse and apply #958 — it is the only live
   wrong answer in the database.
2. Retire #969 as superseded and make sure it can never be promoted by accident.
3. Rehearse and apply the three Paramount migrations **in version order** in one window.
4. Send the source-resolution pair (#963/#999) back for a small fix before scheduling anything.
5. Close issue #949 only when the checker is repaired, so the alarm stops being throttled shut.

## Limits of this audit

Preview was not queried from this session (the database connection here is production-bound); the
statement that none of the six reached preview is taken from the task brief and is consistent with
the absence of any preview-rehearsal evidence for them under `docs/verification/`. The production
findings above are first-hand.
