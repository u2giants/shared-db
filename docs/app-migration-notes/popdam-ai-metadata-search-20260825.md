# PopDAM Scoped AI Metadata + Deterministic Search — 2026-08-25

Canonical database migration: `20260825010603_popdam_scoped_ai_metadata_search.sql`.

Production timeout recovery: apply
`20260825025154_popdam_asset_tag_normalization_accelerator.sql` first, then retry
the canonical migration. The prerequisite adds the same metadata columns with
`IF NOT EXISTS` and a partial `asset_tags(id)` index containing only rows still
needing normalization. The index gives each canonical keyset batch a much
cheaper ordered scan of the dirty-row subset and avoids repeated table/primary-
key prefix scans. Because every batch remains inside one transaction, dead index
entries remain until commit; the index does not physically shrink between
batches. The global 10-minute statement timeout and complete metadata/search
contract remain unchanged, and the canonical migration remains byte-for-byte
unchanged.

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

Preview cannot rehearse the prerequisite and canonical migration together:
`20260825010603` is already applied there. The production retry is therefore the
first combined execution. After the canonical migration is confirmed applied in
both preview and production, a separately governed follow-up migration must drop
`public.asset_tags_pending_metadata_normalization_idx`; it is then permanently
empty and retaining it would add unnecessary predicate evaluation and reduce
HOT-update opportunities.
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

1. Apply the migration and run `supabase/tests/popdam_scoped_ai_metadata_search_contracts.sql` in preview with rollback.
2. Promote the final corpus definition through the shared-db orchestrator gates.
3. Only after production object/ledger proof may PopDAM ship compatible application code.
4. PopDAM may run one separate application-owned embedding backfill only after its approval gate. Never backfill an intermediate corpus definition.

`propagate_group_tags_batch` is intentionally unchanged. Existing applications must update to the new lease-token embedding RPC signatures before enabling the new worker path.
