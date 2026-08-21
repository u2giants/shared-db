# dflow.Factory → core.factory link contract

**Date:** 2026-08-21  
**Migration:** `20260821180000_dflow_factory_to_core_factory.sql`  
**Scripts:** `scripts/dflow-core-sync/factory/`

## Contract

| Legacy | Canonical |
|---|---|
| `dflow."Factory"` (integer `id`) | `core.factory` (uuid `id`) |
| Link | `core.factory_source_ref` with `source_system='designflow_plm'`, `source_table='Factory'`, `source_id=<id::text>` |
| App read shape | `core."Factory"` view (integer columns matching Sequelize `Factory`) |

## Notes

- Coldlion vendors already live in `core.factory` with `source_system='coldlion'`. PLM factories are a separate population; name overlap is near-zero. Do not merge by nickname alone.
- New PLM rows get `code = 'DFLOW-<id>'` so they satisfy `core.factory_code_key` (null codes are not multi-insert safe on this constraint).
- Status map: `Active` → `active`, `Inactive` → `inactive`.
- Reverse sync (active core without a PLM Factory ref → insert into `dflow."Factory"`) is optional and lives only in `02_insert_missing_into_dflow.sql`.

## Develop rehearsal (2026-08-21)

| Metric | Value |
|---|---:|
| `dflow."Factory"` | 169 |
| Inserted into `core.factory` | 169 |
| `designflow_plm` / `Factory` refs | 169 |
| Unlinked dflow rows after sync | 0 |
| `core.factory` total (incl. coldlion) | 262 |

## App consumers

- `designflow-backend` `config/table-schema-map.js`: `Factory: 'core'` (non-production multi-schema).
- Production Cloud SQL remains single-schema `designflow` until cutover.
