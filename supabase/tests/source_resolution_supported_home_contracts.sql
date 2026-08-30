-- Issue #1609 supported successor: plain UUID targets, guarded writes, dangling visibility.
begin;

do $$
declare
  v_count integer;
  v_missing uuid := gen_random_uuid();
begin
  select count(*) into v_count from pg_constraint
   where conrelid='plm.source_resolution'::regclass and contype='f';
  if v_count <> 0 then raise exception 'source_resolution still has % foreign keys',v_count; end if;

  select count(*) into v_count from pg_trigger
   where tgfoid='plm.reject_legacy_landing_resolution_write()'::regprocedure and not tgisinternal;
  if v_count <> 26 then raise exception 'expected 26 landing guards, found %',v_count; end if;

  begin
    perform plm.set_source_resolution('zztest','property','missing-target','matched',
      v_missing,null,null,null,'ZZTEST missing',null);
    raise exception 'guarded write accepted a missing target';
  exception when foreign_key_violation then null;
  end;

  -- A target can disappear after a valid historic decision. The row must remain readable
  -- and explicitly dangling; direct insert is test-only setup for that durable state.
  insert into plm.source_resolution(source_system,entity_kind,source_id,
    core_property_id,resolution_status,resolution_reason,resolved_at,resolved_by)
  values ('zztest','property','dangling-visible',v_missing,'matched','ZZTEST historic',now(),'zztest');
  if not coalesce((select target_missing from api.source_resolution
      where source_system='zztest' and entity_kind='property' and source_id='dangling-visible'),false) then
    raise exception 'dangling decision was not surfaced by the read path';
  end if;

  if exists (
    select 1 from information_schema.role_table_grants
     where table_schema='plm' and table_name='source_resolution'
       and grantee in ('anon','authenticated','service_role')
       and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
  ) then raise exception 'direct mutation grant exists on source_resolution'; end if;

  if position('to_regclass' in lower(pg_get_functiondef(
      'plm.source_resolution_target_missing(text,uuid,uuid,uuid,uuid)'::regprocedure)))=0
     or position('execute' in lower(pg_get_functiondef(
      'plm.source_resolution_target_missing(text,uuid,uuid,uuid,uuid)'::regprocedure)))=0 then
    raise exception 'dangling detector is statically coupled to target relations';
  end if;
end;
$$;

rollback;
