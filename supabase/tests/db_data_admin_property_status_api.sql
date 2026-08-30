begin;

do $$
declare
  v_auth uuid:=gen_random_uuid(); v_profile uuid; v_role uuid;
  v_lic uuid; v_property uuid; v_updated timestamptz; v_op uuid:=gen_random_uuid();
  v_result jsonb; v_authz uuid; v_suffix text:=substr(replace(gen_random_uuid()::text,'-',''),1,10);
begin
  -- Null identity must fail closed.
  begin
    perform api.db_data_admin_set_property_status(gen_random_uuid(),'probe',gen_random_uuid(),'active',now());
    raise exception 'null identity was admitted';
  exception when insufficient_privilege then null; end;

  insert into auth.users(id,email) values(v_auth,'issue1952-'||v_suffix||'@example.invalid');
  insert into app.profile(auth_user_id,email,display_name,status)
    values(v_auth,'issue1952-'||v_suffix||'@example.invalid','Issue 1952','active') returning id into v_profile;
  select id into v_role from app.role where slug='licensing';
  insert into app.user_role(profile_id,role_id) values(v_profile,v_role);

  -- Role alone is insufficient; explicit PLM/admin access is mandatory.
  perform set_config('request.jwt.claim.sub',v_auth::text,true);
  begin
    perform api.db_data_admin_set_property_status(gen_random_uuid(),'probe',gen_random_uuid(),'active',now());
    raise exception 'licensing role without app access was admitted';
  exception when insufficient_privilege then null; end;
  insert into app.app_access(profile_id,app) values(v_profile,'plm');

  insert into plm.licensing_write_authorization
    (backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  values(pg_backend_pid(),txid_current(),'core.licensor','licensing_review_create',gen_random_uuid(),
    repeat('1',64),'issue-1952-test',array['name','code','status'],clock_timestamp()+interval '1 minute');
  insert into core.licensor(name,code,status) values('Issue 1952', 'I'||v_suffix,'active') returning id into v_lic;
  insert into plm.licensing_write_authorization
    (backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',gen_random_uuid(),
    repeat('2',64),'issue-1952-test',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
  insert into core.property(licensor_id,name,code,status)
    values(v_lic,'Issue 1952 Property','P'||v_suffix,'potential') returning id,updated_at into v_property,v_updated;

  -- Invalid states, missing rows and stale tokens never create authority.
  v_result:=api.db_data_admin_set_property_status(gen_random_uuid(),'invalid',v_property,'potential',v_updated);
  if v_result->>'code'<>'validation' then raise exception 'invalid status was not refused'; end if;
  v_result:=api.db_data_admin_set_property_status(gen_random_uuid(),'missing',gen_random_uuid(),'active',v_updated);
  if v_result->>'code'<>'not_found' then raise exception 'missing Property was not refused'; end if;
  v_result:=api.db_data_admin_set_property_status(gen_random_uuid(),'stale',v_property,'active',v_updated-interval '1 second');
  if v_result->>'code'<>'stale_token' then raise exception 'stale token was not refused'; end if;

  v_result:=api.db_data_admin_set_property_status(v_op,'activate',v_property,'active',v_updated);
  if v_result->>'success'<>'true' or v_result->>'idempotent_replay'<>'false' then raise exception 'valid transition failed'; end if;
  v_authz:=(v_result->>'authorization_id')::uuid;
  if (select status::text from core.property where id=v_property)<>'active' then raise exception 'status did not change'; end if;
  if not exists(select 1 from plm.licensing_write_authorization where id=v_authz and consumed_at is not null
    and protected_columns=array['status']::text[]) then raise exception 'exact authorization was not consumed'; end if;
  if not exists(select 1 from plm.licensing_write_guard_audit where authorization_id=v_authz
    and protected_columns=array['status']::text[]) then raise exception 'licensing audit missing'; end if;
  if not exists(select 1 from app.db_data_admin_audit_event where operation_id=v_op
    and old_snapshot->>'status'='potential' and new_snapshot->>'status'='active') then raise exception 'admin audit missing'; end if;

  v_result:=api.db_data_admin_set_property_status(v_op,'activate',v_property,'active',v_updated);
  if v_result->>'idempotent_replay'<>'true' then raise exception 'idempotent replay failed'; end if;
  if (select count(*) from plm.licensing_write_authorization where plan_id=v_op)<>1 then raise exception 'replay created authority'; end if;

  if has_function_privilege('anon','api.db_data_admin_set_property_status(uuid,text,uuid,text,timestamptz)','EXECUTE')
     or has_function_privilege('service_role','api.db_data_admin_set_property_status(uuid,text,uuid,text,timestamptz)','EXECUTE')
     or not has_function_privilege('authenticated','api.db_data_admin_set_property_status(uuid,text,uuid,text,timestamptz)','EXECUTE') then
    raise exception 'RPC grants are not authenticated-only';
  end if;
  raise notice 'db_data_admin_property_status_api: OK';
end $$;

rollback;
