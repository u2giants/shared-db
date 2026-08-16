-- #853/#868 contract: canonical item links are additive and fail loudly.

do $$
declare
  delete_action "char";
  function_body text;
begin
  select c.confdeltype
  into delete_action
  from pg_constraint c
  where c.conname = 'style_tracker_item_bridge_plm_item_id_fkey'
    and c.conrelid = 'plm.style_tracker_item_bridge'::regclass;

  if delete_action is distinct from 'r' then
    raise exception 'plm_item_id must use ON DELETE RESTRICT; found %', delete_action;
  end if;

  select pg_get_functiondef('plm.refresh_style_tracker_item_bridge()'::regprocedure)
  into function_body;

  if function_body not like '%CASE WHEN count(*) = 1 THEN min(id::text)::uuid END AS id%'
     or function_body not like '%coalesce(EXCLUDED.erp_item_id, plm.style_tracker_item_bridge.erp_item_id)%'
     or function_body not like '%coalesce(EXCLUDED.plm_item_id, plm.style_tracker_item_bridge.plm_item_id)%' then
    raise exception 'bridge refresh lost its unique-only or preserve-existing safety rule';
  end if;
end;
$$;
