-- Issue #963: durable resolution shape, security and coherence.
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
    and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER');
  if v_count <> 0 then
    raise exception 'direct source_resolution mutation grants exist: %', v_count;
  end if;

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

