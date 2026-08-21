# DesignFlow `customers` → `core.customer` via import contract (2026-08-21)

**Supabase target for rehearsal:** develop branch `wxwtyxubjsfvxvjrajbk` only.  
**Production / main:** not applied.

## Decision

Do **not** blind-rename `dflow.customers` onto `core.customer`.

| Layer | Object | Role |
|---|---|---|
| Canonical hub | `core.customer` (uuid) | Shared CRM / PLM / DAM identity |
| Lineage | `core.company_source_ref` (`source_system='designflow_plm'`, `source_table='customers'`, `source_id=text(customers_id)`) | Authoritative link |
| PLM staging | `plm.customer_import` | DesignFlow-shaped columns + `company_id` |
| App compat | **`plm.customers` view** | Same integer `customers_id` + DesignFlow column names for Sequelize / RFQ FKs |

RFQ and other DesignFlow tables still store **integer** `customers_id`. Remapping the Sequelize model onto `core.customer` (uuid PK) would break those FKs.

## Data on develop (already applied — no data PR)

Develop row sync was applied operationally (not via production CI):

| Metric | Value |
|---|---:|
| `dflow.customers` | 160 |
| `plm.customer_import` | 160 |
| `designflow_plm` source refs | 160 |
| dflow rows missing core link | 0 |
| `plm.customers` view | 160 (matches linked import rows) |

**No shared-db data migration PR** is required for this develop state. Promoting the same *data* to main later still needs the gated Shared Supabase Migrations workflow and an explicit allowlist — do not treat develop dual-writes as production.

Two residual active `core.customer` rows remain without a PLM source_ref because the same display name already links another core id (`Big Lots`, `Shoppers World` / Forman Mills). Those are CRM duplicate candidates, not DesignFlow gaps.

## Schema PR (required)

Migration: `supabase/migrations/20260821154500_plm_customers_compat_view.sql`

- Creates `plm.customers` view over `customer_import` + `company_source_ref` + `core.customer`
- Adds INSTEAD OF insert/update/delete triggers that dual-write `dflow.customers` and keep import/source_ref in sync
- Does **not** force-update `core.customer.status` (app-owned)

Apply path: Shared Supabase Migrations → **preview first**, then production when DesignFlow cutover is ready. Develop already has the view for app rehearsal.

## App consumer (`designflow-backend`)

`config/table-schema-map.js` maps `customers: 'plm'` in multi-schema (non-production). Production remains single-schema `designflow` until cutover.

Sequelize model keeps integer `customers_id` and optionally reads `core_company_id` from the view.
