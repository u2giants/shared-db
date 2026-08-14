-- Issue #963: durable resolution shape, security and coherence.
begin;
create extension if not exists dblink with schema extensions;

do $$
declare
  v_rls boolean;
  v_count integer;
begin
  select relrowsecurity into v_rls from pg_class where oid = 'plm.source_resolution'::regclass;
  if not v_rls then raise exception 'plm.source_resolution RLS is not enabled'; end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'plm' and table_name = 'source_resolution'
    and grantee in ('anon','authenticated','service_role')
    and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN');
  if v_count <> 0 then
    raise exception 'direct source_resolution mutation grants exist: %', v_count;
  end if;

  if exists (
       select 1
       from pg_proc p,
            aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
       where p.oid = 'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure
         and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
     ) or has_function_privilege('anon',
       'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)',
       'EXECUTE') then
    raise exception 'source resolution command is executable by PUBLIC/anon';
  end if;
  if not has_function_privilege('authenticated',
       'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)',
       'EXECUTE')
     or not has_function_privilege('service_role',
       'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)',
       'EXECUTE') then
    raise exception 'source resolution command missing authenticated/service_role execute';
  end if;

  if position('pg_advisory_xact_lock' in pg_get_functiondef(
       'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure
     )) = 0 then
    raise exception 'source resolution command does not serialize first writers';
  end if;

  begin
    execute 'set local role anon';
    perform plm.set_source_resolution(
      'zztest', 'property', 'anon-must-fail', 'unresolved',
      null, null, null, null, null, null
    );
    execute 'reset role';
    raise exception 'anon executed the source resolution command';
  exception when insufficient_privilege then
    execute 'reset role';
  end;

  execute 'set local role authenticated';
  perform plm.set_source_resolution(
    'zztest', 'property', 'authenticated-command', 'unresolved',
    null, null, null, null, null, null
  );
  execute 'reset role';
  delete from plm.source_resolution
    where source_system = 'zztest' and entity_kind = 'property'
      and source_id = 'authenticated-command';

  begin
    insert into plm.source_resolution (
      source_system, entity_kind, source_id, resolution_status
    ) values ('zztest', 'property', 'matched-without-target', 'matched');
    raise exception 'matched resolution without a target was accepted';
  exception when check_violation then null;
  end;

  begin
    insert into plm.source_resolution (
      source_system, entity_kind, source_id, resolution_status, core_property_id
    ) values ('zztest', 'character', 'wrong-kind', 'matched', gen_random_uuid());
    raise exception 'character-to-property target was accepted';
  exception when check_violation or foreign_key_violation then null;
  end;
end;
$$;

do $$
declare v_has boolean; v_first text; v_second_failed boolean := false;
begin
  select exists (select 1 from pg_extension where extname='dblink') into v_has;
  if not v_has then raise exception 'first-writer race requires dblink; concurrency proof cannot be skipped'; end if;
  -- This suite runs as the throwaway database owner. The _u form is required because dblink's
  -- ordinary form refuses passwordless local-socket reuse even for this isolated test server.
  -- Shared preview is verified by the governed workflow, never by this ephemeral-only suite.
  perform dblink_connect_u('sr_first','dbname='||current_database());
  perform dblink_connect_u('sr_second','dbname='||current_database());
  perform dblink_send_query('sr_first', $q$
    with d as materialized (select plm.set_source_resolution('zztest-race','property','same-key','unresolved',null,null,null,null,'first',null) row),
         pause as materialized (select pg_sleep(1) from d)
    select (row).updated_at::text from d,pause$q$);
  perform pg_sleep(0.1);
  perform dblink_send_query('sr_second', $q$select (plm.set_source_resolution('zztest-race','property','same-key','no_match',null,null,null,null,'second',null)).updated_at::text$q$);
  while dblink_is_busy('sr_first')=1 loop perform pg_sleep(0.05); end loop;
  select result into v_first from dblink_get_result('sr_first') as t(result text);
  while dblink_is_busy('sr_second')=1 loop perform pg_sleep(0.05); end loop;
  begin
    perform result from dblink_get_result('sr_second') as t(result text);
  exception when serialization_failure then v_second_failed := true;
            when unique_violation then raise exception 'concurrent first writer leaked duplicate-key error';
  end;
  if not v_second_failed then raise exception 'concurrent first writer did not receive reload conflict'; end if;
  perform dblink_disconnect('sr_first'); perform dblink_disconnect('sr_second');
  delete from plm.source_resolution where source_system='zztest-race' and source_id='same-key';
exception when others then
  begin perform dblink_disconnect('sr_first'); exception when others then null; end;
  begin perform dblink_disconnect('sr_second'); exception when others then null; end;
  delete from plm.source_resolution where source_system='zztest-race' and source_id='same-key';
  raise;
end;
$$;
rollback;
