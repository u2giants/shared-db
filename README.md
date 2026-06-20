# Shared DB

Planning repo for the unified POP shared database on Supabase.

This repo holds schema mapping, relationship design, migration gaps, and cutover preparation notes for consolidating DAM, CRM, PM, and the operational PLM data needed by those apps into one Supabase project.

## Current Documents

- [Unified Supabase schema map](docs/unified-supabase-schema-map.md) - canonical entity/table ownership map across DAM, CRM, PM, and PLM.
- [Unified Supabase relationships](docs/unified-supabase-relationships.md) - crossover relationships, join strategy, realtime boundaries, and browser-facing API contracts.
- [Unified Supabase migration gaps](docs/unified-supabase-migration-gaps.md) - duplicates, conflicts, risky tables, missing links, and migration-order risks.
- [Supabase migration preparation](docs/supabase-migration-prep.md) - rehearsal plan for moving the current Directus-owned Postgres data into Supabase.

## Target

Supabase project:

```text
https://qsllyeztdwjgirsysgai.supabase.co
```

No migrations or production writes are represented by these documents. They are planning artifacts for later implementation.
