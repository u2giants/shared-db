# PopDAM Scoped AI Metadata + Deterministic Search — 2026-08-25

Canonical forward production migration:
`20260825031841_popdam_ai_search_forward_recovery.sql`.

Preview truthfully retains historical ledger rows `20260825010603` (the original
complete contract) and `20260825025154` (its later accelerator). Neither may run
in production: the original timed out and rolled back, while ascending migration
order correctly refuses to run the later accelerator before it. Both versions
are permanently retired from production allowlists and superseded by the single
self-contained forward migration.

The forward migration detects preview's already-complete object contract and
records a no-op without rebuilding it. On production it creates the accelerator,
executes the entire #1427 metadata/search contract and legacy reconciliation,
then drops the temporary index before commit. There is no inverse dependency and
no permanent HOT/predicate overhead.

Live read-only sizing proof on 2026-08-25 used production project
`https://qsllyeztdwjgirsysgai.supabase.co` and this query:

```sql
select count(*) total_asset_tags,
       count(*) filter (
         where tag is distinct from btrim(tag)
            or source is distinct from btrim(source)
            or source is null
            or source = ''
       ) existing_text_normalization_rows
from public.asset_tags;
```

It returned `total_asset_tags = 2,173,558` and
`existing_text_normalization_rows = 0`. The new nullable `category` and `status`
columns mean the prerequisite index initially covers the existing rows, while
the proof shows none also require legacy text cleanup.

Preview can apply the one forward version idempotently because the complete
contract marker is already present. The production execution is still the first
large reconciliation at the measured 2,173,558-row scale; it runs only through
the governed promotion lane with the unchanged 10-minute statement timeout.
Tracked by [shared-db #1427](https://github.com/u2giants/shared-db/issues/1427),
[PopDAM #96](https://github.com/u2giants/popdam3/issues/96), and
[PopDAM #97](https://github.com/u2giants/popdam3/issues/97).

## Contract

- Product/artwork AI facts live on `style_groups` and `style_group_tags`; file-specific visual facts live in `asset_tags`.
- Manual rows and rejected tombstones are retained. AI replacement RPCs may replace only rows owned by the same source/model and cannot overwrite a manual or differently sourced row.
- `assets.tags` remains a compatibility array of active asset-level tags only. Group tags, candidates, and rejections never enter it.
- `get_effective_asset_metadata` reads both scopes without copying group rows or identity onto member assets. Current Style Group licensor/property wins for grouped assets; asset identity is used only while ungrouped.
- Search documents deterministically include active tags and canonical character names. Changes refresh only directly affected asset/group documents through a bounded, deduplicated contract.
- Embedding work uses expiring exclusive leases, content-hash and lease-token checked writes, bounded categorized retries, and an admin/service reset. No embedding backfill is part of this migration.
- Legacy tag normalization disables the obsolete per-row compatibility trigger first, normalizes 5,000 tag rows per internal batch, then rebuilds compatibility arrays in 2,000-asset keyset batches. The internal batches remain one enclosing `DO` statement, so the production statement timeout applies to their combined duration; the prerequisite index is required to keep its repeated ordered scans bounded.

## Release order and gates

1. Apply only `20260825031841` and run `supabase/tests/popdam_scoped_ai_metadata_search_contracts.sql` plus the forward-recovery contract in preview with rollback.
2. Promote the final corpus definition through the shared-db orchestrator gates.
3. Only after production object/ledger proof may PopDAM ship compatible application code.
4. PopDAM may run one separate application-owned embedding backfill only after its approval gate. Never backfill an intermediate corpus definition.

`propagate_group_tags_batch` is intentionally unchanged. Existing applications must update to the new lease-token embedding RPC signatures before enabling the new worker path.
