# dflow."Factory" → core."Factory" table replica

**Date:** 2026-08-21  
**Migration:** `20260821180000_dflow_factory_to_core_factory.sql`  
**Scripts:** `scripts/dflow-core-sync/factory/`

## Contract

| Source | Target |
|---|---|
| `dflow."Factory"` | `core."Factory"` (same columns, integer PK) |

This is a **writable table replica**, not a view over `core.factory` and not
driven by `factory_source_ref`.

`core.factory` (uuid hub used by CRM/Coldlion) is a separate object and is
unchanged by this sync.

## App consumers

- `designflow-backend` `config/table-schema-map.js`: `Factory: 'core'`
  (non-production multi-schema).
