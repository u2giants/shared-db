# dflow → core Factory sync scripts

Idempotent SQL for promoting `dflow."Factory"` into `core.factory` via
`core.factory_source_ref` (`designflow_plm` / `Factory` / `<id>`).

| File | Purpose |
|---|---|
| `00_audit_factory.sql` | Counts + unlinked dflow rows |
| `01_insert_missing_into_core.sql` | Insert missing PLM factories into `core.factory` + source_ref |
| `02_insert_missing_into_dflow.sql` | Optional reverse: active core without PLM ref → `dflow."Factory"` |

Canonical durable contract: migration
`supabase/migrations/20260821180000_dflow_factory_to_core_factory.sql`
and note `docs/app-migration-notes/dflow-factory-to-core-20260821.md`.

Apply official preview/prod through the Shared Supabase Migrations workflow.
Develop may be rehearsed with these scripts or MCP `execute_sql` first.
