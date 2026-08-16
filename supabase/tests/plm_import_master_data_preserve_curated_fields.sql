-- Synthetic, rollback-safe proof for issue #555.
begin;

do $$
declare
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  v_feed_licensor uuid;
  v_curated_parent uuid;
  v_property uuid;
  v_feed_licensor_source text;
  v_property_source text;
  v_count integer;
  v_row record;
begin
  v_feed_licensor_source := 'zz555-lic-' || v_suffix;
  v_property_source := 'zz555-prop-' || v_suffix;

  insert into core.licensor (name, code, status, metadata)
  values ('ZZ555 CURATED FEED LICENSOR ' || v_suffix, 'ZZ555-L-' || v_suffix,
          'inactive', '{"curated":true}'::jsonb)
  returning id into v_feed_licensor;

  insert into core.licensor (name, code, status, metadata)
  values ('ZZ555 CURATED OTHER PARENT ' || v_suffix, 'ZZ555-PARENT-' || v_suffix,
          'potential', '{"curated":true}'::jsonb)
  returning id into v_curated_parent;

  insert into core.property (licensor_id, name, code, status, metadata)
  values (v_curated_parent, 'ZZ555 CURATED PROPERTY ' || v_suffix,
          'ZZ555-PROP-' || v_suffix, 'inactive', '{"curated":true}'::jsonb)
  returning id into v_property;

  insert into core.taxonomy_source_ref
    (entity_schema, entity_table, entity_id, source_system, source_table,
     source_id, source_code, source_name, confidence, raw)
  values
    ('core', 'licensor', v_feed_licensor, 'designflow_plm', 'merchGroup',
     v_feed_licensor_source, 'CURATED-SOURCE-CODE', 'CURATED SOURCE NAME',
     'rejected', '{"before":true}'::jsonb);

  -- The property has no PLM source ref yet and sits under a different curated
  -- parent. The importer must find it globally by its unique code, not insert a
  -- duplicate beneath the feed parent.
  perform plm.import_master_data(
    jsonb_build_array(jsonb_build_object(
      'id', v_feed_licensor_source,
      'title', 'UPSTREAM LICENSOR NAME',
      'mg_code', 'UPSTREAM-LICENSOR-CODE',
      'properties', jsonb_build_array(jsonb_build_object(
        'id', v_property_source,
        'title', 'UPSTREAM PROPERTY NAME',
        'mg_code', 'ZZ555-PROP-' || v_suffix
      ))
    )),
    '[]'::jsonb
  );

  select * into v_row from core.licensor where id = v_feed_licensor;
  if v_row.name <> 'ZZ555 CURATED FEED LICENSOR ' || v_suffix then
    raise exception 'issue 555: matched licensor name was overwritten';
  elsif v_row.code <> 'ZZ555-L-' || v_suffix then
    raise exception 'issue 555: matched licensor code was overwritten';
  elsif v_row.status::text <> 'inactive' then
    raise exception 'issue 555: matched licensor status was overwritten';
  elsif v_row.metadata <> '{"curated":true}'::jsonb then
    raise exception 'issue 555: matched licensor metadata was overwritten';
  end if;

  select * into v_row from core.property where id = v_property;
  if v_row.licensor_id <> v_curated_parent
     or v_row.name <> 'ZZ555 CURATED PROPERTY ' || v_suffix
     or v_row.code <> 'ZZ555-PROP-' || v_suffix
     or v_row.status::text <> 'inactive'
     or v_row.metadata <> '{"curated":true}'::jsonb then
    raise exception 'issue 555: matched property curation was overwritten';
  end if;

  select count(*) into v_count
  from core.property where code = 'ZZ555-PROP-' || v_suffix;
  if v_count <> 1 then
    raise exception 'issue 555: parent disagreement created % property rows', v_count;
  end if;

  update core.taxonomy_source_ref
  set source_code = 'CURATED-PROP-SOURCE-CODE',
      source_name = 'CURATED PROPERTY SOURCE NAME',
      confidence = 'rejected'
  where source_system = 'designflow_plm'
    and source_table = 'merchGroup'
    and source_id = v_property_source;

  -- Re-pull after the source link itself has been curated. Only raw evidence and
  -- PLM mirror rows may refresh.
  perform plm.import_master_data(
    jsonb_build_array(jsonb_build_object(
      'id', v_feed_licensor_source,
      'title', 'SECOND UPSTREAM LICENSOR NAME',
      'mg_code', 'SECOND-UPSTREAM-LICENSOR-CODE',
      'properties', jsonb_build_array(jsonb_build_object(
        'id', v_property_source,
        'title', 'SECOND UPSTREAM PROPERTY NAME',
        'mg_code', 'SECOND-UPSTREAM-PROPERTY-CODE'
      ))
    )),
    '[]'::jsonb
  );

  select source_code, source_name, confidence::text into v_row
  from core.taxonomy_source_ref
  where source_system = 'designflow_plm'
    and source_table = 'merchGroup'
    and source_id = v_feed_licensor_source;
  if v_row.source_code <> 'CURATED-SOURCE-CODE'
     or v_row.source_name <> 'CURATED SOURCE NAME'
     or v_row.confidence <> 'rejected' then
    raise exception 'issue 555: curated licensor source link was overwritten';
  end if;

  select source_code, source_name, confidence::text into v_row
  from core.taxonomy_source_ref
  where source_system = 'designflow_plm'
    and source_table = 'merchGroup'
    and source_id = v_property_source;
  if v_row.source_code <> 'CURATED-PROP-SOURCE-CODE'
     or v_row.source_name <> 'CURATED PROPERTY SOURCE NAME'
     or v_row.confidence <> 'rejected' then
    raise exception 'issue 555: curated property source link was overwritten';
  end if;

  if not exists (
    select 1 from plm.property_import
    where plm_property_id = v_property_source
      and title = 'SECOND UPSTREAM PROPERTY NAME'
  ) then
    raise exception 'issue 555: upstream evidence did not refresh in the PLM mirror';
  end if;

  raise notice 'issue 555 OK: curated canonical and source-link decisions survive re-pulls';
end;
$$;

rollback;
