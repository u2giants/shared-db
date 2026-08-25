-- #1427 historical accelerator/final forward-state contract checks.
-- Transaction rollback keeps the test non-destructive.
begin;

do $$
begin
  -- 20260825025154 is retained as truthful preview history. Prerequisite A
  -- recreated this index and recovery B removes it after bounded normalization.
  if to_regclass('public.asset_tags_pending_metadata_normalization_idx') is not null then
    raise exception 'recovery-B normalization accelerator remains after final activation';
  end if;

  if not exists (
    select 1
    from pg_attribute
    where attrelid = 'public.asset_tags'::regclass
      and attname in ('category', 'status', 'confidence', 'model', 'evidence',
                      'rejected_at', 'rejected_by', 'updated_at')
      and not attisdropped
    group by attrelid
    having count(*) = 8
  ) then
    raise exception 'normalization prerequisite columns are incomplete';
  end if;
end $$;

rollback;
