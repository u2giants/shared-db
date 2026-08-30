-- #1881: synthetic, rollback-only Warner lifecycle contracts.

begin;

create temp table test_wb_asset_lifecycle
  (like plm.wb_asset_normalized including defaults including generated including constraints);
create temp table test_wb_character_lifecycle
  (like plm.wb_character_normalized including defaults including generated including constraints);
create temp table test_wb_property_lifecycle
  (like plm.wb_property including defaults including generated including constraints);
create temp table test_wb_style_guide_lifecycle
  (like plm.wb_style_guide_normalized including defaults including generated including constraints);

do $contract$
declare
  v_id uuid := '18810000-0000-4000-8000-000000000001';
  v_first_seen timestamptz := '2026-01-01 00:00:00+00';
  v_invalid_rejected boolean := false;
  v_mismatch_rejected boolean := false;
  v_signal text;
begin
  insert into test_wb_asset_lifecycle (
    id, source_namespace, source_id, file_name, source_path, capture_id,
    source_url, raw, source_hash, first_seen_at
  ) values (
    v_id, 'synthetic', 'asset-1', 'fixture.bin', '/fixture.bin',
    '18810000-0000-4000-8000-000000000099', 'https://example.invalid',
    '{}'::jsonb, repeat('a', 64), v_first_seen
  );

  select change_signal into v_signal from test_wb_asset_lifecycle where id = v_id;
  if v_signal <> repeat('a', 64) then
    raise exception 'change_signal did not reproduce the retained source hash';
  end if;

  update test_wb_asset_lifecycle
  set status = 'withdrawn', withdrawn_at = '2026-02-01 00:00:00+00'
  where id = v_id;
  update test_wb_asset_lifecycle
  set status = 'active', withdrawn_at = null, source_hash = repeat('b', 64)
  where id = v_id;

  if not exists (
    select 1 from test_wb_asset_lifecycle
    where id = v_id
      and status = 'active'
      and withdrawn_at is null
      and first_seen_at = v_first_seen
      and change_signal = repeat('b', 64)
  ) then
    raise exception 'reappearance did not preserve first-seen history and refresh the signal';
  end if;

  begin
    update test_wb_asset_lifecycle set status = 'missing' where id = v_id;
  exception when check_violation then
    v_invalid_rejected := true;
  end;
  if not v_invalid_rejected then
    raise exception 'invalid lifecycle status was accepted';
  end if;

  begin
    update test_wb_asset_lifecycle
    set status = 'withdrawn', withdrawn_at = null
    where id = v_id;
  exception when check_violation then
    v_mismatch_rejected := true;
  end;
  if not v_mismatch_rejected then
    raise exception 'withdrawn status without withdrawn_at was accepted';
  end if;

  insert into test_wb_character_lifecycle (
    source_namespace, source_id, label, identity_method, capture_id,
    source_url, raw, source_hash
  ) values (
    'synthetic', 'character-1', 'Synthetic Character', 'source_id',
    '18810000-0000-4000-8000-000000000099', 'https://example.invalid',
    '{}'::jsonb, repeat('c', 64)
  );
  insert into test_wb_property_lifecycle (
    source_namespace, source_id, label, identity_method, capture_id,
    source_url, raw, source_hash
  ) values (
    'warner_product_catalogue', 'property-1', 'Synthetic Property', 'source_id',
    '18810000-0000-4000-8000-000000000099', 'https://example.invalid',
    '{}'::jsonb, repeat('d', 64)
  );
  insert into test_wb_style_guide_lifecycle (
    source_namespace, source_id, label, identity_method, capture_id,
    source_url, raw, source_hash
  ) values (
    'synthetic', 'guide-1', 'Synthetic Guide', 'source_id',
    '18810000-0000-4000-8000-000000000099', 'https://example.invalid',
    '{}'::jsonb, repeat('e', 64)
  );

  if exists (
    select 1 from test_wb_character_lifecycle where status <> 'active' or change_signal <> source_hash
    union all
    select 1 from test_wb_property_lifecycle where status <> 'active' or change_signal <> source_hash
    union all
    select 1 from test_wb_style_guide_lifecycle where status <> 'active' or change_signal <> source_hash
  ) then
    raise exception 'default active lifecycle or generated signal failed on an entity table';
  end if;
end
$contract$;

rollback;
