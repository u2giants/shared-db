-- #1474 transaction-rolled-back final-state checks.
begin;

do $$
begin
  if to_regclass('public.style_group_tags') is null
     or to_regclass('public.dam_search_documents') is null
     or to_regprocedure('public.get_effective_asset_metadata(uuid)') is null
     or to_regprocedure('public.claim_dam_search_embedding_documents(integer,text,integer)') is null then
    raise exception 'complete #1427 contract is missing after batched forward';
  end if;

  if to_regclass('public.asset_tags_pending_metadata_normalization_idx') is not null then
    raise exception 'temporary normalization accelerator remains after batched forward';
  end if;

  if to_regprocedure('pg_temp.popdam_forward_1474_normalize_batch(integer)') is not null
     or to_regprocedure('pg_temp.popdam_forward_1474_rebuild_batch(integer)') is not null then
    raise exception 'temporary batched-forward helper remains after migration';
  end if;

  if to_regclass('pg_temp.popdam_forward_1474_cursor') is not null then
    raise exception 'temporary batched-forward cursor remains after migration';
  end if;
end $$;

rollback;
