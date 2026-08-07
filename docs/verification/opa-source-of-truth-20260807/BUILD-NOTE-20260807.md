# OPA property→character — BUILD NOTE

**Status: BUILT (schema + loader + contract tests). NOT YET APPLIED ANYWHERE.**

This records what was actually built from
[`README.md`](./README.md) (the authoritative design, PR #485, which supersedes
`../opa-characters-20260806/DESIGN.md` from PR #476), where the build
**deliberately departs** from that design, and every migration it depends on.

**Author:** sub-agent `opa-build`, dispatched by the shared-db coordinator
(session `697b5b87`, machine `al8960ofc`, coordinator marker: GitHub issue #491).
**Database claim:** issue #496.
**Branch:** `agent/opa-build-20260807`, cut from `origin/main` at
`5613fb042a4cf0677ea365102e62fe38f3fac124`.
**Date:** 2026-08-07.

---

## 1. What was built

| File | Purpose |
| --- | --- |
| `supabase/migrations/20260807170000_opa_property_character_landing.sql` | Landing schema (§7.1) + the junction (§7.2) + both `api` views (§7.5, §7.6) |
| `supabase/migrations/20260807170100_opa_property_character_importer.sql` | Privilege predicate + guarded `SECURITY DEFINER` loader + `public.*` wrapper |
| `supabase/tests/opa_property_character_landing_contracts.sql` | Contract tests for the landing |
| `supabase/tests/opa_property_character_importer_contracts.sql` | Contract tests for the loader |
| `tools/sync-opa-property-character.mjs` | Runner — **logic only, no data** |

### Migration versions this work depends on — all 14 digits, in full

| Version | Migration | Why it is a dependency |
| --- | --- | --- |
| `20260621150815` | `app_core.sql` | Defines `core.licensor`, `core.property`, `core.character`, `app.entity_status`, `app.has_role` / `app.has_any_role`. The junction FKs and the RLS posture require all of these. |
| `20260710135950` | `reconcile_dflow_baseline.sql` | Creates `dflow.property_character_associations` — the pre-existing third table analysed in §4 below. Not modified. |
| `20260724030000` | `coldlion_licensor_property_phase1_mirror_schema.sql` | The `plm.erp_*` mirror pattern (raw typed mirror in `plm`, view in `api`, nullable resolution columns) that the landing copies. |
| `20260724060000` | `coldlion_licensor_property_phase2a_mirror_importer.sql` | The `SECURITY DEFINER` + thin `public.*` wrapper + advisory-lock + guarded-snapshot pattern that the importer copies. |
| `20260727230000` | `core_style_guide_axis.sql` | Creates `core.style_guide` and `core.style_guide_character` — the axis-2 sibling. The junction's RLS posture is copied from it, and the reconciliation invariant is asserted against it. |
| `20260807170000` | *(this work)* `opa_property_character_landing.sql` | Required by `20260807170100`, which writes the table it creates. |

The highest migration version on `origin/main` when these were authored was
**`20260807030000`**. Both new versions were **allocated by the coordinator**, not
derived from `now()` — two agents dispatched in the same minute pick the same
number, and a duplicate version means one migration is **silently skipped**,
because Supabase's ledger keys on the version alone and not on the filename.
That has happened twice in this repository.

### Objects created — matching what the migrations actually declare

Not what the design doc's prose listed; see §3 for where those disagreed.

**`20260807170000` (landing)**

| Object | Kind |
| --- | --- |
| `plm.opa_property_character` | table |
| `opa_property_character_pkey` | PK `(licensed_property_id, character_id)` |
| `opa_property_character_property_name_chk` | check |
| `opa_property_character_character_name_chk` | check |
| `opa_property_character_option_source_chk` | check |
| `opa_property_character_lob_chk` | check |
| `opa_property_character_resolution_status_chk` | check |
| `opa_property_character_property_id_fkey` | FK → `core.property(id)` ON DELETE RESTRICT |
| `plm.idx_opa_property_character_property_name` | index |
| `plm.idx_opa_property_character_character_name` | index |
| `plm.idx_opa_property_character_character_id` | index |
| `plm.idx_opa_property_character_licensed_property_id` | index |
| `plm.idx_opa_property_character_property_id` | partial index |
| `plm.idx_opa_property_character_resolution_status` | index |
| `plm.idx_opa_property_character_base_property_name` | expression index |
| `opa_property_character_read` | RLS policy |
| `core.property_character` | table |
| `property_character_pkey` | PK `(property_id, character_id)` |
| `property_character_property_id_fkey` | FK → `core.property(id)` ON DELETE RESTRICT |
| `property_character_character_id_fkey` | FK → `core.character(id)` ON DELETE CASCADE |
| `property_character_source_chk` | check |
| `core.idx_property_character_character_id` | index |
| `shared_read`, `admin_write` | RLS policies on `core.property_character` |
| `api.opa_property_character` | view (`security_invoker`) |
| `api.opa_property_reconciliation` | view (`security_invoker`) |

**`20260807170100` (importer)**

| Object | Kind |
| --- | --- |
| `plm.opa_loader_privilege_ok(text, text)` | function — pure, immutable, testable |
| `plm.sync_opa_property_character(jsonb, text, numeric)` | function — `SECURITY DEFINER` |
| `public.sync_opa_property_character(jsonb, text, numeric)` | function — thin wrapper |

**Nothing existing is altered or dropped. Nothing in `core.*` is modified.
`core.character` is not populated. Nothing is resolved. Nothing is deleted.**

---

## 2. The biggest deliberate departure: NO SEED MIGRATION

**The design doc's §7.7 instructs a seed migration generated from the committed
CSV. That was NOT done, and must never be done.**

§7.7's justification is explicit: the seed *"crosses no new confidentiality
boundary"* because the CSV *"is already committed to this **private**
repository (PR #466)."* **That premise is false as of today.**

- `u2giants/shared-db` was **public for seven weeks** while holding the
  confidential Disney extract.
- The CSV was **removed** from this repo by **PR #495** and now lives only in the
  private repo **`u2giants/licensor-source-data`** at
  `disney-opa/opa-characters.csv`.
- **This repository is public right now.**

A seed migration would re-materialise the same 10,262 confidential Disney rows
as SQL `INSERT`s under `supabase/migrations/` — permanently, in git history, in a
public repository. It would reopen the exact leak PR #495 just closed, in a new
file, and no later deletion could undo it.

> **The rule this build follows: SCHEMA IN GIT, DATA OUT OF GIT.**
> No `INSERT` of a Disney row appears in any migration. No CSV is committed
> anywhere in this repo. Not one sample row — not in a comment, not in a test
> fixture, not in a doc. **Every fixture in both test files is invented.**

Instead, rows arrive at runtime, following the repository's real and safe
precedent — the `plm.erp_*` ColdLion vendor mirror (`20260724030000` /
`20260724060000`): a `SECURITY DEFINER` function taking a `jsonb` snapshot, a
thin `public.*` wrapper so a service-role caller needs no raw DB password, and a
runner under `tools/` that supplies the payload. The runner reads the CSV from
the **private** repo and contains no data itself.

Two consequences worth stating plainly:

1. **Applying these migrations loads zero rows.** The tables land empty. That is
   correct and intended.
2. **The database is now the only place the Disney rows exist outside the private
   repo.** They are production-sensitive there. `plm.opa_property_character`
   grants `anon` nothing and both `api` views are `security_invoker`.

---

## 3. Naming defects in the design doc, and what was actually written

The doc's §7.2 lists constraint names its own DDL contradicts. Resolved
deliberately, and the object list in §1 above matches the catalog, not the prose.

| Design doc said | Actually written | Why |
| --- | --- | --- |
| `core.property_character_pkey` (prose) vs `constraint core_property_character_pkey` (its DDL) | **`property_character_pkey`** | The two cannot both be right. Chose the name Postgres itself would generate, so prose, DDL and `pg_constraint` agree. A constraint name is not schema-qualified in `pg_constraint.conname`; the schema comes from the table. |
| J3/J4 listed as *named* FK constraints, but the DDL used inline `references` (auto-generating `property_character_property_id_fkey` / `property_character_character_id_fkey`) | **Named explicitly** as `property_character_property_id_fkey` and `property_character_character_id_fkey` | Same names, but declared rather than inferred, so a test can assert them. |
| §7.1 lists indexes unqualified | Land in their table's schema — **`plm.*`** for the landing, **`core.*`** for the junction | Stated explicitly; the tests assert `schemaname`. |

Two further departures, both deliberate:

- **The junction's RLS posture is copied from `core.style_guide_character`, not
  from the design doc.** The doc proposed `for select to authenticated using
  (true)`. Its sibling on the other axis uses `app.has_any_role([...])` plus an
  `admin_write` policy. Canonical `core` data should read the way its sibling
  reads; the permissive form belongs to the `plm` vendor mirror, which does use it.
- **`property_character_source_chk`** was added (non-blank `source`). Not in the
  doc; a one-line integrity guard on a free-text provenance column.

---

## 4. The three overlapping property↔character tables — required reading

The coordinator flagged that a property↔character junction **already exists** and
that this would be the third. Both pre-existing tables were read before writing
any DDL. They model **different things**, and the design doc's §5.5 concern about
duplication is real but narrower than it looks.

### `dflow.property_character_associations` — legacy, app-local, and NOT a peer

Created in `20260710135950_reconcile_dflow_baseline.sql`.
PK `(property_id, character_id, licensor_id)`, integer keys.

The decisive fact: **both FKs point at the SAME table**,
`dflow.properties_and_characters` — one table holding rows typed `PROPERTY` and
rows typed `CHARACTER`, with a self-referential edge table between them. And per
`docs/style-guides-characters-and-royalties.md` §5 (and README §3.1), the rows
typed `PROPERTY` **are style guides**; the column name lies.

> So despite its name, `dflow.property_character_associations` is a
> **style-guide↔character edge inside the DesignFlow application's own schema.**
> It is a **migration SOURCE**, not a peer: its 9,622 edges are destined for
> `core.style_guide_character`. Nothing reads it as canonical. This work does not
> touch it.

`core.properties_and_characters` (10,122) and
`core.property_character_associations` (9,622) mirror the same legacy shapes.
Same reading applies. **Do not re-open the retracted lineage argument** (README
"A retracted claim you must NOT re-derive").

### `core.style_guide_character` — axis 2, STYLE

Created in `20260727230000_core_style_guide_axis.sql`. PK `(style_guide_id,
character_id)`, uuid keys. Answers **"which art files show this character."**
M:N by owner ruling 2026-07-23.

### `core.property_character` — axis 1, OWNERSHIP (built here)

Answers **"which licensed property does Disney approve this character under."**
Left endpoint `core.property`.

### How the three stay reconciled instead of drifting apart

The design doc's §5.5 warns that for the 178 style guides that are 1:1 with 178
OPA property nodes, the two `core` tables would assert the same ~4,967 facts
under two different left-hand keys, and would drift the first time one is updated.

**The contract that prevents it, and it is now enforced in the test suite:**

> **`core.style_guide.property_id` is the SINGLE bridge between the two axes.**
> A style guide belongs to exactly one property. Therefore every
> `core.style_guide_character` edge implies **at most one** property, and
> `core.property_character` is a **superset projection** of it — never an
> independent second opinion. Formally:
>
> ```
> every (style_guide.property_id, character_id) pair implied by
> core.style_guide_character MUST exist in core.property_character
> ```

Neither table is trigger-derived from the other — that would be the tempting fix
and it is the wrong one, because a derived table hides the moment the two
disagree instead of surfacing it. The invariant is **checkable at any time** and
is asserted in `opa_property_character_landing_contracts.sql` §5.

Because `core.character` holds **0 rows**, both tables are empty today and the
invariant holds trivially. **It must be re-asserted before either is first
populated** — that is the moment the risk becomes real, not now.

### Why it was built rather than questioned further

Albert ruled on 2026-08-07 to build it, because **Laura, the licensing manager,
confirmed a character can appear in multiple properties.** That is a business
fact from the domain authority. The design doc argues against the junction on
measurement grounds (~6 genuine multi-property cases out of 9,613); that argument
has been **heard and overruled** and is not re-argued here.

Having read all three tables, the ruling is **not** contradicted by what is in the
database: the third table is a genuinely different axis from
`core.style_guide_character`, and the `dflow` one is a legacy app-local
style-guide edge that is not a peer at all. **No push-back was warranted**, so
none is raised. The cost is not the build — `core.character` is empty, so it is
nearly free — **it is owning two overlapping contracts forever**, which the
invariant above is designed to make cheap.

---

## 5. The natural key: the ID pair, never the name pair

`plm.opa_property_character` is keyed on
**`(licensed_property_id, character_id)`** — Disney's **IDs**.

Measured on the 2026-08-06 extract (corrected in PR #495; an older copy of the
README asserting the name pair is **stale**):

| Key | Distinct values over 10,262 rows |
| --- | ---: |
| `(licensedPropertyID, characterID)` — **used** | **10,262** — unique |
| `(property, character)` display names — **rejected** | 10,240 — **22 collisions** |

Keying on names would have **silently dropped 22 rows**. Two distinct
`licensedPropertyID`s share one property display name (`Davy Crockett` is both
`216` and `425` — two genuinely distinct Disney properties).

ID-keying also handles, without any special case, the **21 OPA character names
that carry multiple `characterID`s** (e.g. `Beagle Boys` has `510`, `512`,
`518031315` — an apparent Disney system migration that left two ID generations
live). **Do not dedupe those without asking Disney.**

This is guarded in three places, on purpose:

1. the PK itself;
2. the importer (`G7`) aborts on a duplicate ID pair inside one snapshot rather
   than letting last-write-wins pick a winner at random;
3. the runner rejects the same thing before any network call.

And it is **regression-tested from both ends**: the landing test inserts two rows
with an *identical* name pair under different IDs and asserts **both** land; the
importer test does the same through the loader; and the landing test asserts no
`UNIQUE` index exists on `(property_name, character_name)`.

---

## 6. The privilege guard, and how it is actually proved

§7.4 of the design doc contains the **null-permissive shape**:

```sql
if not ( current_user = 'postgres' or auth.role() = 'service_role' ) then raise ...
```

Inside a migration `auth.role()` is **NULL**. `NULL = 'service_role'` is `NULL`;
`false or NULL` is `NULL`; `if not NULL then` **never runs the body**. The guard
reads as strict and behaves as wide open, admitting everyone forever. This has
already fired in this repo.

Three deliberate choices:

1. **The guard is a FUNCTION, `plm.opa_loader_privilege_ok(text, text)`, not a
   `do $$ … $$` block.** An anonymous block **never lands in `pg_proc`**, so a
   test cannot see it, call it, or prove it rejects anything — a defect already
   caught in this repo, where a test queried `pg_proc.prosrc` for a `DO` block
   and therefore asserted nothing. This predicate is directly callable, so the
   test asserts the NULL case is **REJECTED** rather than asserting that some
   text exists somewhere.
2. **It takes `session_user`, not `current_user`.** `SECURITY DEFINER` rewrites
   `current_user` to the function **owner**, so a `current_user` check inside a
   definer function always passes and guards nothing. `session_user` is the real
   login role and is unaffected. *(The design doc's corrected shape still used
   `current_user`; this is a third departure from it.)*
3. **It requires a non-null, non-empty, positively-matched identity.** Every
   other input, including NULL on both arguments, returns `false`.

**Neutralise-and-observe** is implemented as a real construction, not a claim
(`opa_property_character_importer_contracts.sql` §3): the test builds the
forbidden `not ( … or … )` shape as a `pg_temp` function inside the transaction,
calls it with `(null, null)`, and asserts that it **ADMITS** while the real guard
**REJECTS**. If the two ever agree, the test fails loudly with a message saying
either the guard regressed or the test can no longer detect the regression. A
negative test that passes with the bug present is a false safety signal; this one
demonstrates it can see the bug.

A second class of the same defect was found and fixed **in the test file itself**
during this build: every importer guard raises `P0001`, and an early draft raised
its own "was ACCEPTED" failure *inside* a block trapping `sqlstate 'P0001'` — so
the failure would have been swallowed by the very handler meant to absorb the
guard, and those ten negative tests would have passed no matter what. They now
set a flag inside the block and assert **outside** it.

---

## 7. Other things the build refuses to do, and why

- **Resolves nothing.** `property_id` lands `NULL`, `resolution_status` lands
  `'unresolved'` on every row, and the five resolution columns are **absent from
  both the insert list and the update `SET` list** of the importer's upsert — so
  a re-import can never wipe a human's decision. Tested.
- **Deletes nothing.** Rows held but absent from a snapshot are counted as
  `rows_missing` and **left alone**. "Presence adds and corrects; **absence never
  removes**."
- **Populates no `core.character` row**, and writes nothing to `core.*` at all.

These are not caution for its own sake — **two owner gates are still open** (how
far Disney may overwrite our curated names; whether ColdLion deletions should
propagate). Resolving nothing is exactly what makes this migration safe to ship
**before** those rulings.

The importer also has **no `resolve` or `promote` mode**. `mirror_only` is the
only mode that exists and any other value raises. There is deliberately no code
path for a decision that has not been made.

- **`option_source_id = 1007` stays pinned.** Its meaning is unknown; the pin
  exists so a future extract carrying a different value **fails loudly** rather
  than landing silently under an assumption nobody has verified. If a later
  extract legitimately differs, **widen it in a new migration with a recorded
  reason** — do not drop it.
- **Negative sentinel IDs are accepted.** `Special Projects` carries
  `licensedPropertyID = -9999`, `characterID = -9998`. Any unsigned or
  `text`-with-digit-check typing rejects them. Tested at both the table and the
  loader.
- **`captured_at` is supplied explicitly and never derived from `now()`.** The
  server runs **`America/New_York`**: a timestamp at UTC midnight reads back
  through `::date` as the **previous day**. The landing test *demonstrates* the
  hazard rather than assuming it, and asserts that midday-UTC pinning reads as
  the same date in both UTC and server-local time.
- **No schedule, no automation.** OPA has no API, no change feed and no webhook;
  a refresh requires Albert to complete MFA in his own browser and re-extract.

---

## 8. Verification status — read this before merging

**No SQL in this branch has been executed anywhere.** The build machine has
**neither Docker nor a local PostgreSQL**, so there was no disposable database to
run against, and this agent was **not pre-authorised to push to preview**
(`rjyboqwcdzcocqgmsyel`). Reported as it stands rather than dressed up:

| Claim | Status |
| --- | --- |
| Runner parses, validates and rejects correctly | **PROVED** — executed under Node against invented CSV fixtures; reproduces the name-pair collision (4 rows → 3 distinct name pairs → 1 collision), accepts negative sentinels, handles quoted/embedded-comma fields, and rejects `optionSourceID <> 1007`, duplicate ID pairs and a missing `captured_at`. |
| Migrations apply cleanly | **NOT PROVED** — needs a database. |
| Every declared object exists | **NOT PROVED** — the assertions are written (`to_regclass`, `pg_constraint`, `pg_indexes`, `pg_policies`, `pg_proc`, `reloptions`); they have not been run. |
| Guards reject behaviourally | **NOT PROVED** — written and not run. |
| Neutralise-and-observe on the privilege guard | **CONSTRUCTED, NOT RUN** — the demonstration is real code inside the test, but it has not executed. |

> **"It applied successfully" would prove nothing anyway.** The ledger can record
> a migration whose object does not exist, and this repo has already shipped a
> syntactically perfect trigger that was permanently dead (a `BEFORE` trigger read
> a `GENERATED … STORED` column, which Postgres populates *after* before-triggers,
> so the value was always NULL and the guard never fired). **The two contract test
> files must be run and seen to pass before anyone treats this as done.**

**Next step is the coordinator's:** authorise a preview dry-run and apply against
`rjyboqwcdzcocqgmsyel` (confirming `supabase/.temp/project-ref` reads it
immediately before **every** push), then run both contract test files and record
the output here.

---

## 9. Follow-ups

- Run both contract test files against preview and record the result in §8.
- **§8 of the README's two owner decisions are still open** and gate any
  resolution work: how far Disney may overwrite our curated names, and whether
  ColdLion deletions propagate.
- **Serialise this against the ColdLion licensor/property cutover** — both touch
  the property spine (AGENTS.md §4 rule 1).
- Re-assert the axis-1/axis-2 reconciliation invariant (§4) **before**
  `core.property_character` or `core.style_guide_character` is first populated.
  It is trivially true while both are empty.
- Check whether `api.coldlion_*_reconciliation` are definer- or invoker-security
  views (README §7.5). If definer, that is a **pre-existing** finding to raise
  separately — not something to copy.
- Raise the Morbius block (README §5.3 — 30 Disney+ TV characters mis-filed under
  a film **in Disney's own portal**) with Laura or Disney. It is the clearest
  counter-example to "Disney is always right".
