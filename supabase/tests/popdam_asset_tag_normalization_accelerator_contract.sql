-- #1427 production-timeout recovery contract checks. Run after 20260825020826.
-- Transaction rollback keeps the test non-destructive.
begin;

do $$
declare
  v_predicate text;
begin
  if to_regclass('public.asset_tags_pending_metadata_normalization_idx') is null then
    raise exception 'asset tag normalization accelerator index is missing';
  end if;

  select pg_get_expr(i.indpred, i.indrelid)
    into v_predicate
  from pg_index i
  where i.indexrelid = 'public.asset_tags_pending_metadata_normalization_idx'::regclass;

  if v_predicate is null
     or v_predicate not like '%category IS NULL%'
     or v_predicate not like '%status IS NULL%'
     or v_predicate not like '%btrim(tag)%'
     or v_predicate not like '%btrim(source)%' then
    raise exception 'normalization accelerator predicate is incomplete: %', v_predicate;
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
