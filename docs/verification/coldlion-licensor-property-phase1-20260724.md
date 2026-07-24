# Verification — ColdLion licensor/property Phase 1 schema (revised)

**Date:** 2026-07-24
**Scope:** additive mirror/review schema + enforced scalar NOT NULL parent FK
**No apply, no fetch, no credentials in this worktree task**

## Files

| Path | Purpose |
|---|---|
| `supabase/migrations/20260724030000_coldlion_licensor_property_phase1_mirror_schema.sql` | Migration (retimed from withdrawn `20260724120000`) |
| `supabase/tests/coldlion_licensor_property_phase1_contracts.sql` | Rolled-back SQL contracts |
| `tools/coldlion-licensor-property-phase1.test.mjs` | Static smoke |
| `docs/app-migration-notes/coldlion-licensor-property-phase1-20260724.md` | Durable note |
| `fix_coldlion_licensor_property_phase1_handoff.md` | Handoff |

## Enforced parent rule (not deferred)

- Preflight: abort if any `core.property.licensor_id` is null
- `ALTER COLUMN licensor_id SET NOT NULL`
- `property_licensor_id_fkey` recreated **ON DELETE RESTRICT** (name preserved)
- Preview baseline used for confidence: 256 properties, 0 null parents

## Review contracts (revised)

### 1) Active partial unique (history preserved)

`plm_taxonomy_resolution_review_source_uidx` is a **partial** unique index:

```text
UNIQUE (entity_type, company_code, division_code, mg_type_code, mg_code)
WHERE finding_scope = 'source'
  AND status IN ('open', 'quarantined', 'conflict')
```

- **Active** = `open` | `quarantined` | `conflict` (work queue only).
- **Terminal history** = `approved_link` | `ignored` | `dismissed` (excluded from predicate).
- Proved by SQL contracts: second active insert fails; after dismiss or
  `approved_link`, a new active insert for the same source key succeeds and
  prior rows remain.

Same active-status predicate on canonical-only unique indexes.

Indexes are created **in schema `plm`**. `COMMENT ON INDEX` must use
schema-qualified identities (`plm.plm_taxonomy_resolution_review_*_uidx`).
Unqualified names failed real preview apply transactionally with:

```text
ERROR: relation "plm_taxonomy_resolution_review_source_uidx" does not exist (SQLSTATE 42P01)
At: comment on index plm_taxonomy_resolution_review_source_uidx ...
```

Root cause: migration `search_path` does not include `plm`, so bare index names
resolved under `public`. Static smoke asserts every comment on the three partial
unique indexes is `plm.`-qualified.

### 2) Status / resolution / resolved-\* CHECK matrix

| status | resolution allowed | resolved package |
|---|---|---|
| `open` | null, unmatched, ambiguous, canonical_only, deferred | all null |
| `quarantined` | null, quarantined, unmatched, ambiguous | all null |
| `conflict` | null, conflict | all null |
| `ignored` | null, ignored | all null |
| `dismissed` | null, deferred, unmatched, ignored, canonical_only | all null |
| `approved_link` | **approved_link required** | typed resolved ID + nonblank `resolved_by` + nonnull `resolved_at` |

Invalid cases contracted: missing/blank `resolved_by`, missing `resolved_at`,
`status=approved_link` with wrong resolution, non-approved + `resolution=approved_link`,
open with any resolved package, `conflict`+`ignored`, `ignored`+`conflict`,
property finding with `resolved_licensor_id`.

Typed licensor/property FK separation retained.

## Local checks (exact)

See session report for exact commands and environment limitations. Expected:

```text
node tools/coldlion-licensor-property-phase1.test.mjs
node tools/item-taxonomy-phase2.test.mjs
```

Repository SQL static checks: `scripts/check-sql.sh` content verified; on this
Windows worktree the script file is CRLF and WSL `rg` may not run — report the
exact attempt honestly rather than claiming a clean bash pass.

SQL contracts (after migration apply on disposable/preview only):

```text
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/coldlion_licensor_property_phase1_contracts.sql
```

## Object inventory (after apply)

- `core.property.licensor_id` NOT NULL; FK `property_licensor_id_fkey` RESTRICT
- Tables: `plm.erp_licensor`, `plm.erp_property`, `plm.taxonomy_resolution_review`
- Header: semantic unique key + audit columns
- Review: partial unique active indexes + status/resolution CHECK matrix
- Views: `api.coldlion_licensor_reconciliation`, `api.coldlion_property_reconciliation`, `api.coldlion_taxonomy_cutover_summary`
