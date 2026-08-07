# Disney OPA extract — FIRST REAL `--apply` INTO PREVIEW

**Date (UTC):** 2026-08-07
**Issue:** [#581](https://github.com/u2giants/shared-db/issues/581) — "HANDOVER: load the
Disney OPA extract into preview — tables exist, 0 rows, dry run PASSES"
**Claim issue:** #589 · **Orchestrator marker:** #587
**Target:** PREVIEW `rjyboqwcdzcocqgmsyel` — **production `qsllyeztdwjgirsysgai` was never
contacted for any write.**
**Machine:** al8960ofc · **Agent:** Claude (Opus 5) sub-agent
**Repo state at start of work:** `origin/main` = `dc1b760`, 405 migration files.

> **NO MIGRATION WAS CREATED BY THIS WORK.** Preview's ledger is 405 rows before and 405
> rows after, max version `20260807200000` before and after. This task was a *data load*
> and a *tooling* change, nothing else. No table, view, function, policy, constraint,
> index or grant was altered.

---

## 1. What this proves, in one line

The `--apply` path — the one thing issue #581 listed as **NOT proven**, because it had
only ever run against invented fixtures — now works against the real Disney extract, and
**all three of its previously-unexercised safety guards were made to fire for real
before and after the load.**

---

## 2. Exact versions in effect

Every OPA migration below was **already applied** to preview before this work and was
**not modified**. These are the 14-digit versions the loaded data depends on:

| Version | File | Role |
|---|---|---|
| `20260807170000` | `opa_property_character_landing.sql` | landing table `plm.opa_property_character`, view `api.opa_property_character` |
| `20260807170100` | `opa_property_character_importer.sql` | `plm.sync_opa_property_character(jsonb, text, numeric)` |
| `20260807180000` | `opa_sync_reentrancy_fix.sql` | re-entrancy fix |
| `20260807190000` | `opa_security_and_view_corrections.sql` | RLS to the `erp_` posture; `api.opa_property_reconciliation` regrouped to node grain; NULL-safe shrink band; `pg_temp`-qualified staging |
| `20260807200000` | `opa_comment_corrections.sql` | `coalesce(...,'{}')` + stable `ORDER BY` on the view's arrays; comment corrections |

Ledger check against preview, before and after: `405` rows,
`max(version) = 20260807200000`, and all five versions above present
(`opa_migs_applied = 5`).

## 3. Exact source file

| Property | Value |
|---|---|
| Repository | `u2giants/licensor-source-data` (**PRIVATE**) |
| Path | `disney-opa/opa-characters.csv` |
| Fetch | `gh api -H "Accept: application/vnd.github.raw" repos/.../contents/...` |
| **Bytes** | **1,069,881** — matches the recorded size exactly |
| **SHA-256** | **`333a1c04ea2da5a678da3527ee9a28b503cb6c16af94dbd902e10fbe776a5d69`** — matches `BUILD-NOTE-20260807.md` exactly |
| Lines | 10,263 (1 header + 10,262 data rows) |

The `Accept: application/vnd.github.raw` header is **required**: `gh api` on a `contents/`
path returns an empty body for files over 1 MB. The file was fetched to a scratchpad
directory outside the repo and **was never written into `shared-db`**, which is PUBLIC.

### Invocation actually used

```
OPA_CSV_PATH=<scratch>/opa-characters.csv
OPA_CAPTURED_AT=2026-08-06
OPA_SOURCE_URL='https://opa.disney.com/ProdApp/createEditProduct.spring'
OPA_MIN_ROWS=10262
OPA_EXPECTED_PROJECT_REF=rjyboqwcdzcocqgmsyel
SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY  <- 1Password vibe_coding, injected via `op run`
node tools/sync-opa-property-character.mjs --apply
```

No credential value was written to any file, commit, log or report.

---

## 4. Row counts — BEFORE and AFTER

All measured against `rjyboqwcdzcocqgmsyel` via the Management API
`/v1/projects/rjyboqwcdzcocqgmsyel/database/query`, with the ref **named in the request
path** so the target could not drift (see §7).

| Table / view | BEFORE | AFTER | Note |
|---|---:|---:|---|
| `plm.opa_property_character` | **0** | **10,262** | the load |
| `api.opa_property_character` (view) | 0 | 10,262 | passthrough |
| `api.opa_property_reconciliation` (view) | 0 | **1,445** | one row per node — see §5.1 |
| `core.property_character` | **0** | **0** | untouched, as designed |
| `core.character` | **0** | **0** | untouched, as designed |
| `supabase_migrations.schema_migrations` | 405 | 405 | **no migration created** |

Importer return value on the real load:

```json
{"mode":"mirror_only","captured_at":"2026-08-06","rows_seen":10262,
 "rows_inserted":10262,"rows_updated":0,"rows_unchanged":0,"rows_missing":0,
 "distinct_property":1445,"distinct_character":9613,
 "snapshot_hash":"f8d229505c0767fa3afaa18e7c768d70"}
```

Independently re-measured in the database (not taken from the importer's own report):
`count(*) = 10262`, `count(distinct licensed_property_id) = 1445`,
`count(distinct character_id) = 9613`. Every figure issue #581 predicted is reproduced
exactly: **10,262 rows / 1,445 properties / 9,613 characters / 10,240 distinct name pairs
/ 22 name-pair collisions.**

---

## 5. Behavioural assertions

Per the repo's standard, "it applied successfully" proves nothing. Each item below
asserts **behaviour** or **the object itself**, not an exit code or a ledger row.

### 5.1 The node-grain fix (`20260807190000`) actually holds

`api.opa_property_reconciliation` returns **exactly 1,445 rows** against 1,445 distinct
`licensed_property_id` values. The bug that migration fixed produced *more* rows than
nodes by grouping on per-row resolution columns. With 10,262 rows now loaded across
1,445 nodes, a regression could not hide: it would show as a row count above 1,445.

`sum(opa_character_count) = 10262` — the view accounts for every loaded row exactly once,
with none double-counted and none dropped.

### 5.2 The object, not just the data

- `to_regclass('plm.opa_property_character')` → `plm.opa_property_character` (not null).
- `to_regclass('api.opa_property_reconciliation')` → not null.
- `pg_class.relrowsecurity` on the landing table → **`true`**; `pg_policies` count → **1**.
- `pg_get_viewdef('api.opa_property_reconciliation', true)` was fetched and compared
  against migration `20260807200000`. It matches: `coalesce(array_agg(DISTINCT ... ORDER
  BY ...) FILTER (...), '{}')` on all three array columns, `GROUP BY
  o.licensed_property_id` alone. **No schema drift between repo and preview.**

### 5.3 Primary key = the ID pair, and it survived a real 10,262-row load

`pg_get_constraintdef` → `PRIMARY KEY (licensed_property_id, character_id)`.
The load inserted all 10,262 rows with **zero** conflicts, which is the live proof that
the ID pair is unique across the real extract. The **name** pair is not: 10,240 distinct
`(property_name, character_name)` pairs measured in the database → **22 collisions**,
matching the dry run. This is exactly why the key is the ID pair.

### 5.4 Idempotence / re-entrancy (`20260807180000`)

The identical extract was applied a **second** time:

```json
{"rows_seen":10262,"rows_inserted":0,"rows_updated":0,"rows_unchanged":10262,
 "rows_missing":0,"snapshot_hash":"f8d229505c0767fa3afaa18e7c768d70"}
```

Zero inserts, zero updates, 10,262 unchanged, **identical snapshot hash**. Re-running the
loader is safe.

---

## 6. NEGATIVE assertions — proving it says NO when it should

A view that returns the right answer for a matching row proves half of nothing. These
assert the *absence* of what must be absent, and the *refusal* of what must be refused.

### 6.1 The reconciliation view

| Assertion | Expected | Measured |
|---|---:|---:|
| Rows for a `licensed_property_id` that does not exist (`-999999`) | 0 | **0** |
| Nodes claiming a `core.property` match (`matched_core_property_count <> 0`) | 0 | **0** |
| Nodes with `resolution_status <> 'unresolved'` | 0 | **0** |
| Nodes with a non-null `last_resolved_at` | 0 | **0** |
| Nodes where `unresolved_character_count <> opa_character_count` | 0 | **0** |
| Landing rows with a non-null `property_id` | 0 | **0** |

The loader **resolves nothing**, exactly as documented. Every one of the 1,445 nodes is
`unresolved` with no core match — the correct state for a raw mirror with
`core.property_character` still at 0 rows.

### 6.2 The array contract of `20260807200000` — verified in both directions

`matched_core_property_ids`, `core_property_names` and `core_licensor_codes` are
**`'{}'` (empty array) for all 1,445 nodes and NULL for none** — measured as
`is null` → 0 rows, `= '{}'` → 1,445 rows.

This confirms the corrected comment on the view rather than contradicting it. The
discriminator it documents remains sound: *"an empty name array beside a **NON-EMPTY**
`matched_core_property_ids` means RLS suppression, not an unresolved node."* A genuinely
unresolved node has an **empty** `matched_core_property_ids`, so it cannot be mistaken for
RLS suppression. Had `20260807190000`'s original wording survived (which said "non-null"
rather than "non-empty"), every one of these 1,445 unresolved nodes would have satisfied
the RLS-suppression test and the discriminator would have been useless. **The
`20260807200000` correction is load-bearing, and this load is the first evidence of it.**

### 6.3 The three guards that had never fired outside fixtures

| Guard | How it was provoked | Result |
|---|---|---|
| **Wrong-target gate** | `SUPABASE_URL` → preview, `OPA_EXPECTED_PROJECT_REF` → the **production** ref | **Exit 1.** `REFUSING TO SEND ... NOTHING HAS BEEN SENT.` Aborted before the first byte. Deliberately arranged so the only possible failure mode still wrote to preview. |
| **`OPA_MIN_ROWS` floor** | `OPA_MIN_ROWS=10263` against a 10,262-row extract | **Exit 1.** `extract has 10262 data row(s), fewer than the expected minimum of 10263.` |
| **`OPA_MIN_ROWS` mandatory** | `--apply` with `OPA_MIN_ROWS` unset | **Exit 1.** `OPA_MIN_ROWS is required for --apply.` No default, as issue #581 states. |

### 6.4 The database shrink band — the strongest test performed

With 10,262 rows already stored, a **deliberately truncated** extract (first 1,000 data
rows, 104,101 bytes) was applied with `OPA_MIN_ROWS=1000` so the *runner-side* floor
passed and **only the database guard could catch it**.

- Result: **HTTP 400 from `plm.sync_opa_property_character`. Rejected.**
- The runner refused to print the response body (correct — it can contain extract
  content, and this repo and its CI logs are public).
- **The mirror survived intact**, re-measured immediately afterwards:
  `plm.opa_property_character = 10,262`, 1,445 properties, 9,613 characters,
  `api.opa_property_reconciliation = 1,445`. The rejecting transaction rolled back
  cleanly and destroyed nothing.

This is the guard that protects against a truncated or partly-scraped refresh. It had
never run against a real database before today.

---

## 7. The link-state trap — found, proven, and repaired

### 7.1 What was wrong

`supabase/.temp/` held two records of "which project am I linked to", and they
**disagreed** on the working checkout:

```
supabase/.temp/project-ref          ->  rjyboqwcdzcocqgmsyel   (PREVIEW)
supabase/.temp/linked-project.json  ->  qsllyeztdwjgirsysgai   (PRODUCTION)
```

The documented safety check was `cat supabase/.temp/project-ref`. **It passed** — while
the CLI would have targeted **production**. A green check over the wrong database is worse
than no check, because it converts caution into confidence.

### 7.2 The root cause, measured — not guessed

Running `supabase link --project-ref rjyboqwcdzcocqgmsyel` and inspecting the directory
afterwards shows that **`supabase link` writes only `project-ref`. It never creates,
refreshes or deletes `linked-project.json`.** That file is written by a *different* tool
(the Supabase editor extension / MCP tooling).

That is the whole incident: `linked-project.json` was **orphaned, stale state pointing at
production, and no amount of re-linking would ever have corrected it.** It simply sat
there looking authoritative.

This also corrected the checker's design mid-build. An earlier draft treated a missing
`linked-project.json` as "half-present link state = error". That would have **failed on
every correctly linked checkout**, and a check that cries wolf is one people learn to
skip. The rule is now: **`project-ref` is required; `linked-project.json` is optional but
must agree when present.**

### 7.3 The repair

Neither file is in git — `.gitignore` line 1 excludes `supabase/.temp/`. **So the fix
could not be a committed file. It had to be a committed check.**

1. **Local state repaired.** `supabase/.temp/` in the shared checkout was deleted and
   re-linked explicitly to `rjyboqwcdzcocqgmsyel`. The contradictory
   `linked-project.json` is gone. Verified: the checker now PASSES against the shared
   checkout naming preview.
2. **`tools/check-supabase-link-state.mjs`** (new) — a fail-closed gate. The expected ref
   is a **required input with no default**, because a default is indistinguishable from
   an unset variable at the moment it matters.
3. **`tools/check-supabase-link-state.test.mjs`** (new) — 24 tests. Picked up
   automatically by `.github/workflows/tools-offline-tests.yml`, which globs
   `tools/*.test.mjs` with no `paths:` filter, so it runs on every PR and every push to
   main. Offline, no secrets, no database contact.

### 7.4 Proof the check catches the real thing

Replayed against the **actual bytes of the two contradictory files** as they were found:

```
SUPABASE LINK STATE IS INCONSISTENT -- THIS IS THE 2026-08-07 TRAP.
  supabase/.temp/project-ref says      rjyboqwcdzcocqgmsyel
  supabase/.temp/linked-project.json says  qsllyeztdwjgirsysgai
```

It fails **even though `project-ref` matches the expected ref** — which is the precise
situation that produced a green check over a wrong target. The headline test encodes
exactly this case. CLI paths verified end-to-end:

| Invocation | Result |
|---|---|
| `--expect-ref=rjyboqwcdzcocqgmsyel` (repaired state) | exit **0**, both files reported |
| `--expect-ref=qsllyeztdwjgirsysgai` | exit **1**, `WRONG PROJECT` |
| no ref given | exit **1**, `REQUIRED and has no default` |

### 7.5 The Supabase MCP is bound to PRODUCTION

`get_project_url` returned **`https://qsllyeztdwjgirsysgai.supabase.co`**. The MCP takes
no project parameter, so it **cannot** be aimed at preview. It was **not used for any
read or write in this task.** Every database call went through the Management API with the
preview ref **named in the request path**, so the target could not drift.

---

## 8. Test results

| Suite | Result |
|---|---|
| `tools/sync-opa-property-character.test.mjs` | **45 / 45 pass** (unchanged; matches issue #581) |
| `tools/check-supabase-link-state.test.mjs` | **24 / 24 pass** (new) |
| Combined run | **69 / 69 pass**, 0 fail |

---

## 9. What was NOT done — deliberately

- **No production contact.** Nothing was read from or written to `qsllyeztdwjgirsysgai`.
  It remains 44 migrations behind preview; that is somebody else's task.
- **No migration created.** Preview's ledger is unchanged at 405 / `20260807200000`. The
  brief allocated no version and none was invented.
- **No promotion, no `main` push, no self-merge.** Delivered as a PR.
- **No resolution run.** `core.property_character`, `core.character`,
  `core.style_guide` and `core.style_guide_character` are all still **0 rows**. Mapping
  OPA nodes onto `core.property` is separate work.
- **No CSV committed.** The extract never entered this PUBLIC repo. No row of Disney data
  appears in this document, in the loader output, or in any error message.
- **`OPA_SOURCE_URL` snag NOT resolved** (issue #581 snag 1). The load used the bare page
  URL `https://opa.disney.com/ProdApp/createEditProduct.spring`, so `source_url` records
  *which page*, not *which slice*. All 10,262 rows carry one identical `source_url` and
  one `line_of_business` (`Home`). **A second LOB extract would be indistinguishable by
  `source_url` alone.** This still needs the owner decision issue #581 calls for; it is
  not blocked by anything technical here.
- **Bare-quote CSV rule still unexercised** (issue #581 snag 2). Disney's exporter quotes
  every field and the file has zero embedded quotes, so that branch did not fire. Still
  luck, still untested. Re-run the dry run on every refresh — it contacts no database.

---

## 10. Findings that ADD to issue #581

1. **`supabase link` does not write `linked-project.json`** (§7.2). This is the root cause
   of the trap and it is not recorded anywhere else. Any future instruction of the form
   "re-link to fix the link state" is **wrong** — re-linking cannot touch that file.

2. **A sentinel row exists in Disney's extract.** One row carries
   `licensed_property_id = -9999` and `character_id = -9998` — the only negative IDs in
   the file (all other IDs run from 38 to 1,159,383,366). It is loaded as a legitimate
   node, so **`api.opa_property_reconciliation`'s 1,445 rows include 1 sentinel; there are
   1,444 real property nodes.** Nothing rejects it today, and any consumer counting
   "Disney properties" off this mirror will be off by one. Recommend an owner decision on
   whether to filter negative IDs at the `api` view or reject them at the importer.

3. **The `20260807200000` array `coalesce` is load-bearing, not cosmetic** (§6.2). With
   real data it is what keeps the view's RLS-suppression discriminator meaningful. Under
   the pre-`20260807200000` wording all 1,445 unresolved nodes would have looked like RLS
   suppression.

4. **Issue #581 says `core.style_guide` and `core.style_guide_character` are 0 rows.**
   Confirmed for `core.character` (0) and `core.property_character` (0); the style-guide
   tables were not re-measured in this task and are outside its scope.

Nothing measured in this task **contradicts** issue #581. Every figure it predicted was
reproduced exactly.
