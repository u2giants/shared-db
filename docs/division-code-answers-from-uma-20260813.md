# Division codes: Uma's answers (2026-08-13)

**Answered by:** Uma (developer), with owner rulings from Albert Hazan.
**Verified against:** production Supabase `qsllyeztdwjgirsysgai` (read-only),
DesignFlow Cloud SQL `designflow."divisionCode"`, the DesignFlow item UI, and the
`designflow-data-syncing` sync code. Nothing was changed.

Questions asked in [`division-code-questions-for-uma.md`](division-code-questions-for-uma.md).

---

## Owner rulings (binding)

1. Only three live divisions: `CW001`→1, `SP001`→8, `EH001`→9.
2. DesignFlow id **2 is deprecated** (old Everyday code, not in use).
3. Company code is **`EDGEHOME` only**.
4. `plm."divisionCode"` / DesignFlow `divisionCode` is maintained **by DesignFlow**,
   not by ColdLion.

## Live mapping

| ColdLion | DesignFlow id | Name | Active |
|---|---|---|---|
| `CW001` | 1 | POP Lic | yes |
| `SP001` | 8 | Spruce Lic | yes |
| `EH001` | 9 | Spruce non-Lic | yes |

Ids 2 (Gen / Everyday) and 7 (POP Lic duplicate) also point at `CW001` in the bridge
table, but 2 is deprecated and 7 is unused. **They must not be treated as live
divisions.** With those excluded, the reverse map ColdLion→DesignFlow is unique.

Bridge table as it stands (source: DesignFlow `designflow."divisionCode"`, mirrored as
`plm."divisionCode"`):

| divCode_id | divCode_code | division_name | company_name_fk | external_divisoncode | is_divcode_active |
|---|---|---|---|---|---|
| 1 | Lic | POP Lic | EDGEHOME | CW001 | true |
| 2 | Gen | Everyday | EDGEHOME | CW001 | null (deprecated) |
| 7 | POP Lic | POP Lic | EDGEHOME | CW001 | null (unused) |
| 8 | Spruce Lic | Spruce Lic | EDGEHOME | SP001 | true |
| 9 | Spruce non-Lic | Spruce non-Lic | EDGEHOME | EH001 | true |

ColdLion also has a fourth division, `EP001`, with no DesignFlow row (see Q4).
The column-name typo `external_divisoncode` (missing "i") is real.

---

## Q1. Is `external_divisoncode` maintained by a process, or hand-entered?

Maintained **in DesignFlow**, not by ColdLion. It is a DesignFlow lookup/seed value on
DesignFlow's `divisionCode` table (mirrored to `plm."divisionCode"`). The ColdLion
item/merch sync does not read it at runtime — it uses a **hardcoded map** in
`designflow-data-syncing/helpers/utility.js`: `CW001`→1, `SP001`→8, `EH001`→9. No job
refreshes the table from ColdLion. If the mapping ever changes, DesignFlow updates the
table **and** the sync hardcode must be changed to match.

## Q2. Ids 1, 2 and 7 all map to CW001. Which are live?

**Only id 1.** The live DesignFlow set is exactly 1, 8, 9. Always reverse-map `CW001`
to 1.

| Id | Status | Why |
|---|---|---|
| 1 | Live | POP Lic — UI, sync, `is_divcode_active = true` |
| 2 | Deprecated | Old Everyday code; owner ruling: not in use |
| 7 | Not live | Duplicate POP Lic label; 0 merchGroup rows |

## Q3. Are 2 and 7 deprecated, and why is the flag NULL?

Yes — 2 is deprecated, 7 is unused. NULL means the flag was **never set historically**;
it is not a deliberate false and does not mean active.

- Filter with `is_divcode_active = true` only (keeps 1, 8, 9).
- Do **not** use `IS NOT FALSE` — that would keep 2 and 7.
- Later cleanup: set `is_divcode_active = false` on ids 2 and 7.

## Q4. Does DesignFlow know about `EP001`?

**No.** There is no `divisionCode` row for it. Sync pulls only `CW001`, `SP001`, `EH001`
and skips unrecognized codes; the frontend only knows 1 / 8 / 9. In `EP001`, ColdLion
type codes mean different things (`MG05`/`MG06` = Product Line / Product Type, not
Licensor / Property), so treating `EP001` like `CW001` would turn product lines into
licensors. Out of scope for DesignFlow item keys today.

## Q5. Text or integer — which is authoritative?

DesignFlow's live identity is the **integer** (1 / 8 / 9): items use
`dflow."itemHeader".div_code_fk`, merch uses `divisionCode_id_fk`, UI constants are
1 / 8 / 9. The text column is the ColdLion-style copy.

For the 271 contradicting `core."merchGroup"` rows (of 3,645 total; 3,553 with both
columns populated):

| Block | Text says | Integer says | Integer really means | Rows | Fix |
|---|---|---|---|---|---|
| A | `EH001` | 2 | deprecated Everyday / CW001 | 217 | Trust text → set integer to **9** |
| B | `CW001` | 8 | Spruce Lic / SP001 | 54 | Trust integer → set text to **SP001** |

Worked example, all sharing MG01 code `0` ("OTHER"):

| mg_id | text | integer | Meaning | Verdict |
|---|---|---|---|---|
| 22 | CW001 | 1 | POP Lic | clean, leave alone |
| 455 | EH001 | 2 | text = Spruce non-Lic; int = deprecated | trust text → id 9 |
| 888 | CW001 | 8 | text = POP Lic; int = Spruce Lic | trust integer → text SP001 (clean POP Lic row already exists as mg_id 22) |

## Q6. Does the DesignFlow item record carry a division?

Yes: `dflow."itemHeader".div_code_fk`, DesignFlow integer (1 / 8 / 9). About 19,461 of
19,463 item headers have it set. `public.erp_items_current.division_code` is NULL on all
17,703 rows because division was dropped on the way in, not because DesignFlow lacks it.
**Backfill from `itemHeader.div_code_fk`.** Worked example: `BRT10DYWP01` has
`div_code_fk = 1`, so ColdLion division = `CW001`.

## Q7. Is EDGEHOME the only company code?

**Yes.** Matches `divisionCode.company_name_fk`, ColdLion tenant usage, and the owner
ruling. `itemHeader.compan_code_fk` is stored as an integer (1 = EDGEHOME); mirror rows
that are null or 2 ("OTHER") are data quality, not extra companies. The item-key company
component is `EDGEHOME`.

## Q8. Does DesignFlow division 1 come back from ColdLion as CW001?

**Yes.** 1 = `CW001`, 8 = `SP001`, 9 = `EH001`. Worked example: `BRT10DYWP01` has
`div_code_fk = 1`, so ColdLion `/items` should return `companyCode = "EDGEHOME"`,
`divisionCode = "CW001"`. One live API call settles any remaining doubt.

---

## One-line summary

Two encodings of the same real divisions, joined by
`divisionCode.external_divisoncode` plus a matching hardcoded sync map. With owner
rulings applied the live set is only 1↔CW001, 8↔SP001, 9↔EH001, company `EDGEHOME`,
id 2 is dead, and the 271 merchGroup conflicts have a clear fix rule. Building
`company | division | item_no` is safe **after** the conflict fixes and the
`erp_items_current` division backfill.

## Agreed next steps (pending Albert's go-ahead per item)

1. **Canonical encoding for new item keys:** ColdLion shape —
   `EDGEHOME | CW001|SP001|EH001 | item_no` — translating DesignFlow ids only through
   the 1 / 8 / 9 map.
2. Never accept `"1"` / `"8"` / `"9"` or deprecated `"2"` as `division_code` in shared
   PLM item tables.
3. Fix the 271 `core."merchGroup"` rows using the Q5 rules (217 → integer 9;
   54 → text `SP001`).
4. Backfill `public.erp_items_current.division_code` from `itemHeader.div_code_fk`.
5. Later shared-db PR: `CHECK` constraint or domain so only ColdLion-shaped division
   codes are accepted.
