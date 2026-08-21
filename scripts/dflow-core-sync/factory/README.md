# dflow."Factory" → core.factory

One-way sync only. Run this when you want latest PLM factory data in `core.factory`.

| File | Purpose |
|---|---|
| `00_audit_factory.sql` | Counts + unlinked rows |
| `01_sync_latest_into_core_factory.sql` | **Execute this** — insert missing + update linked `core.factory` from current `dflow."Factory"` |

Does not write back to `dflow`. Durable contract: migration `20260821180000_dflow_factory_to_core_factory.sql`.
