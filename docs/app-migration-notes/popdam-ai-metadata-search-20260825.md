# PopDAM Scoped AI Metadata + Deterministic Search — 2026-08-25

Canonical prerequisite-A migration:
`20260825041343_popdam_ai_search_batched_forward.sql`.

This is deliberately not the final #1427 contract. It is the short first half
of a governed two-transaction recovery. It adds the nullable `asset_tags`
columns and the three indexes needed by the later bounded reconciliation, then
commits so PostgreSQL releases the `ALTER TABLE` lock before that long work.
It performs no tag normalization, legacy import, deduplication, compatibility
rebuild, search-document rebuild, or final constraint activation.

Between prerequisite A and recovery B, production is an explicit safe pending
state:

- all new columns remain nullable, so existing rows and writers keep working;
- the existing enabled `assets.tags` compatibility trigger is retained and
  verified, rather than disabled before reconciliation is ready;
- the category column comment records that #1427 recovery B is pending;
- the general `(asset_id, id)` index supports the later keyset compatibility
  rebuild and B drops it afterwards; the active-only index is retained for the
  final contract; the pending-normalization index supports bounded dirty-row
  seeks and B drops it after normalization;
- no application may enable the new scoped-AI/search contract until B is
  applied and its final contract tests pass.

Preview already contains the complete historical #1427 contract. Prerequisite A
is idempotent there: it does not replace functions or triggers, and its nullable
`ADD COLUMN IF NOT EXISTS` statements do not weaken existing constraints.

Historical merged versions `20260825010603`, `20260825025154`, and
`20260825031841` remain retired and production-hard-blocked. The first and third
timed out in production and rolled back; the accelerator had an impossible
inverse ordering dependency. Rejected draft version `20260825034915` was never
merged and has no migration file; its permanent governance reservation prevents
reuse. It was rejected because it still wrapped the remaining contract in one
timed statement and held an exclusive table lock across the long transaction.

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
`existing_text_normalization_rows = 0`. Recovery B must still reconcile every
new nullable category/status value and must use separately timed, monotonic
keyset statements. The pending partial index cheapens those seeks but does not
physically shrink inside B's transaction because dead index entries remain
until commit.

## Final contract retained for recovery B

- Product/artwork AI facts live on `style_groups` and `style_group_tags`;
  file-specific visual facts live on `asset_tags`.
- Manual rows and rejected tombstones are retained. AI replacement RPCs replace
  only rows owned by the same source/model.
- `assets.tags` contains active asset-level tags only; group tags, candidates,
  and rejections never enter it.
- Effective metadata reads both scopes without copying group facts onto member
  assets, with current Style Group identity winning for grouped assets.
- Search documents deterministically include active tags and canonical
  character names and refresh only directly affected assets/groups.
- Embedding work uses expiring exclusive leases, hash/token-checked writes,
  bounded categorized retries, and admin/service reset.

Tracked by [shared-db #1427](https://github.com/u2giants/shared-db/issues/1427),
[shared-db #1474](https://github.com/u2giants/shared-db/issues/1474),
[PopDAM #96](https://github.com/u2giants/popdam3/issues/96), and
[PopDAM #97](https://github.com/u2giants/popdam3/issues/97).
