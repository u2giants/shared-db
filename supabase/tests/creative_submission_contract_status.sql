-- Synthetic, rollback-safe contract for issue #1872.
begin;

do $$
declare
  v_definition text;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  v_role_id uuid;
  v_profile uuid;
  v_auth uuid;
  v_licensor uuid := gen_random_uuid();
  v_capture_complete uuid := gen_random_uuid();
  v_capture_incomplete uuid := gen_random_uuid();
  v_property_complete uuid := gen_random_uuid();
  v_property_incomplete uuid := gen_random_uuid();
  v_document uuid := gen_random_uuid();
  v_page jsonb;
  v_row jsonb;
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

  select p.id, p.auth_user_id into v_profile, v_auth from app.profile p
  where p.status = 'active' and p.auth_user_id is not null order by p.created_at, p.id limit 1;
  select id into v_role_id from app.role where slug = 'licensing'::app.app_role;
  delete from app.user_role where profile_id = v_profile and role_id = v_role_id;
  insert into app.user_role(profile_id, role_id) values (v_profile, v_role_id);

  insert into plm.dcp_property(source_system, source_id, display_name) values
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-mapped', 'ZZ Synthetic mapped'),
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-many', 'ZZ Synthetic one to many'),
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-conflict', 'ZZ Synthetic conflict'),
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-unmapped', 'ZZ Synthetic unmapped'),
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-incomplete', 'ZZ Synthetic incomplete'),
    ('disney_dcpvault', 'zz1872-'||v_suffix||'-no-evidence', 'ZZ Synthetic no evidence');

  insert into plm.creative_submission_property_resolution
    (resolution_id,creative_source_system,creative_source_table,creative_source_id,decision_version,
     decision_state,reviewed_batch_id,reviewed_batch_digest,approval_actor_id,approved_at)
  select gen_random_uuid(),'disney_dcpvault','plm.dcp_property','zz1872-'||v_suffix||'-'||x.suffix,1,
    x.state,gen_random_uuid(),'sha256:'||repeat('1',64),gen_random_uuid(),now()
  from (values ('mapped','mapped'),('many','mapped'),('conflict','conflict'),
    ('unmapped','unmapped'),('incomplete','mapped'),('no-evidence','mapped')) x(suffix,state);

  insert into plm.creative_submission_property_resolution_member
    (resolution_member_id,resolution_id,submission_source_system,submission_source_table,submission_source_id)
  select gen_random_uuid(),r.resolution_id,'zz_submission','zz.property','submission-'||r.creative_source_id
  from plm.creative_submission_property_resolution r
  where r.creative_source_id like 'zz1872-'||v_suffix||'-%' and r.decision_state='mapped';
  insert into plm.creative_submission_property_resolution_member
    (resolution_member_id,resolution_id,submission_source_system,submission_source_table,submission_source_id)
  select gen_random_uuid(),r.resolution_id,'zz_submission','zz.property','submission-extra-'||v_suffix
  from plm.creative_submission_property_resolution r
  where r.creative_source_id='zz1872-'||v_suffix||'-many';

  insert into core.licensor(id,name,code) values(v_licensor,'ZZ Synthetic 1872','ZZ1872'||v_suffix);
  insert into plm.contract_property_capture(id,licensor_id,source_identity,evidence_date,decision_authority,controlling_chain_complete)
  values(v_capture_complete,v_licensor,'ZZ-COMPLETE-'||v_suffix,date '2099-01-01','ZZ-SYNTHETIC',true),
        (v_capture_incomplete,v_licensor,'ZZ-INCOMPLETE-'||v_suffix,date '2099-01-01','ZZ-SYNTHETIC',false);
  insert into plm.contract_property(capture_id,id,exact_property_text)
  values(v_capture_complete,v_property_complete,'ZZ SYNTHETIC COMPLETE'),
        (v_capture_incomplete,v_property_incomplete,'ZZ SYNTHETIC INCOMPLETE');
  insert into plm.contract_property_document(capture_id,id,evidence_identity,document_sha256,signature_status)
  values(v_capture_complete,v_document,'ZZ-OPAQUE-'||v_suffix,repeat('2',64),'ZZ-SIGNED');
  insert into plm.contract_property_evidence(capture_id,property_id,document_id,page_schedule_locator)
  values(v_capture_complete,v_property_complete,v_document,'ZZ-SYNTHETIC-LOCATOR');

  insert into plm.creative_submission_contract_resolution
    (submission_source_system,submission_source_table,submission_source_id,decision_version,decision_state,
     contract_capture_id,contract_property_id,reviewed_batch_id,reviewed_batch_digest,approval_actor_id,approved_at)
  select 'zz_submission','zz.property','submission-zz1872-'||v_suffix||'-mapped',1,'evidenced',
    v_capture_complete,v_property_complete,gen_random_uuid(),'sha256:'||repeat('3',64),gen_random_uuid(),now()
  union all select 'zz_submission','zz.property','submission-zz1872-'||v_suffix||'-incomplete',1,'evidenced',
    v_capture_incomplete,v_property_incomplete,gen_random_uuid(),'sha256:'||repeat('4',64),gen_random_uuid(),now()
  union all select 'zz_submission','zz.property','submission-zz1872-'||v_suffix||'-no-evidence',1,'not_evidenced',
    null,null,gen_random_uuid(),'sha256:'||repeat('5',64),gen_random_uuid(),now();

  set constraints all immediate;
  perform set_config('request.jwt.claim.sub',v_auth::text,true);
  select api.db_data_admin_scraped_properties('zz1872-'||v_suffix,null,100) into v_page;
  if jsonb_array_length(v_page->'rows') <> 6 then raise exception '#1872 dropped a Creative row'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-mapped';
  if v_row->>'mapping_state'<>'mapped' or v_row->>'contract_status'<>'entitled_evidenced' then raise exception '#1872 mapped/evidenced state failed'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-many';
  if jsonb_array_length(v_row->'submissions')<>2 or v_row->>'contract_status'<>'unknown' then raise exception '#1872 one-to-many state failed'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-conflict';
  if v_row->>'mapping_state'<>'conflict' or v_row->>'contract_status'<>'conflict' then raise exception '#1872 conflict state failed'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-unmapped';
  if v_row->>'mapping_state'<>'unmapped' or v_row->>'contract_status'<>'unknown' then raise exception '#1872 unmapped state failed'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-incomplete';
  if v_row->>'contract_status'<>'incomplete_chain' then raise exception '#1872 incomplete-chain state failed'; end if;
  select x into v_row from jsonb_array_elements(v_page->'rows') x where x->>'source_property_id'='zz1872-'||v_suffix||'-no-evidence';
  if v_row->>'contract_status'<>'not_evidenced' then raise exception '#1872 no-evidence state failed'; end if;
end;
$$;

rollback;
