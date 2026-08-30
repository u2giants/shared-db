-- Synthetic, rollback-safe contract for issue #1872.
begin;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('api.db_data_admin_scraped_properties(text,text,integer)'::regprocedure)
    into v_definition;
  if position('app.require_licensing_manager_access()' in v_definition) = 0
     or position('creative_submission_property_resolution' in v_definition) = 0
     or position('creative_submission_contract_resolution' in v_definition) = 0 then
    raise exception '#1872 RPC contract or Licensing Manager gate is missing';
  end if;
  if position('document_sha256' in v_definition) <> 0
     or position('page_schedule_locator' in v_definition) <> 0
     or position('exact_property_text' in v_definition) <> 0 then
    raise exception '#1872 RPC exposes private contract fields';
  end if;
  if has_table_privilege('authenticated', 'plm.creative_submission_contract_resolution', 'select')
     or has_table_privilege('anon', 'plm.creative_submission_contract_resolution', 'select')
     or not has_table_privilege('service_role', 'plm.creative_submission_contract_resolution', 'select,insert')
     or has_table_privilege('service_role', 'plm.creative_submission_contract_resolution', 'update,delete,truncate') then
    raise exception '#1872 private decision table grants are unsafe';
  end if;
end;
$$;

rollback;
