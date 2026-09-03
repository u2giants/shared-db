# Licensor source extracts reconciled against `core.property` / `core.licensor`

Issue: [#640](https://github.com/u2giants/shared-db/issues/640) — first run of the comparison.
Date: 2026-09-03. Read-only against **production `qsllyeztdwjgirsysgai`** (proved with
`get_project_url` immediately before the first query; every write was refused by the
read-only transaction, which is itself evidence no mutation occurred).

**Nothing here is a decision.** Every disagreement below is an owner decision per #640 §5.
Absence in a source is not a delete instruction (#640 §4).

---

## 0. Headline

| | |
|---|---|
| Source property names examined (four extracts, de-duplicated) | **2,055** |
| Of those, matched to a `core.property` row by name | **63** |
| Present in a source extract, absent from `core.property` | **1,992** |
| `core.property` rows total | **260** (all 260 carry a `licensor_id`) |
| `core.property` rows not found in any of the four extracts | **197** |
| Cross-licensor attribution disagreements (named below) | **9** |
| Source rows carrying a stored resolution to `core.property` | **0** |

**The dominant finding is not misattribution — it is a level mismatch.** For the Warner
family, `core.property` is largely populated with **characters**, not properties: 11 of the
14 `DC` rows (BATMAN, SUPERMAN, HARLEY QUINN, …) match Warner's **character** catalogue, not
its property catalogue. The same pattern holds for `SW` (CHEWBACCA, DARTH VADER, BB-8) and
`MV` (THANOS, GROOT, HULK). A reconciliation that treats these as properties will report them
as "missing from the licensor" when the licensor does carry them — one level down.

---

## 1. The derived licensor ↔ portal mapping, and how it was derived

The mapping was **not assumed**. It is an output of the data.

Method: normalise every source property name and every `core.property.name` to a comparison
key (lowercase, leading *and trailing* article removed, non-alphanumerics stripped), join on
that key, then read off which `core.licensor` the matched core rows belong to, per source
system. Whatever licensors fall out are the mapping.

Result of that cross-tab (matched source rows → core licensor):

| Source portal | core licensor(s) that fell out | matched rows |
|---|---|---|
| Disney OPA | `DY` DISNEY **16**; `MV` MARVEL 6; `SW` STAR WARS 1; `PN` PEANUTS WORLDWIDE 1; `VM` VIACOM MULTI 1 | 25 |
| Warner STARLABS | `WB` WARNER BROS **5** (9 after the trailing-article fix, §5) | 5 |
| Paramount Creative Library | `VM` VIACOM MULTI **9** | 9 |
| NBCU Creative Asset Factory | `NB` NBC **20** | 20 |

**Derived mapping (each portal's modal licensor):**

- Disney OPA → `DY` DISNEY, with `MV` MARVEL and `SW` STAR WARS as sub-brands held as
  *separate* `core.licensor` rows. This is a real structural fact about our data, not an
  error: Disney's portal presents Marvel and Star Wars titles, but our master data files
  them under distinct licensors. Any royalty roll-up by `core.licensor` will therefore split
  one portal's output three ways.
- Warner STARLABS → `WB` WARNER BROS, with `DC` and `HP` as separate `core.licensor` rows.
  Warner's own `plm.wb_franchise` confirms this at franchise level: its 8 franchises are
  Adult Swim, Cartoon Network, **DC**, Hanna-Barbera, **Harry Potter**, HBO, Looney Tunes,
  Warner Bros. So `DC`/`HP` are Warner franchises in the source and licensors in our data.
- Paramount Creative Library → `VM` VIACOM MULTI. Clean: **every** Paramount match landed on
  `VM` and nothing else.
- NBCU Creative Asset Factory → `NB` NBC. Clean: **every** NBCU match landed on `NB`.

**What the derivation refutes:** a naive one-portal-one-licensor assumption. Two of the four
portals (Disney, Warner) span three `core.licensor` rows each. Starting from the assumption
would have produced two false "misattribution" categories out of thin air.

---

## 2. The join key, and why

**Key used: normalised property NAME, scoped per source system.**
**Key deliberately NOT used: `source_id`.**

The four extracts do not share an ID space, and integer IDs collide hard across licensors.
Measured on production:

> `plm.opa_property.licensed_property_id` and `plm.sega_property.property_source_id`
> **collide on 105 values** (range 101–210).
> `101` = Disney **"Aristocats"** and Sega **"Company of Heroes 2"**.
> `102` = Disney **"Aristocats - Individual Characters"** and Sega
> **"Company of Heroes 2: The Western Front Armies"**.

A join on `source_id` alone attributes Company of Heroes to Disney. That is a royalty error,
and it is not hypothetical — it is 105 rows waiting to happen. **Any future loader must key on
`(source_system, source_namespace, source_id)`.**

The namespace half matters too, not only the system half: `plm.wb_property` carries the same
UUID under **two** namespaces, `warner_art_assets` and `warner_product_catalogue` (e.g.
`79c6d511-…` appears as both for "Conjuring, The (2013)"). `(system, id)` without namespace
double-counts Warner; `(system, namespace, id)` does not.

`core.property` has **no** source-id column at all, so name is the only bridge available
today. That is a limitation of the comparison, stated plainly, not a claim that names are a
good key.

---

## 3. Per-licensor reconciliation

Denominator is **distinct normalised source names** (source rows repeat: Warner's 525 rows
carry only 234 distinct names; Paramount's 134 rows carry 67).

| Portal | distinct source names | matched to `core.property` | in source, not in ours |
|---|---|---|---|
| Disney OPA | 1,517 | 25 | **1,492** |
| Warner STARLABS | 234 | 9 | **225** |
| Paramount | 67 | 9 | **58** |
| NBCU | 237 | 20 | **217** |

And the other direction — `core.property` rows found in **none** of the four extracts:

| core licensor | core properties | found in some extract | **core-only** |
|---|---|---|---|
| `WB` WARNER BROS | 41 | 9 | 32 |
| `DY` DISNEY | 40 | 16 | 24 |
| `NB` NBC | 31 | 20 | 11 |
| `MV` MARVEL | 29 | 6 | 23 |
| `SW` STAR WARS | 28 | 1 | 27 |
| `VM` VIACOM MULTI | 23 | 10 | 13 |
| `DC` DC | 14 | **0** | 14 |
| `HP` HARRY POTTER | 12 | **0** | 12 |

`DC` and `HP` scoring zero against a *property* comparison, while 11 of 14 `DC` rows match
Warner's *character* catalogue, is the level mismatch in one line.

---

## 4. Disagreements, by category, with named examples

### 4.1 Cross-licensor attribution disagreement — 9 rows

Disney OPA asserts these properties; `core.property` files them under a different licensor.
All 9 come from Disney OPA; Paramount, NBCU and Warner produced **none**.

| Source id | Source (Disney OPA) says | `core.property` row | core code | core licensor |
|---|---|---|---|---|
| 206 | Blaze | BLAZE | `BZ` | **`VM` VIACOM MULTI** |
| 1159097950 | Peanuts | PEANUTS | `UT` | **`PN` PEANUTS WORLDWIDE** |
| 1000 | Guardians of the Galaxy | GUARDIANS OF THE GALAXY | `GG` | `MV` MARVEL |
| 628 | Iron Man | IRON MAN | `RM` | `MV` MARVEL |
| 635 | Spider-Man | SPIDER MAN | `SP` | `MV` MARVEL |
| 637 | Venom | VENOM | `VN` | `MV` MARVEL |
| 639 | Wolverine | WOLVERINE | `WR` | `MV` MARVEL |
| 640 | X-Men | X-MEN | `XM` | `MV` MARVEL |
| 1159089281 | The Mandalorian | THE MANDALORIAN | `MD` | `SW` STAR WARS |

**Two distinct things are in that table and they must not be reported as one number.**

- **7 rows (Marvel, Star Wars) are the sub-brand split of §1**, not errors. Disney's portal
  legitimately carries Marvel and Star Wars; our data files them under sibling licensors.
- **2 rows are genuine, and both are name collisions across unrelated rights holders.**
  `Blaze` — Disney OPA id 206 versus core `BZ` under Viacom; "Blaze and the Monster Machines"
  is a Nickelodeon/Viacom title, so this looks like two different Blazes sharing a name.
  `Peanuts` — Disney OPA id 1159097950 versus core `UT` under Peanuts Worldwide.
  **These two are the owner decisions.** Neither can be settled from the extracts alone;
  both need the contract.

### 4.2 Present in a source extract, absent from `core.property` — 1,992 names

Largest category by far, and mostly *expected*: the extracts are the licensors' catalogues,
`core.property` is our licensed subset. Named examples, Warner STARLABS:

- `Conjuring 2, The (2016)` — `warner_art_assets` / `warner_product_catalogue`,
  id `5920496d-31d2-4487-a584-7ecb941aee91`
- `Looney Tunes Show, The: Animated Series (2011)` — id `91cc56b1-954b-4281-ae9e-c2cdfcd311e4`
- `WB 100: Looney Tunes Mashups` — id `cfdc27f0-a15f-4254-87c4-9bf96b14ebe2`
- `Gokko x Wizard of Oz, The (1939)` — id `f85a1d83-46ea-4859-86c1-01ff1ee24b2e`

**Do not read 1,992 as a gap to be filled.** It is the size of the licensors' catalogues
relative to ours, plus the naming noise in §5. It is not a work item.

### 4.3 Present in `core.property`, absent from every extract — 197 rows

Named examples, split by what they appear to be:

*Character-level rows filed as properties (the level mismatch, §0):*
`BATMAN` `BM` / DC · `SUPERMAN` `SM` / DC · `HARLEY QUINN` `HQ` / DC · `WONDER WOMAN` `WW` / DC ·
`HERMIONE` `HR` / HP · `DUMBLEDORE` `DD` / HP · `VOLDEMORT` `VT` / HP ·
`CHEWBACCA` `CB` / SW · `DARTH VADER` `DV` / SW · `BB-8` `B8` / SW ·
`THANOS` `TN` / MV · `GROOT` `GR` / MV · `HULK` `HU` / MV

*Genuine property-level rows our data has and the extracts do not:*
`GAME OF THRONES` `GT` / WB · `FRIENDS` `FN` / WB · `SEINFELD` `SN` / WB ·
`LORD OF THE RINGS` `LR` / WB · `RICK & MORTY` `RK` / WB · `TED LASSO` `TL` / WB ·
`JURASSIC WORLD/JURASSIC PARK` `JR` / NB · `WICKED PART I` `W1` / NB · `SCARFACE` `SF` / NB ·
`CURIOUS GEORGE` `CG` / NB · `SPONGEBOB` `SB` / VM · `GARFIELD` `GE` / VM ·
`NINJA TURTLES GROUP` `NT` / VM (with `DONATELLO` `DN`, `LEONARDO` `EN`, `RAPHAEL` `RA`,
`MICHAELANGELO` `MA` as separate rows — character level again)

*Confirmed structural gap named in the issue:* `core.property` has **zero** rows with code
`EX` and zero rows named like Exorcist, while `plm.wb_property` carries **3** Exorcist labels.
Positive control on the same query shape: `core.property` names like `%batman%` returns **2**,
so the query can and does return non-empty — the Exorcist zero is a real absence.

### 4.4 Zero stored resolutions — the whole comparison is unbacked

`plm.opa_property`, `plm.pmt_property` and `plm.nbcu_property` each carry a
`core_property_id` + `resolution_status` pair designed to hold exactly this reconciliation.

**All 1,901 rows across the three tables are `resolution_status = 'unresolved'` with
`core_property_id IS NULL`. Not one resolution has ever been recorded.**
(Disney OPA 1,518 · NBCU 249 · Paramount 134.)

Positive control: the same query grouped by status returned those three non-empty rows, so
the empty resolution join is a real zero, not a broken query.

`plm.wb_property` has **no** `core_property_id` column at all — Warner cannot record a
resolution even if one were decided. That is a structural gap, and closing it is a schema
change under the ordinary orchestrator route, not this workstream.

---

## 5. Naming conventions that inflate the "missing" counts

**Warner writes labels in sort order.** `Conjuring, The (2013)`, `Looney Tunes Show, The:
Animated Series (2011)`, `Wizard of Oz, The (1939)` — trailing article, not leading. A
normaliser that strips only a leading article scores every one of these as missing.
Correcting for it moved Warner's matches from **5 to 9** on a 234-name denominator, i.e. it
was overstating Warner's gap by nearly half of its true matches. Any future matcher must
handle the trailing-article form.

Other conventions observed: Paramount and NBCU mix case freely (`DORA` vs `Minions`); NBCU
uses both `MINIONS` (id 2576) and `Minions` (id NULL) for the same title; punctuation differs
routinely (`KUNG FU PANDA` vs `KUNG-FU PANDA`, `E.T.: THE EXTRA-TERRESTRIAL` vs
`E.T. THE EXTRATERRESTRIAL`). All of these matched only because punctuation was stripped.

---

## 6. What I could NOT determine

1. **Whether the 2 genuine disagreements are wrong.** `Blaze` and `Peanuts` need the contract,
   not the extracts. Owner decision.
2. **Whether the Marvel / Star Wars / DC / Harry Potter licensor split is intended.** It is
   consistent across all 260 core rows, which reads as deliberate, but nothing in the database
   records the intent. Owner decision, and it changes what "correct attribution" even means.
3. **Anything about fuzzy matches.** Exact-key matching only. Titles that differ by more than
   punctuation and articles are counted as non-matches. The real agreement number is
   **at least** 63 and could be materially higher. I did not estimate how much higher.
4. **Whether a source-only name is genuinely unlicensed to us**, or licensed and simply never
   entered into `core.property`. The extracts cannot distinguish these.
5. **Sega.** `plm.sega_property` (440 rows) matched **zero** `core.property` names on the exact
   key, against 3 `SE` core rows. Sega is outside #640's four, and I did not chase it; the zero
   is reported only so nobody reads it as "checked and clean". It is unexplained.
6. **Which `core.property` rows are hand-curated.** Nothing in the database records which
   fields a human set (the §6.4 problem). So I cannot say whether a disagreement overrides a
   human ruling — which is precisely why none of this may be auto-applied.
7. **Warner franchise-level agreement.** `plm.wb_franchise` has 8 rows and
   `plm.wb_franchise_property_evidence` exists, but per #640 only the Product
   Property-to-Character catalogue is a direct Warner record. I did not use franchise evidence
   for attribution, and Paramount's `pmt_property_franchise_evidence` was excluded for the same
   reason — co-occurrence is forbidden by #640 §1.

---

## 7. Method, reproducible

All figures come from read-only SQL against production `qsllyeztdwjgirsysgai` on 2026-09-03.
The comparison key is:

```sql
nullif(regexp_replace(
  regexp_replace(
    regexp_replace(lower(name), '^(the|a|an)\s+', ''),   -- leading article
    ',\s*(the|a|an)\s*(\(|$)', '\2'),                    -- Warner trailing article
  '[^a-z0-9]', '', 'g'), '')
```

Source tables used, direct records only, no inferred or co-occurrence links:
`plm.opa_property`, `plm.wb_property`, `plm.pmt_property`, `plm.nbcu_property`, with
`plm.wb_franchise`, `plm.wb_character_normalized` and `plm.opa_property_character` used only
to characterise the level mismatch in §0 and §4.3.

Every "nothing found" claim in this document is paired with a positive control that returned
rows on the same query shape.
