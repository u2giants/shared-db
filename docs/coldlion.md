# ColdLion — start here

**This page is a map, not a source.** It holds no facts of its own, so it cannot go stale
except by a broken link. Everything ColdLion lives in the documents below. Read this page
first, then go to the one you need.

**Last reviewed: 2026-09-01.**

---

## Before you ask ColdLion anything

> ### ⛔ Read [`coldlion-open-questions.md`](coldlion-open-questions.md) FIRST.
>
> It is the single register of every question we have asked ColdLion, every answer they
> have given, and everything still outstanding. **Twelve questions are already answered
> there.** Check it before drafting a question, before concluding a field is broken, and
> before telling Albert something is unknown.
>
> **This is not optional advice.** On 2026-08-19 a session spent an afternoon measuring
> two always-zero quantity fields and drafted a question to ColdLion about them. That exact
> question had been answered on 2026-08-18 and was sitting in §4 of the register. The
> session had read four ColdLion documents and none of them pointed here. That is why this
> page exists.

**Who answers, and how.** ColdLion is a third-party ERP that Albert does **not**
administer. Questions go **from Albert**, never sent by an AI session:

| Topic | Contact |
|---|---|
| API behaviour, fields, data meaning | **JamieLynn** |
| Division and company codes | **Uma** |
| Whether we even want to ask | **Albert** (some register entries are owner decisions, not ColdLion questions) |

---

## Field dispositions — what is settled and what is not

> ### ⛔ SETTLED — `/vendors` field dispositions are RULED. Do not re-open them.
>
> **All 29 `/vendors` fields were ruled by the owner on 2026-08-19** in
> [`coldlion-field-decisions-20260819.csv`](coldlion-field-decisions-20260819.csv):
> **10 ingest, 19 DECLINED.** The ruling was **re-verified against the live feed on
> 2026-09-03** — the live field-name set is **identical** to the CSV's 29 rows, so the
> August ruling applies in full and nothing about it is stale.
>
> **DECLINED (ruled out — not pending, not undisposed):** `address1`, `address2`,
> `address3`, `zipCode`, `state`, `email`, `phoneNo`, `faxNo`, `createdUser`, `modUser`,
> `udf01`–`udf04`, `udfDate01`, `udfDate02`, `payTermCode`, `glCode`, `separateCheck`.
> Vendor **addresses, zip, state, email and phone are DECLINED**. Never describe any of
> these as pending, undisposed, or an open owner decision, and never re-ask Albert for them.
>
> **`/seasons` is now ALSO ruled** — see the next block. Issues #2180 and #2081 were written
> as though no `/vendors` ruling existed; they are wrong on that point, and #2180's
> owner-decision blocker is fully resolved.

> ### ⛔ SETTLED — `/seasons` field dispositions are RULED (2026-09-03). Do not re-open them.
>
> **All eight currently-unstored `/seasons` fields are DECLINED** by owner ruling on
> **2026-09-03**: `seasonDesc`, `startDate`, `endDate`, `shipStartDate`, `shipEndDate`,
> `active`, `createdUser`, `modUser`. **Nothing new is to be added to `coldlion.season`.**
> The five stored columns — `company_code`, `division_code`, `season_code`, `created_time`,
> `mod_time` — stand as the **complete approved projection**.
>
> Evidence, from a full live read of all 21 of 21 rows on 2026-09-03: `seasonDesc` merely
> repeats `seasonCode` on every row except `NONE`, whose description is empty; all four date
> fields are the `1900-01-01` empty-date sentinel on every row; `active` carries the same
> single value on every row; and `createdUser` / `modUser` are ColdLion record-audit stamps
> naming one internal staff login, identical to each other on every row — personal data about
> a named individual, which we do not land.
>
> Never describe any of these eight as pending, undisposed, or an open owner decision, and
> never re-ask Albert for them. **Revisit only if ColdLion begins populating them.**

> ### ⛔ VENDOR DEFECT — the unfiltered `/seasons` call DROPS 13 of the 21 records. Never use it.
>
> **The other divisions' records are MISSING, not mislabelled.** A company-wide (unfiltered)
> `/seasons` query returns the **CW001 record in place of every other division's record
> entirely** — division code, description, `createdUser`, `createdTime`, `modUser` and
> `modTime` all come from the CW001 row. **All 13 non-CW001 records (4 SP001, 1 EP001,
> 8 EH001) are ABSENT from the response.**
>
> The row *count* is correct — 8 + 4 + 1 + 8 = 21 — but the row *content* is duplicated from
> CW001: each affected season code is repeated three or four times, and each repetition is
> byte-identical. It reads as a lookup keyed on `seasonCode` alone, ignoring division.
>
> **There is no workaround.** A loader author who reads "mislabelled" might think the division
> code can be re-derived from elsewhere and the response otherwise trusted. It cannot: the
> other divisions' data is simply not in the response. **Any `/seasons` loader MUST query per
> division and MUST NEVER use the unfiltered call.**
>
> The failure is silent: nothing in the response envelope signals it, the response looks
> complete and well-formed, and paging is not involved (single page, 21 of 21, page size 50).
>
> Confirmed against the live feed on **2026-09-03**, from a full 21-of-21 read re-verified
> three times, with a positive control that fires — so the check can fail and is trustworthy.
>
> **This is a `/seasons` fault, not how their API is designed to behave.** For contrast,
> unfiltered `/merchGroupHeaders?companyCode=EDGEHOME` returns 37 rows correctly spanning all
> four division codes.

---

## What ColdLion is

The ERP that runs the business day to day: what we sell, what we bought, what it cost, who
we bought it from, who we sold it to. Base URL `http://x5.coldlion.com/EhpApi`, tenant
`companyCode=EDGEHOME`. We are a client of it, not its owner — we cannot change its schema,
and it has changed shape on us three times in a month.

Credentials: 1Password vault `vibe_coding`, item *"Coldlion ERP API key x5.coldlion.com"*,
field `credential`. Header `X-API-Key`. **A missing key returns HTTP 400, not 401.**

**Do not ask Albert to rotate the ColdLion API key.** He does not administer ColdLion.
Owner ruling 2026-08-09.

---

## The map

### How the API behaves
| Document | What it answers |
|---|---|
| [`coldlion-erp-api-reference.md`](coldlion-erp-api-reference.md) | Every endpoint, its parameters, paging, auth, the division matrix, which four endpoints are writable |
| [`coldlion-history-endpoints-shape.md`](coldlion-history-endpoints-shape.md) | The two history feeds in depth: the 7-day window cap, row identity, the malformed error contract, dead fields |
| [`business-rules-erp-data.md` §10](business-rules-erp-data.md) | **Read before building any order-history loader.** How one prepack line explodes into one row per SKU, which quantity fields are per-SKU and which are parent totals, and the four-part natural key |
| [`coldlion-answers-20260826.md`](coldlion-answers-20260826.md) | ColdLion's 2026-08-26 answers, each verified live: `salesOrderLineNo` and `stageCode` are now IN the API, the report formulas are applied, `orderHistory` has no hidden dimension — and the one question ColdLion asked us back |
| **The live spec** — `GET /EhpApi/v2/api-docs` | The final authority when a document and reality disagree. It has been right and our docs wrong at least once |

### What the data means to the business
| Document | What it answers |
|---|---|
| [`business-rules/erp-orders-and-source-meaning.md`](business-rules/erp-orders-and-source-meaning.md) | Order history, production history, `COS`, contractual samples, ERP code meaning |
| [`business-rules/merchandise-and-product-taxonomy.md`](business-rules/merchandise-and-product-taxonomy.md) | Merch groups, `mgCategory`, product types, the divisions and what each sells |
| [`merch-group-taxonomy-architecture.md`](merch-group-taxonomy-architecture.md) | Why `mgTypeCode` cannot be hardcoded — its meaning changes per division |
| [`business-rules/application-map.md`](business-rules/application-map.md) | The front door to all companywide business rules |

### What we are building
| Document | What it answers |
|---|---|
| [`plan_coldlion-landing-phases-2-6.md`](plan_coldlion-landing-phases-2-6.md) | Historical phase plan and owner-decision record; execution assumptions are superseded by the completion plan below. |
| [`../plan_coldlion_landing_schema_completion.md`](../plan_coldlion_landing_schema_completion.md) | Current completion/correction plan after the 2026-09-02 live-schema and current-API audit. **Read its STATUS table first** |
| [`coldlion-field-decisions-20260819.csv`](coldlion-field-decisions-20260819.csv) | Albert's per-field ingest/ignore decision for all eight feeds. **Owner authority, not a suggestion** |
| [`coldlion-raw-landing-schema-design.md`](coldlion-raw-landing-schema-design.md) | The landing-layer design, grain by grain. Carries dated supersession notes — read them |
| [`coldlion-source-of-truth-plan.md`](coldlion-source-of-truth-plan.md) | Making ColdLion authoritative for the `core.*` master tables |
| [`coldlion-direct-sync-and-taxonomy-plan.md`](coldlion-direct-sync-and-taxonomy-plan.md) | The "Option B" direct-sync architecture decision |

### History and evidence
| Document | What it answers |
|---|---|
| [`coldlion-erp-to-supabase-field-mapping.md`](coldlion-erp-to-supabase-field-mapping.md) | Field-by-field mapping into our schema |
| [`coldlion-customer-dedupe-review.md`](coldlion-customer-dedupe-review.md) | Customer duplicate analysis |
| [`coldlion-unmatched-properties-by-licensor-20260731.md`](coldlion-unmatched-properties-by-licensor-20260731.md) | The 66 unmatched property codes behind register question 2.5 |
| [`verification/`](verification/) | Measured evidence from past sessions. Cite these rather than re-measuring |

---

## The five traps that have already cost us

Each of these was learned the expensive way. They are stated in full in the documents
above; this list exists so you recognise one before it costs you the same afternoon.

1. **`mgTypeCode` has no fixed meaning.** `05` is Licensor in `CW001`/`SP001`, "Big Theme"
   in `EH001`, "Product Line" in retired `EP001`. Keying on the number alone corrupts data.
2. **`mgCode` collides across types inside one division.** `1P` is both a licensor and a
   property in `CW001`. Identity is always `(division, mgTypeCode, mgCode)` — four parts
   with company. Never the code alone.
3. **ColdLion has no licensor-to-property link and no licence expiry flag.** Neither can be
   invented. A sync that assumes otherwise resurrects lapsed licences.
4. **The 7-day-cap refusal is malformed.** It arrives as **HTTP 400 on the wire** with
   `"status": 500` in the body. Branch on the wire status, or your loader will retry a
   permanent input error forever.
5. **A zero is not an absence.** Several fields return `0` rather than null, so a report
   sums them happily and shows a plausible wrong answer. Equally, a field measuring 0%
   populated is not necessarily dead — `subUpc` is empty by business practice and one real
   value would be meaningful.

---

## Adding to this page

Add a **link and one line saying what the document answers**. Never copy content here — a
map that restates its territory becomes a second source that disagrees with the first. If a
document is superseded, leave the row and mark it, so a reader who finds the old file also
finds the pointer.
