-- Issue #963: migration backfill and required catalog objects are present.
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from pg_trigger
  where not tgisinternal and tgname in (
    'pmt_property_resolution_immutable','pmt_character_resolution_immutable',
    'nbcu_property_resolution_immutable','nbcu_character_resolution_immutable',
    'nbcu_style_guide_resolution_immutable','nbcu_asset_resolution_immutable'
  );
  if v_count <> 6 then raise exception 'expected 6 legacy guards, found %', v_count; end if;

  select count(*) into v_count from pg_constraint
  where conrelid = 'plm.source_resolution'::regclass
    and conname in (
      'source_resolution_pkey','source_resolution_entity_kind_chk',
      'source_resolution_status_chk','source_resolution_target_kind_chk',
      'source_resolution_matched_target_chk','source_resolution_audit_pair_chk'
    );
  if v_count <> 6 then raise exception 'source_resolution constraints incomplete: %', v_count; end if;

  if obj_description('plm.source_resolution'::regclass) is null then
    raise exception 'source_resolution table comment is missing';
  end if;
end;
$$;
