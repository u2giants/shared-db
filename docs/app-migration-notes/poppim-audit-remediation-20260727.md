# Poppim audit remediation database contracts

Date: 2026-07-27

Status: applied and verified on preview branch `shared-db-schema-rehearsal`
(`rjyboqwcdzcocqgmsyel`). Production promotion is explicitly not authorized in
this workstream.

Migrations:

- `20260727013000_poppim_audit_remediation_contracts.sql`
- `20260727013100_poppim_atomic_contract_dml_grants.sql`
- `20260727013200_fix_pm_view_pref_conflict_target.sql`

## Business problem

Poppim's product pipeline fetched a broad, updated-at-sorted product set, stopped
at 5,000 rows, and only then applied department, eligibility, search, list, and
licensor filters in the browser. Matching products beyond the cap were
undiscoverable. Counts and list facets repeated the same capped read. Product
stage and metadata writes were multi-statement client operations, so stage
history could disagree with the product and concurrent metadata writers could
erase unrelated keys. Saved-view preference persistence used a read-then-write
path even though the canonical table already had a uniqueness contract.

These migrations add bounded server contracts while leaving the existing
tables and `api.pm_product_board` compatibility view in place.

## Contracts

### `api.pm_pipeline_page(...)`

The list RPC requires `Licensed`, `Generic`, or `Software`, normalizes the
legacy aliases, applies top-level and ClickUp `open`/`custom` eligibility before
the limit, and optionally applies search, licensor UUID, list name, and
lifecycle filters. It returns only the card/detail summary fields already
present in the board contract.

Ordering is `(updated_at desc, id desc)`. Both cursor values must be supplied
together. Page size is clamped to `1..200`. The caller owns an opaque,
versioned encoding of the two returned cursor fields. The list never computes
or returns a total.

The partial `pim_product_pipeline_keyset_idx` matches the eligibility,
department expression, and keyset order. It was added from measured PM
predicates; it is unrelated to and does not copy DAM worker indexes.

### Optional supporting contracts

- `api.pm_pipeline_count(...)` is an independent exact count with the list's
  department/search/licensor/list/lifecycle semantics.
- `api.pm_pipeline_list_facets(business_unit)` returns folder/list counts for
  the entire eligible department.

Decision / Evidence / Date:

- **Decision:** facets are stable department navigation and deliberately do not
  change with active search/licensor/lifecycle filters.
- **Evidence:** the current sidebar is department/list navigation, while active
  filters are transient pipeline controls; coupling them would make navigation
  entries disappear while typing.
- **Date:** 2026-07-27.

Count and facet calls are separate RPCs so their failure cannot blank a
successful list page. The application must render them as optional data.

### Atomic mutations

- `api.pm_set_product_stage(product_id, target_stage_id)` locks the product,
  requires a UUID from the product's department pipeline, treats a same-stage
  call as a no-op, updates the product, and writes actor-attributed
  `pim.stage_history` in one transaction.
- `api.pm_patch_product_metadata(product_id, patch, expected_updated_at)`
  atomically merges JSON keys. It rejects direct-column keys and returns SQLSTATE
  `40001` with `PM_METADATA_CONFLICT` when the optional version is stale.
- `api.pm_upsert_view_pref(scope, patch)` derives the current profile rather
  than accepting another user's ID and performs `config || patch` through the
  existing named unique constraint.

All functions are `SECURITY INVOKER`. Anonymous/public execution is revoked;
authenticated execution is granted. The second migration grants only the
underlying `UPDATE product`, `INSERT stage_history`, and
`INSERT/UPDATE view_pref` privileges needed by those invoker functions.
Existing `pim.pm_write` RLS still restricts writes to administrators,
licensing, designers, and sales.

## Production and preview evidence

Read-only production inventory before authoring:

| Measurement | Result |
|---|---:|
| Products | 17,909 |
| Top-level products | 9,213 |
| Open/custom products (all nesting) | 9,985 |
| Eligible Licensed / Generic / Software | 3,337 / 183 / 55 |
| Null `updated_at` | 0 |
| Null `licensor_id` | 17,909 |
| Missing ClickUp list name | 0 |
| Missing department | 0 |
| Duplicate `(profile_id, scope)` preference groups | 0 |

All production `licensor_id` values are currently null. The list/count
contracts accept licensor UUID filters as the correct typed boundary, but that
filter cannot match legacy rows until a separately governed data reconciliation
populates those IDs. This migration does not guess a licensor mapping.

`pim.stage` has 86 rows across three pipelines. Names are unique within a
pipeline in current data but repeat across pipelines (for example `complete`
and `smpl req`), which is why the mutation accepts a stage UUID and validates
its department pipeline.

`pim.view_pref` already had
`UNIQUE (profile_id, scope)` and production had zero duplicates. No destructive
dedupe or constraint migration was needed.

## Preview verification

Reproducible scripts:

- `scripts/poppim-audit-remediation/verify-preview.sql`
- `scripts/poppim-audit-remediation/explain-preview.sql`

The correctness script inserts 12,050 rollback-only Licensed fixtures and runs
as a real authenticated preview administrator. It verified:

- all eligible rows beyond 10,000 were traversed with no duplicate primary key
  and the fetched count equaled the authoritative exact count;
- a known search match beyond the former 5,000 cap was found;
- half-cursors and invalid departments were rejected;
- facets reconciled to an independent authoritative query;
- metadata preserved unrelated keys, rejected stale versions distinctly, and
  rejected direct-column keys;
- two saved-view partial writes produced one merged row;
- stage no-op wrote no history, a real transition wrote one actor-attributed
  history row, and a forced history-insert failure rolled back the product
  update;
- a signed-in non-PM user saw zero product rows through RLS;
- `anon` had no execute privilege.

All fixture and mutation changes were rolled back. Preview was left with no
test rows.

Measured preview `EXPLAIN (ANALYZE, BUFFERS)` results under an authenticated
administrator and `statement_timeout = '8s'`:

| Probe | Execution time |
|---|---:|
| Licensed first 50 | 3,131 ms |
| Licensed next 50 | 2,816 ms |
| Generic first 50 | 298 ms |
| Software first 50 | 220 ms |
| Licensed selective search | 474 ms |
| Licensed list filter | 2,549 ms |
| Licensed exact count | 190 ms |
| Licensed facets | 618 ms |
| Underlying keyset predicate/order | 170 ms |

The underlying query used `pim_product_pipeline_keyset_idx`. Its remaining sort
was a bounded top-N heapsort (28 kB), not an offset/deep-page sort. Every public
contract completed inside the production eight-second statement budget.

## Preview rehearsal corrections

Two failures were found and corrected with new immutable migrations:

1. The first atomic mutation test failed before RLS with `permission denied for
   table product`. Existing PM tables had SELECT grants only. Migration
   `20260727013100` adds the narrow DML grants; it does not broaden RLS.
2. The first saved-view upsert reached an ambiguous PL/pgSQL conflict target
   because output names matched column names. Migration `20260727013200`
   replaces only that function and names
   `view_pref_profile_id_scope_key` explicitly.

The applied `20260727013000` file was not edited after either preview finding.

## Rollout and rollback

Preview had unrelated pending migrations
`20260726190000_style_tracker_rows_restrict_writes.sql` and
`20260726200000_style_tracker_rows_restore_open_writes.sql`. Each PM dry-run and
apply used a detached bounded checkout that removed only those two files from
the temporary copy. The reviewed dry-runs listed only the PM migration being
applied. `--include-all` was never used.

Production project `qsllyeztdwjgirsysgai` has not been linked, dry-run, or
mutated for promotion. Exact pending migrations requiring a future approved
window are the three files listed at the top of this note.

The shared-db PR/merge gate is intentionally still open. Poppim's checked-in
caller does not invoke these RPCs yet, and the current app worktree contains
uncommitted Phase 0 characterization tests owned by another workstream.
Database-level authenticated/RLS verification is complete, but an app-dependent
preview test would be artificial until the Phase 2 caller adoption exists.

Exact next steps:

1. Update Poppim's pipeline, count, facet, stage, metadata, and saved-view
   adapters to invoke these RPC signatures without editing the app's
   `shared-db/` mirror.
2. Point that app build at preview and run the named Phase 0 tests plus
   authenticated browser/network checks.
3. When the app test confirms complete first/deep pages, optional count/facet
   failures, atomic mutations, and saved-view persistence, open the shared-db PR
   from `codex/poppim-audit-remediation`.
4. Re-run `scripts/check-sql.sh`, the bounded preview dry-run, both verification
   scripts, and GitHub checks; then merge the PR.
5. Wait for the consumer sync bot and regenerate Poppim types. Production
   promotion of these three migrations still requires a separately approved
   window and must use a bounded migration set.

Rollback is additive: revert the app caller to its previous deployed SHA and
leave unused functions/indexes in place. If database removal becomes necessary,
author a new migration that revokes/drops only these six functions and the
`pim_product_pipeline_keyset_idx`; never edit an applied migration.
