<!-- Authored by GLM 5.2 via ai-glm session orderlist-727-idempotent-import-design, 2026-08-11. Verified against scripts/import-order-list-xlsx.py at bdc556e. DESIGN ONLY - no migration, no database writes. -->

# PopDAM OrderList — idempotent one-time import design (issue #727)

- **Issue:** u2giants/shared-db#727 (PopDAM OrderList, migration Step 3)
- **Implementation under design:** `scripts/import-order-list-xlsx.py` (merged, PR #750) + `scripts/tests/test_import_order_list.py`
- **Schema it depends on:** `20260810010000_popdam_order_list_contract.sql`, `20260810060000_popdam_order_list_source_pair_nulls_distinct.sql`, `20260810100000_link_dam_order_line_cross_item_ambiguity.sql` (issue #613, object claim #624; all merged)
- **Target:** preview `rjyboqwcdzcocqgmsyel` only. Production `qsllyeztdwjgirsysgai` is refused unconditionally by the importer.
- **Status:** BLOCKED on an owner decision (§5). Everything in §1–§4 is settled and code-complete; only the physical run is held.

---

## 1. Scope and non-goals

**In scope.** Import the legacy Google `Order` tab (spreadsheet `1i1da5J0qy5a0EvsO1CvfyQ6Xijn4678LG7TFqbwxwUk`, tab `Order`, `gid=0`, 48 columns) **once**, idempotently, into the preview Supabase project. Prove idempotency by running the apply step a second time and showing zero changed rows. Commit a secret-free reconciliation report.

**Non-goals.**
- Production is out of scope. There is no `--production` flag; the importer refuses the production ref in `assert_preview_target`.
- No reconciliation of Google vs. Coldlion rows. Per the profile, no Google-only business tuple is a universal Coldlion key; that design waits for a real Coldlion production-order payload sample.
- No fuzzy Master Data matching, no first-of-duplicates, no quantity derivation for assortment components.
- No `plm.item` population. The importer never writes `plm.item`, `plm.style_tracker_item_bridge`, or any `core.*` table (confirmed in the migration header and in `load_master_data_catalog`, which is SELECT-only).
- No re-design of the checksum gate, no auto-update of the approved checksum, no source reconciliation. Which workbook is authoritative is the owner's call (§5).

---

## 2. The four idempotency answers

This is the core. Every claim below is cited to the function or constraint that enforces it in `scripts/import-order-list-xlsx.py` and the three migrations.

### 2a. What is the natural key?

The importer addresses **every** canonical row by a deterministic Google source reference built from the physical sheet row (column `AQ` "Order Tab Line#" is unusable: one `#REF!`, 12,327 blanks). The three generator functions are:

| Thing written | Generator function | Natural-key form |
|---|---|---|
| Order header (real PO) | `header_source_id(po, row)` | `order:po:<normalized-po>` |
| Order header (blank PO) | `header_source_id(None, row)` | `order:row:<sheet-row>` — each of the 130 blank-PO rows gets its own header, so unrelated blanks never merge |
| Direct order line | `line_source_id(row)` | `order:row:<sheet-row>` |
| Assortment component line | `component_source_id(row, ordinal)` | `order:row:<sheet-row>:component:<1-based-ordinal>` |

All are written under the single source-system constant `SOURCE_SYSTEM = "google_order_list"`. The composite `(source_system, source_id)` is the natural key, enforced at the database by two UNIQUE constraints created in `20260810010000`:

- `plm.production_order_source_ref … constraint production_order_source_ref_unique unique (source_system, source_id)`
- `plm.production_order_line_source_ref … constraint production_order_line_source_ref_unique unique (source_system, source_id)`

Plus two partial unique indexes that guarantee at most one PRIMARY identity per canonical row per source system:
- `production_order_source_ref_primary_uidx on (production_order_id, source_system) where is_primary`
- `production_order_line_source_ref_primary_uidx on (production_order_line_id, source_system) where is_primary`

The importer always inserts the Google ref with `is_primary = true` (`PostgresGateway.insert_order` / `insert_line`).

The canonical tables `plm.production_order` and `plm.production_order_line` carry a legacy single `(source_system, source_id)` pair from `20260621151024`. The importer does **not** set that pair on canonical rows — it leaves it NULL and writes identity into the source-ref tables only. This is only legal because `20260810060000` rebuilt both legacy constraints as **NULLS DISTINCT**; see risk R2.

### 2b. What happens on re-run?

`apply_plan` is the single write path. For each row it calls `gateway.order_id_for_source` / `line_id_for_source`, which (in `PostgresGateway`) resolve the existing canonical id by `select … from plm.production_order[_line]_source_ref where source_system = 'google_order_list' and source_id = %s`. Three outcomes:

| Existing ref? | Payload comparison (`payload_differs`) | Action | Counter |
|---|---|---|---|
| No | — | INSERT canonical row + INSERT source_ref (`on conflict do nothing`) | `orders_inserted` / `lines_inserted` |
| Yes | identical (`canonical()` of every owned field matches) | DO NOTHING | `orders_unchanged` / `lines_unchanged` |
| Yes | drifted (one or more owned fields differ) | DO NOTHING by default; counted + added to `drift_details` | `orders_drifted` / `lines_drifted` |

`--replace-source` flips the drift branch from "do nothing" to `gateway.update_order` / `update_line`. It is **preview-only**: `main` refuses it unless `--preview` is set, and the parser exposes no production mode. After a `--replace-source` rewrite, a third run without drift is again a no-op (proven by `test_replace_source_rewrites_only_when_asked`).

The `canonical()` comparator is what makes "identical" meaningful: `Decimal('5')` equals `Decimal('5.0')`, `date(2026,1,1)` equals `'2026-01-01'`, and dict key-order differences in `metadata` are ignored. Without it, formatting noise would make every second run rewrite every row.

**Quarantined orders are never written.** `apply_plan` pre-computes `orders_skipped_quarantined` and `lines_skipped_quarantined`; `writable_orders()` and `writable_lines()` exclude quarantined orders and any line whose `order_source_id` is blocked. A quarantined order is one whose header identity columns (`A` PO status, `C` order vendor, `H` vendor id, `I` company, `L` customer) disagree across its rows (`HEADER_IDENTITY_COLUMNS` in `build_plan`). First-wins and majority-wins are both explicitly forbidden (`test_no_first_wins_and_no_majority_wins`).

### 2c. What happens on partial failure?

**Batch boundary.** `apply_plan` chunks orders into batches of `batch_size` (default `DEFAULT_BATCH_SIZE = 500`), then chunks lines into batches of the same size. Each batch is one transaction:
- `gateway.begin_batch()` → try the chunk → `gateway.commit_batch()`, or on any exception `gateway.rollback_batch()` then re-raise.
- In `PostgresGateway`, `begin_batch` is a no-op on an `autocommit=False` connection, `commit_batch` is `connection.commit()`, `rollback_batch` is `connection.rollback()`. So one batch = one Postgres transaction.

**Ordering.** All order batches are committed before any line batch starts. Lines resolve their parent order from the in-run `order_ids` map first, falling back to a fresh `order_id_for_source` lookup; if neither finds an order the importer raises `ImporterError("Refusing to create an orphan line …")` rather than writing a line with no header.

**What is left behind on a mid-run crash.** Every batch that already committed stays committed; the failing batch is rolled back whole; nothing after it runs. This is per-batch atomicity, exactly the §5.1-A / issue #611 shape but at the 500-row batch rather than the migration-file level — a mid-run failure leaves a prefix of the import applied, not an all-or-nothing result.

**Is a resumed run safe?** Yes, because of 2a/2b. Re-running the same command re-locates every already-written row by source ref: committed rows come back `unchanged`, the failed batch is re-attempted as `inserted`, quarantined/rejected rows are skipped again. The balance checks (2d) are derived from the source `plan`, not from the DB, so they still hold on a resume. The only operational nuance: on a resume, the report's "inserted" column reflects only what this run wrote, not the cumulative total — committed rows show as `unchanged`. The `--verify-idempotency` second run is still expected to report zero changes because by that point every source ref exists.

### 2d. How is the row count verified after load?

The report **asserts**, it does not print-and-hope. Two layers:

**Layer 1 — `Reconciliation.balance_checks()` returns `(name, passed, detail)` tuples.** Two checks always fire:

1. `staged_rows == rows_direct + rows_assortment + rows_both + rows_neither`
2. `sum(match_matched, match_unmatched, match_ambiguous, match_manual, match_not_applicable) == planned_lines`

Eight more checks fire **only when the workbook SHA-256 equals `APPROVED_SOURCE_SHA256`** (`checksum_matched_approved_source=True`), asserting the run against the frozen `ReconciliationBaseline`:

| Baseline field | Asserted value |
|---|---:|
| `populated_rows` | 12,328 |
| `direct_only_rows` | 8,412 |
| `assortment_only_rows` | 3,899 |
| `both_shape_rows` | 3 |
| `neither_shape_rows` | 14 |
| `assortment_components` | 15,816 |
| `blank_po_rows` | 130 |
| `normalized_po_numbers` | 3,083 |

**Layer 2 — `main()` treats balance as a hard gate.** After writing the report, `if not reconciliation.balanced(): raise ImporterError("Reconciliation did NOT balance …")`. The process exits non-zero. A synthetic 12-row fixture is proven to **fail** this gate (`test_phase0_baseline_checks_only_fire_for_the_approved_workbook`), so the baseline assertions cannot be silently passed by a wrong workbook.

**Layer 3 — idempotency is a hard gate when requested.** `--verify-idempotency` runs `apply_plan` a second time in the same process and `raise ImporterError` if `second.changed_rows != 0`. The rendered report then prints the literal line `the second identical run changed 0 business rows. PASS.` and an overall `BALANCED`.

The baseline dataclass also carries `structurally_invalid_assortment_rows = 10` and `ambiguous_matches = 449`, and the report prints those counters — but `balance_checks` does **not** assert either against the baseline today. See open question O1.

---

## 3. Exact database object list for the anti-collision gate

**The implementation creates NO schema objects and creates/replaces NO functions, views, triggers, policies, indexes, types, or constraints.** All DDL for this feature was authored in issue #613 / object claim #624 and is already merged in the three migrations above. The importer is a row-writing batch loader, not a migration.

Consequently the `scripts/check-dispatch-collision.mjs` object list is empty in the DDL sense. Be aware of the checker's known limit (AGENTS.md §4 rule 1): it models only `function/procedure/view/materialized view/trigger/policy` and is blind to table-row writes. A clear result here is therefore expected; it is not proof that two importers cannot both write the same rows. The real guard against that is the single-orchestrator discipline, not the checker.

For completeness, the tables the importer writes **rows** to (all created by the merged migrations; "rows only, no DDL"):

| Table | Operation | Notes |
|---|---|---|
| `plm.production_order` | INSERT / UPDATE of importer-owned columns (`ORDER_COLUMNS`) | Legacy `(source_system, source_id)` left NULL; identity lives in the ref table |
| `plm.production_order_source_ref` | INSERT (`on conflict do nothing`, `is_primary=true`) | Enforces the header natural key |
| `plm.production_order_line` | INSERT / UPDATE of importer-owned columns (`LINE_COLUMNS`) | `master_data_match_status` always set; `item_id` always NULL today |
| `plm.production_order_line_source_ref` | INSERT (`on conflict do nothing`, `is_primary=true`) | Enforces the line/component natural key |

Tables it **reads only** (no writes): `plm.production_order_source_ref`, `plm.production_order_line_source_ref` (existing-row lookup), `plm.production_order`, `plm.production_order_line` (current-payload read for drift), `public.style_tracker_rows`, `plm.style_tracker_item_bridge` (builds the Master Data catalog in `load_master_data_catalog`).

The importer does **not** use the browser write RPCs `public.create_dam_order` / `update_dam_order` / `link_dam_order_line`. Those are the `SECURITY DEFINER`, `auth.uid()`-validated surface for PopDAM staff; the importer is a service-role batch loader that writes through the source-ref identity surface and stamps `source_system = 'google_order_list'` (distinct from `popdam_order_list` used by native creates, so an imported order can never be mistaken for a natively created one in reconciliation).

---

## 4. The run procedure

The importer enforces three preconditions itself: `main` refuses to run without `--dry-run` or `--preview`; `--replace-source` requires `--preview`; and on `--preview` it calls `assert_preview_target`, which reads `supabase/.temp/project-ref` and refuses anything other than `rjyboqwcdzcocqgmsyel` (production refused; missing file refused; unknown ref refused). This satisfies §4.2's "prove the target immediately before writing" for the importer's own writes. Runtime deps are `openpyxl` (workbook read) and `psycopg` (preview writes); neither is needed for the test suite.

**Step 0 — confirm the schema is live on preview.** Before any write, confirm the three migrations are applied on `rjyboqwcdzcocqgmsyel`, in particular `20260810060000` (NULLS DISTINCT — see R2) and `20260810100000` (the corrected `link_dam_order_line`). Verify real objects, not just the ledger row: check `pg_constraint` for the source-ref uniques and confirm `plm.production_order_source_ref` exists. This step is read-only and is the one genuine dependency check the importer cannot perform for itself.

**Step 1 — dry-run (writes nothing).**
```
python scripts/import-order-list-xlsx.py --workbook <approved.xlsx> --dry-run
```
Exercises the real `apply_plan` against `InMemoryGateway`, checks the workbook SHA-256, and writes a report whose balance table must read BALANCED. This proves the plan and the checksum before any connection is opened. It does **not** prove the live Master Data catalog.

**Step 2 — preview write with idempotency proof (writes once, then proves zero).**
```
python scripts/import-order-list-xlsx.py \
  --workbook <approved.xlsx> \
  --preview --database-url "$PREVIEW_DATABASE_URL" \
  --verify-idempotency
```
`--verify-idempotency` runs `apply_plan` twice in one process; the importer raises `ImporterError` if the second pass changes any business row, so a non-zero exit means idempotency failed and the report is still written for diagnosis. This is the single command that both loads the data and proves the load is a no-op to repeat. (Equivalent: run the command without `--verify-idempotency` twice manually; source-ref idempotency makes both approaches equivalent.)

**Step 3 — commit the evidence.** The importer writes the report to `docs/verification/popdam-order-list-preview-<YYYY-MM-DD>/README.md` by default (`--report-dir` overrides). The committed artifact must contain: the verified SHA-256, the destination project ref, the row-shape table, the orders/headers table, the Master Data resolution table, the writes table with both first- and second-run columns, the line `the second identical run changed 0 business rows. PASS.`, and the balance-checks table ending `BALANCED`. The report is secret-free by construction (`render_report` emits counts and deterministic source refs only; the leak test screens for customer/vendor/SKU strings and the production ref).

---

## 5. BLOCKED — the source-of-truth decision

**The blocker, plainly.** The approved source is the 2026-08-09 read-only export whose SHA-256 is the constant `APPROVED_SOURCE_SHA256 = 4958b4b7b783a46b968a0d5c9438364216303ad8b856b9b7e9aebbdffc6abbe4` and whose populated-row baseline is 12,328 (profile: "Source evidence"). The live sheet has since changed: the last session observed 12,323 populated rows and the workbook SHA-256 no longer matches. `assert_source_checksum` refused it — correctly. Which source is authoritative has **not** been answered by the owner.

**The two options the owner has.**
- **Option A — the approved 2026-08-09 export is authoritative.** Re-supply that exact file (SHA `4958b4b7…fc6abbe4`, 12,328 populated rows). No code change, no baseline change; the checksum gate passes as built and the §2d baseline assertions fire.
- **Option B — the current live sheet is authoritative.** This requires re-running the Phase 0 profile against the current export, an explicit owner-approved new SHA-256, and new `ReconciliationBaseline` numbers (note the row count already differs: 12,323 vs 12,328), then a code change to `APPROVED_SOURCE_SHA256` and `BASELINE` plus a PR. This design does not assume Option B and does not propose it.

**Everything that cannot proceed until he answers:**
- Step 1 (dry-run against the real workbook) — the checksum gate refuses the current sheet and the approved file is not on the machine (importer header docstring: "THE REAL IMPORT HAS NOT RUN").
- Step 2 (the preview write).
- Step 3 (committing the verification report).
- Closing issue #727 (the importer's own header states it stays open until someone supplies the workbook, runs the import, and commits the report).

**Everything that proceeds regardless (already done, not blocked):**
- The offline test suite (`scripts/tests/test_import_order_list.py`) — green, needs no workbook, no DB, no network. It proves the import **logic**, including the zero-change second run; it does not prove the import **happened**.
- The merged schema DDL (the three migrations) — already applied to preview per their own headers.
- This design document.

I am not picking a source, not designing a reconciliation between the two exports, and not proposing to auto-update the approved checksum.

---

## 6. Risks and open questions

**R1 — `matched` will read 0 on the real run today, by design.** `load_master_data_catalog` joins `public.style_tracker_rows` to `plm.style_tracker_item_bridge`, and the bridge's `plm_item_id` is all-NULL today (`plm.item` is empty — confirmed read-only in `20260810100000`). So uniquely resolved lines get `master_data_match_status = 'unmatched'` with `metadata.item_link_pending_reason = 'plm_item_unpopulated'` and `resolution = 'unique'`. The report's "status = matched" row will be 0; "resolution = unique" will carry the large count (~23,756). This is issue #727's coordination constraint with `fix_schema_for_api.md` Phase 4, not a defect. A reviewer who scans only the `matched` column will wrongly conclude the import failed — the `resolution` column is the one that reflects Master Data evidence.

**R2 — hard dependency on `20260810060000`.** The importer writes canonical rows with the legacy `(source_system, source_id)` pair left NULL. That is only legal because `20260810060000` rebuilt both constraints as NULLS DISTINCT; under the original NULLS NOT DISTINCT shape the second canonical order INSERT would die with `duplicate key (null, null)`. Step 0 of the run procedure must confirm `20260810060000` is applied on preview before any write. (This is the same latent bug the migration documents; `plm.item` carries the identical unfixed shape but is out of claim #624 and out of scope here.)

**R3 — the real first import will show no drift, but the drift path matters later.** On a clean preview there is no existing data, so `orders_drifted` / `lines_drifted` are 0 and the drift table is empty. Drift becomes live only if (a) staff edit imported rows in the app before a re-import, or (b) a prior aborted run left a partial prefix on preview. Case (b) is safe to resume (§2c) but the operator should know the report's "inserted" column reflects this run only.

**R4 — drift source refs include normalized PO numbers.** When populated, the drift table's `source_id` column carries refs like `order:po:<normalized-po>`. These are deterministic provenance (sheet row / normalized PO), not SKUs, customers, or licensed data, and the table is empty on a clean first import. Flagged only so a future reviewer does not mistake a populated drift table for a leak.

**O1 — two baseline figures are printed but not asserted.** `ReconciliationBaseline` holds `structurally_invalid_assortment_rows = 10` and `ambiguous_matches = 449`, and the report prints both, but `balance_checks()` does not compare either to the baseline. Both are deterministic from the source (the 10 invalid assortments) or from a stable Master Data read (the 449 ambiguous SKU+type pairs), so they could be asserted. Until they are, a regression in assortment splitting or catalog duplicate counts could pass a "BALANCED" report. Not blocking; recommend adding both to the baseline-gated checks.

**O2 — catalog read happens once at run start.** `load_master_data_catalog` reads `public.style_tracker_rows` live. If Master Data changes between the dry-run and the preview run, the `resolution`/`status` split can shift while the row-shape baseline stays fixed. Not blocking for a single same-session run; worth keeping the dry-run and preview run in the same session.

**O3 — `openpyxl` / `psycopg` not pinned by the test suite.** The offline tests import neither, so CI proves the logic without them. The preview run will fail late if either is missing (`main` raises a clear `ImporterError`). Recommend documenting the install step in the run procedure rather than discovering it at run time.
