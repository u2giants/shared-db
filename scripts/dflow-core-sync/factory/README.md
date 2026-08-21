# dflow."Factory" → core."Factory" (table replica)

Real table copy — same columns and integer `id`. **Not** a view and **not**
`core.factory` / `factory_source_ref`.

| File | Purpose |
|---|---|
| `00_audit_factory.sql` | Counts / missing ids |
| `01_sync_latest_into_core_factory.sql` | **Execute this** — upsert + delete extras so `core."Factory"` matches dflow |

Migration: `20260821180000_dflow_factory_to_core_factory.sql` creates the table.
