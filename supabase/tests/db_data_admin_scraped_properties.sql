-- Rollback-safe contract for issue #1533.

begin;

do $$
declare
  v_sig text := 'api.db_data_admin_scraped_properties(text,text,integer)';
  v_definition text;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  v_search text;
  v_capture_old uuid := '00000000-0000-0000-0000-000000000001';
  v_capture_new uuid := '00000000-0000-0000-0000-000000000002';
  v_role_id uuid;
  v_profile uuid;
  v_auth uuid;
  v_denied_profile uuid;
  v_denied_auth uuid;
  v_page jsonb;
  v_rows jsonb;
  v_count integer;
begin
  v_search := 'Issue1533-' || v_suffix;

  if to_regprocedure(v_sig) is null then
    raise exception 'missing scraped Properties function: %', v_sig;
  end if;
  if has_function_privilege('public', v_sig::regprocedure, 'execute')
     or has_function_privilege('anon', v_sig::regprocedure, 'execute')
     or has_function_privilege('service_role', v_sig::regprocedure, 'execute') then
    raise exception 'scraped Properties function is executable outside authenticated';
  end if;
  if not has_function_privilege('authenticated', v_sig::regprocedure, 'execute') then
    raise exception 'authenticated cannot execute scraped Properties function';
  end if;

  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p where p.oid = v_sig::regprocedure;

  if position('app.require_licensing_manager_access()' in v_definition) = 0 then
    raise exception 'licensing-manager gate is missing';
  end if;

  if position('plm.opa_property' in v_definition) = 0
     or position('plm.dcp_property' in v_definition) = 0
     or position('plm.marvel_dcp_property' in v_definition) = 0
     or position('plm.lucasfilm_dcp_property' in v_definition) = 0
     or position('plm.twentieth_century_dcp_property' in v_definition) = 0
     or position('plm.pmt_property' in v_definition) = 0
     or position('plm.wb_property' in v_definition) = 0
     or position('plm.nbcu_property' in v_definition) = 0
     or position('plm.sega_property' in v_definition) = 0
     or position('plm.sega_property_licensor' in v_definition) = 0 then
    raise exception 'source Property union is incomplete';
  end if;

  if position('plm.wb_franchise' in v_definition) <> 0
     or position('plm.pmt_collection' in v_definition) <> 0
     or position('plm.dcp_style_guide' in v_definition) <> 0
     or position('core.property' in v_definition) <> 0 then
    raise exception 'contract includes a non-source-Property vocabulary';
  end if;

  select p.id, p.auth_user_id into v_profile, v_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1;
  select p.id, p.auth_user_id into v_denied_profile, v_denied_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1 offset 1;
  if v_denied_profile is null then
    raise exception 'fixture requires two active authenticated profiles';
  end if;

  select r.id into v_role_id from app.role r where r.slug = 'licensing'::app.app_role;
  delete from app.user_role where profile_id in (v_profile, v_denied_profile) and role_id = v_role_id;
  delete from app.app_access where profile_id in (v_profile, v_denied_profile) and app in ('plm','admin');
  insert into app.user_role (profile_id, role_id) values (v_profile, v_role_id);
  insert into app.app_access (profile_id, app) values (v_profile, 'plm');

  perform set_config('request.jwt.claim.sub', v_denied_auth::text, true);
  begin
    perform api.db_data_admin_scraped_properties(v_search, null, 100);
    raise exception 'unauthorized caller was allowed';
  exception when insufficient_privilege then null;
  end;

  insert into plm.dcp_property (source_system, source_id, display_name)
  values ('disney_dcpvault', v_search || '-Disney', null);
  insert into plm.marvel_dcp_property (source_system, source_id, display_name)
  values ('marvel_dcpvault', v_search || '-Marvel', v_search || ' Marvel name');
  insert into plm.lucasfilm_dcp_property (source_system, source_id, display_name)
  values ('lucasfilm_dcpvault', v_search || '-StarWars', v_search || ' Star Wars name');

  insert into plm.sega_capture (
    id, capture_key, source_repository, source_commit_sha,
    source_manifest_sha256, portal_base_url, source_captured_at,
    load_completed_at, status, expected_counts, observed_counts,
    is_limited, ip_paging_terminal, asset_paging_terminal,
    ip_associations_complete, error_summary, raw_summary, created_by
  ) values
    (v_capture_old, v_search || '-old', 'synthetic-test', repeat('1',40),
     repeat('1',64), 'https://invalid.example', '2026-08-24T00:00:00Z',
     '2026-08-24T00:01:00Z', 'complete', '{}', '{}', false, true, true,
     true, '[]', '{}', 'contract-test'),
    (v_capture_new, v_search || '-new', 'synthetic-test', repeat('2',40),
     repeat('2',64), 'https://invalid.example', '2026-08-25T00:00:00Z',
     '2026-08-25T00:01:00Z', 'complete', '{}', '{}', false, true, true,
     true, '[]', '{}', 'contract-test');

  insert into plm.sega_property (
    capture_id, property_source_id, property_label, source_status,
    source_url, source_hash, raw
  ) values
    (v_capture_old, v_search || '-Sega', v_search || ' Sega old', 'old',
     'https://invalid.example', repeat('3',64), '{}'),
    (v_capture_new, v_search || '-Sega', v_search || ' Sega new', 'active',
     'https://invalid.example', repeat('4',64), '{}');

  insert into plm.sega_property_licensor (
    capture_id, property_source_id, licensor_ordinal,
    licensor_label, normalized_licensor_label, raw
  ) values
    (v_capture_old, v_search || '-Sega', 1, 'SEGA', 'sega', '{}'),
    (v_capture_new, v_search || '-Sega', 1, 'SEGA', 'sega', '{}'),
    (v_capture_new, v_search || '-Sega', 2, 'ATLUS', 'atlus', '{}');

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  select api.db_data_admin_scraped_properties(v_search, null, 100) into v_page;
  v_rows := v_page -> 'rows';

  select count(*) into v_count from jsonb_array_elements(v_rows);
  if v_count <> 5 then
    raise exception 'expected five exact fixture rows, got %', v_count;
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ->> 'presentation_licensor_name' = 'Disney'
      and r ->> 'source_table' = 'plm.dcp_property'
  ) or not exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ->> 'presentation_licensor_name' = 'Marvel'
      and r ->> 'source_table' = 'plm.marvel_dcp_property'
  ) or not exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ->> 'presentation_licensor_name' = 'Star Wars'
      and r ->> 'source_system' = 'lucasfilm_dcpvault'
  ) then
    raise exception 'Disney, Marvel, and Star Wars presentation groups are not distinct';
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ->> 'source_property_id' = v_search || '-Disney'
      and r -> 'source_property_name' = 'null'::jsonb
      and r ->> 'display_label' = '[Unlabeled source ID: ' || v_search || '-Disney]'
  ) then
    raise exception 'null source label was hidden or replaced with an invented name';
  end if;

  select count(*) into v_count
  from jsonb_array_elements(v_rows) r
  where r ->> 'source_property_id' = v_search || '-Sega';
  if v_count <> 2 then
    raise exception 'Sega capture repeats or multi-Licensor rows were collapsed incorrectly: %', v_count;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ->> 'source_property_id' = v_search || '-Sega'
      and r ->> 'capture_marker' <> v_capture_new::text
  ) then
    raise exception 'Sega capture deduplication did not select one deterministic capture';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_rows) r
    where r ?| array['raw','source_url','licensed_asset','metadata']
  ) then
    raise exception 'restricted raw/source fields leaked through the contract';
  end if;

  begin
    perform api.db_data_admin_scraped_properties(v_search, 'not-base64!', 100);
    raise exception 'invalid cursor accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;

rollback;
