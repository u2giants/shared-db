-- Issue #2466 contract: invented rows only; all writes roll back.

begin;

do $$
declare
  v_run uuid;
  v_item uuid;
  v_licensor uuid;
  v_property uuid;
  v_row record;
  v_columns text[];
  v_viewdef text;
begin
  select array_agg(column_name order by ordinal_position)
    into v_columns
  from information_schema.columns
  where table_schema = 'api' and table_name = 'plm_item_list';

  if v_columns is distinct from array[
    'id','source_id','style_number','item_description','mg_category',
    'mg01_code','mg02_code','mg03_code','mg04_code','mg05_code','mg06_code',
    'size_code','licensor_code','property_code','division_code','prepack_code',
    'prepack_codes','dismissed','erp_updated_at','synced_at','source_system'
  ]::text[] then
    raise exception '#2466: api.plm_item_list column contract changed: %', v_columns;
  end if;

  select pg_get_viewdef('api.plm_item_list'::regclass, true) into v_viewdef;
  if v_viewdef not like '%plm.item i%' then
    raise exception '#2466: api.plm_item_list does not read plm.item';
  end if;

  insert into core.licensor (name, code)
  values ('ZZ2466 LICENSOR', 'ZZ2466L') returning id into v_licensor;
  insert into core.property (licensor_id, name, code)
  values (v_licensor, 'ZZ2466 PROPERTY', 'ZZ2466P') returning id into v_property;

  insert into plm.item (
    item_number, style_number, description, licensor_id, property_id,
    source_system, source_id, raw, updated_at
  ) values (
    'ZZ2466ITEM', null, 'ZZ2466 DESCRIPTION', v_licensor, v_property,
    'coldlion', 'ZZCO|ZZ001|ZZ2466ITEM',
    jsonb_build_object(
      'companyCode','ZZCO','divisionCode','ZZ001','itemNo','ZZ2466ITEM',
      'mGCategory','ZZCAT','merchGroup01','ZZ01','merchGroup02','ZZ02',
      'merchGroup03','ZZ03','merchGroup04','ZZ04','merchGroup05','ZZ05',
      'merchGroup06','ZZ06','sizeRangeCode','ZZSIZE',
      'modTime','2024-05-06T07:08:09Z'
    ),
    '2026-09-09T12:00:00Z'
  ) returning id into v_item;

  insert into public.erp_items_current (external_id, dismissed)
  values ('ZZ2466ITEM', true);

  insert into coldlion.sync_run (endpoint, company_code, requested_by)
  values ('/itemDetails', 'ZZCO', 'ZZ2466') returning id into v_run;
  insert into coldlion.item_header (
    company_code, division_code, item_no, run_id, fetched_at, source_hash,
    first_seen_at, last_seen_at
  ) values (
    'ZZCO','ZZ001','ZZ2466ITEM',v_run,now(),repeat('a',64),now(),now()
  );
  insert into coldlion.item_detail (
    company_code, division_code, item_no, item_pkey, pre_pack_code,
    run_id, fetched_at, source_hash, first_seen_at, last_seen_at
  ) values
    ('ZZCO','ZZ001','ZZ2466ITEM','ZZSKU1',' ZZPACK2 ',v_run,now(),repeat('b',64),now(),now()),
    ('ZZCO','ZZ001','ZZ2466ITEM','ZZSKU2','ZZPACK1',v_run,now(),repeat('c',64),now(),now()),
    ('ZZCO','ZZ001','ZZ2466ITEM','ZZSKU3','ZZPACK1',v_run,now(),repeat('d',64),now(),now());

  select * into strict v_row from api.plm_item_list where id = v_item;
  if (v_row.source_id, v_row.style_number, v_row.item_description,
      v_row.mg_category, v_row.mg01_code, v_row.mg06_code, v_row.size_code,
      v_row.licensor_code, v_row.property_code, v_row.division_code,
      v_row.prepack_code, v_row.prepack_codes, v_row.dismissed,
      v_row.erp_updated_at, v_row.synced_at, v_row.source_system)
     is distinct from
     ('ZZ2466ITEM','ZZ2466ITEM','ZZ2466 DESCRIPTION','ZZCAT','ZZ01','ZZ06','ZZSIZE',
      'ZZ2466L','ZZ2466P','ZZ001','ZZPACK1','["ZZPACK1", "ZZPACK2"]'::jsonb,true,
      '2024-05-06T07:08:09Z'::timestamptz,'2026-09-09T12:00:00Z'::timestamptz,'coldlion') then
    raise exception '#2466: canonical mapping/prepack/dismissed contract failed: %', row_to_json(v_row);
  end if;

  insert into plm.item (item_number, description, source_system, source_id, raw)
  values ('ZZ2466NULL', 'ZZ2466 UNRESOLVED', 'coldlion', 'ZZCO|ZZ001|ZZ2466NULL',
          '{"companyCode":"ZZCO","divisionCode":"ZZ001","itemNo":"ZZ2466NULL"}')
  returning id into v_item;

  select * into strict v_row from api.plm_item_list where id = v_item;
  if v_row.licensor_code is not null or v_row.property_code is not null
     or v_row.prepack_code is not null or v_row.prepack_codes is not null
     or v_row.dismissed is distinct from false then
    raise exception '#2466: unresolved/new-item null/default contract failed: %', row_to_json(v_row);
  end if;

  raise notice '#2466 PASSED: 21 columns, canonical mappings, direct prepacks, null attribution and dismissed state.';
end;
$$;

rollback;
