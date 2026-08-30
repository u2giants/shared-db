-- #1883: synthetic, rollback-only Disney OPA lifecycle contracts.

begin;

create temp table test_opa_property_lifecycle
  (like plm.opa_property including defaults including constraints);
create temp table test_opa_character_lifecycle
  (like plm.opa_character including defaults including constraints);

do $contract$
declare
  v_property_first_seen timestamptz := '2026-01-01 00:00:00+00';
  v_character_first_seen timestamptz := '2026-01-02 00:00:00+00';
  v_invalid_rejected boolean := false;
  v_missing_time_rejected boolean := false;
  v_active_time_rejected boolean := false;
begin
  insert into test_opa_property_lifecycle (
    licensed_property_id, property_name, first_seen_at, last_seen_at
  ) values (
    188300000001, 'Synthetic Property', v_property_first_seen, v_property_first_seen
  );

  insert into test_opa_character_lifecycle (
    character_id, character_name, first_seen_at, last_seen_at
  ) values (
    188300000002, 'Synthetic Character', v_character_first_seen, v_character_first_seen
  );

  if not exists (
    select 1 from test_opa_property_lifecycle
    where licensed_property_id = 188300000001
      and status = 'active' and withdrawn_at is null
  ) or not exists (
    select 1 from test_opa_character_lifecycle
    where character_id = 188300000002
      and status = 'active' and withdrawn_at is null
  ) then
    raise exception 'existing/new entity default lifecycle is not active';
  end if;

  update test_opa_property_lifecycle
  set status = 'withdrawn', withdrawn_at = '2026-02-01 00:00:00+00'
  where licensed_property_id = 188300000001;
  update test_opa_property_lifecycle
  set status = 'active', withdrawn_at = null, last_seen_at = '2026-03-01 00:00:00+00'
  where licensed_property_id = 188300000001;

  if not exists (
    select 1 from test_opa_property_lifecycle
    where licensed_property_id = 188300000001
      and status = 'active'
      and withdrawn_at is null
      and first_seen_at = v_property_first_seen
      and last_seen_at = '2026-03-01 00:00:00+00'
  ) then
    raise exception 'reappearance did not preserve original first-seen history';
  end if;

  begin
    update test_opa_property_lifecycle
    set status = 'missing'
    where licensed_property_id = 188300000001;
  exception when check_violation then
    v_invalid_rejected := true;
  end;

  begin
    update test_opa_character_lifecycle
    set status = 'withdrawn', withdrawn_at = null
    where character_id = 188300000002;
  exception when check_violation then
    v_missing_time_rejected := true;
  end;

  begin
    update test_opa_character_lifecycle
    set status = 'active', withdrawn_at = '2026-02-01 00:00:00+00'
    where character_id = 188300000002;
  exception when check_violation then
    v_active_time_rejected := true;
  end;

  if not v_invalid_rejected or not v_missing_time_rejected or not v_active_time_rejected then
    raise exception 'one or more lifecycle invariants accepted an invalid state';
  end if;
end
$contract$;

rollback;
