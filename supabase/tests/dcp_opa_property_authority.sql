-- Sanitized structural contract for issue #1658. No licensed values are fixtures.
do $test$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'api.db_data_admin_scraped_properties(text,text,integer)'::regprocedure
  ) into v_definition;

  if position('plm.dcp_property_licensor_resolution' in v_definition) <> 0 then
    raise exception 'legacy DCP resolution still drives current API authority';
  end if;
  if position('explicit_dcp_to_opa_property_id' in v_definition) = 0
     or position('plm.dcp_opa_property_resolution_member' in v_definition) = 0
     or position('plm.opa_property_scope_membership' in v_definition) = 0 then
    raise exception 'explicit DCP identity -> OPA ID -> direct OPA scope chain is missing';
  end if;
  if position('contract_asserted_studio_code' in v_definition) = 0
     or position('contract_opa_conflict' in v_definition) = 0 then
    raise exception 'signed-contract assertion or contract/OPA fail-closed conflict is missing';
  end if;
  if position('style_guide_names' in v_definition) = 0
     or position('style_guide_count' in v_definition) = 0
     or position('asset_count' in v_definition) = 0 then
    raise exception 'sanitized DCP review context is incomplete';
  end if;
  if position('Current approved evidence supports this presentation.' in v_definition) <> 0
     or position('No action unless newer direct evidence supersedes this decision.' in v_definition) <> 0 then
    raise exception 'clean rows still carry nonblank review prose';
  end if;
  if position('source_path' in v_definition) <> 0
     or position('core_property_id' in v_definition) <> 0
     or position('presentation_licensor_key' in
       substring(v_definition from position('plm.dcp_opa_property_resolution r' in v_definition) for 1800)) <> 0 then
    raise exception 'forbidden raw-path, core, or legacy-presentation fallback detected';
  end if;
  if has_function_privilege('anon',
       'api.db_data_admin_scraped_properties(text,text,integer)', 'EXECUTE')
     or has_function_privilege('service_role',
       'api.db_data_admin_scraped_properties(text,text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated',
       'api.db_data_admin_scraped_properties(text,text,integer)', 'EXECUTE') then
    raise exception 'Scraped Properties EXECUTE boundary changed';
  end if;
end;
$test$;
