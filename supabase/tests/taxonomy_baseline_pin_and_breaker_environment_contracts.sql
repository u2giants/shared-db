-- Rollback-safe contract tests for
--   20260804120000_taxonomy_baseline_pins_table.sql
--   20260804120100_taxonomy_breaker_environment_and_provenance.sql
--
-- Run against preview AFTER both migrations are applied. Every fixture rolls back.
--
-- Proves, for the baseline pins:
--   * the expected baseline is DATA, not compiled-in constants -- the function
--     bodies contain no literal hash, and the retired 2026-08-02 hash
--     d9b07759bf80ff227e2fa9bd635d2138 appears in neither of them
--   * all twelve metrics have exactly one live pin, and the live licensor status
--     hash is the post-owner-ruling value
--   * a live observation passes with baseline_ok = true carrying the NEW hash
--   * changing a pin changes the verdict -- i.e. the gate really reads the table
--     (the test that distinguishes "fixed the baseline" from "muted the alarm")
--   * a forced drill STILL produces a critical alert after the fix
--   * the pin table is append-only: DELETE refused, value UPDATE refused,
--     superseded_at may be stamped once
--   * the guard is STRUCTURAL, not role-based: it fires while auth.role() is NULL,
--     which is exactly the state inside a migration
--   * an incomplete or unknown baseline RAISES rather than reading as green
--
-- Proves, for the breaker environment:
--   * environment holds a deployment identifier, never a version number and never
--     a cause description
--   * trip provenance lands in trip_provenance
--   * the environment fallback is never server_version_num

begin;

do $$
declare
  v_health_def text;
  v_obs_def text;
  v_trip_def text;
  v_live_pins integer;
  v_hash text;
  v_res jsonb;
  v_state jsonb;
  v_raised boolean;
  v_alert record;
  v_env text;
  v_prov text;
  v_breaker record;
begin
  -- ------------------------------------------------------------------
  -- 1. The baseline is no longer compiled into the functions
  -- ------------------------------------------------------------------
  v_health_def := pg_get_functiondef('plm.check_taxonomy_sync_health(interval,jsonb)'::regprocedure);
  v_obs_def := pg_get_functiondef('plm.record_taxonomy_parallel_observation(date,jsonb)'::regprocedure);

  if position('taxonomy_baseline_pin_set' in v_health_def) = 0 then
    raise exception 'FAIL: check_taxonomy_sync_health does not read plm.taxonomy_baseline_pin';
  end if;
  if position('taxonomy_baseline_pin_set' in v_obs_def) = 0 then
    raise exception 'FAIL: record_taxonomy_parallel_observation does not read plm.taxonomy_baseline_pin';
  end if;

  -- The stale pin that caused the 2026-08-02..04 alert storm must not survive
  -- anywhere in either body.
  if position('d9b07759bf80ff227e2fa9bd635d2138' in v_health_def) > 0
     or position('d9b07759bf80ff227e2fa9bd635d2138' in v_obs_def) > 0 then
    raise exception 'FAIL: the retired licensor status hash is still hardcoded in a health/observation function';
  end if;

  -- ------------------------------------------------------------------
  -- 2. Exactly one live pin per metric, and the live hash is the new one
  -- ------------------------------------------------------------------
  select count(*) into v_live_pins
  from plm.taxonomy_baseline_pin
  where baseline_key = 'phase4_preview' and superseded_at is null;

  if v_live_pins <> 12 then
    raise exception 'FAIL: expected 12 live pins, found %', v_live_pins;
  end if;

  select expected_text into v_hash
  from plm.taxonomy_baseline_pin
  where baseline_key = 'phase4_preview'
    and metric_key = 'licensor_status_hash'
    and superseded_at is null;

  if v_hash <> '00bf7069fff79b9deab1d14dbd9112b2' then
    raise exception 'FAIL: live licensor_status_hash pin is %, expected the post-owner-ruling value', v_hash;
  end if;

  -- Every pin must carry provenance. A pin with no stated reason is how the
  -- previous one rotted unnoticed.
  if exists (
    select 1 from plm.taxonomy_baseline_pin
    where baseline_key = 'phase4_preview'
      and (btrim(coalesce(pinned_reason, '')) = '' or btrim(coalesce(pinned_by, '')) = '')
  ) then
    raise exception 'FAIL: a baseline pin is missing pinned_by or pinned_reason';
  end if;

  -- ------------------------------------------------------------------
  -- 3. POSITIVE PATH: the observation passes with the new hash
  -- ------------------------------------------------------------------
  v_res := plm.record_taxonomy_parallel_observation(p_options => '{"skip_alert": true}'::jsonb);

  if (v_res ->> 'baseline_ok')::boolean is not true then
    raise exception 'FAIL: baseline_ok is not true after the refresh: %', v_res;
  end if;
  if (v_res ->> 'licensor_status_hash') <> '00bf7069fff79b9deab1d14dbd9112b2' then
    raise exception 'FAIL: observation did not carry the new licensor status hash: %',
      v_res ->> 'licensor_status_hash';
  end if;

  -- ------------------------------------------------------------------
  -- 4. The gate really reads the table -- change a pin, the verdict flips.
  --    Without this, a passing baseline proves nothing about where the
  --    expected value came from.
  -- ------------------------------------------------------------------
  update plm.taxonomy_baseline_pin
     set superseded_at = now()
   where baseline_key = 'phase4_preview'
     and metric_key = 'licensor_status_hash'
     and superseded_at is null;

  insert into plm.taxonomy_baseline_pin (
    baseline_key, metric_key, metric_kind, expected_text, effective_from,
    pinned_by, pinned_reason, source_migration
  ) values (
    'phase4_preview', 'licensor_status_hash', 'hash',
    '00000000000000000000000000000000', now(),
    'contract-test', 'deliberately wrong pin, rolled back', 'contract-test'
  );

  v_res := plm.record_taxonomy_parallel_observation(p_options => '{"skip_alert": true}'::jsonb);

  if (v_res ->> 'baseline_ok')::boolean is not false then
    raise exception 'FAIL: a deliberately wrong pin still reported baseline_ok -- the gate is not reading the table';
  end if;

  -- No cleanup here on purpose. The append-only guard refuses both the DELETE of
  -- the fixture pin and the un-supersede of the real one -- correctly, and proven
  -- in section 5. The enclosing ROLLBACK is what restores the table, which is why
  -- this is the last assertion in the block.

  raise notice 'OK: baseline gate reads plm.taxonomy_baseline_pin';
end;
$$;

rollback;

-- The append-only guard refuses DELETE/UPDATE, so the section above cannot run
-- inside the same DO block as the guard tests. Fresh transaction.

begin;

do $$
declare
  v_raised boolean;
begin
  -- ------------------------------------------------------------------
  -- 5. The guard is STRUCTURAL, not role-based.
  --    auth.role() is NULL here -- the exact condition under which a guard
  --    written as `if not (... or auth.role() = 'service_role')` would never
  --    fire. These must still be refused.
  -- ------------------------------------------------------------------
  if auth.role() is not null then
    raise exception 'FAIL: this test must run with auth.role() NULL to be meaningful, got %', auth.role();
  end if;

  v_raised := false;
  begin
    delete from plm.taxonomy_baseline_pin
     where baseline_key = 'phase4_preview' and metric_key = 'licensor_status_hash';
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'FAIL: DELETE of a baseline pin was allowed';
  end if;

  v_raised := false;
  begin
    update plm.taxonomy_baseline_pin
       set expected_text = 'deadbeefdeadbeefdeadbeefdeadbeef'
     where baseline_key = 'phase4_preview' and metric_key = 'licensor_status_hash';
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'FAIL: in-place UPDATE of a pin value was allowed';
  end if;

  -- superseded_at is the one permitted update.
  update plm.taxonomy_baseline_pin
     set superseded_at = now()
   where baseline_key = 'phase4_preview' and metric_key = 'licensor_status_hash'
     and superseded_at is null;

  -- ------------------------------------------------------------------
  -- 6. An incomplete baseline RAISES. It must never read as "nothing to
  --    compare", which would turn the whole gate into a no-op reporting green.
  -- ------------------------------------------------------------------
  v_raised := false;
  begin
    perform plm.taxonomy_baseline_pin_set('phase4_preview');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'FAIL: an incomplete baseline did not raise';
  end if;

  v_raised := false;
  begin
    perform plm.taxonomy_baseline_pin_set('a_baseline_that_does_not_exist');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'FAIL: an unknown baseline key did not raise';
  end if;

  raise notice 'OK: append-only guard and fail-loud accessor';
end;
$$;

rollback;

begin;

do $$
declare
  v_res jsonb;
  v_alert record;
  v_trip_def text;
  v_breaker record;
begin
  -- ------------------------------------------------------------------
  -- 7. NEGATIVE PATH: a forced drill must STILL produce a critical alert.
  --    Refreshing a baseline and muting an alarm look identical unless this
  --    passes alongside section 3.
  -- ------------------------------------------------------------------
  v_res := plm.check_taxonomy_sync_health(interval '36 hours', '{"force_fail": true}'::jsonb);

  if (v_res ->> 'ok')::boolean is not false then
    raise exception 'FAIL: a forced drill reported ok';
  end if;
  if (v_res ->> 'alert_id') is null then
    raise exception 'FAIL: a forced drill produced no alert -- the alarm is muted';
  end if;

  select * into v_alert from plm.taxonomy_sync_alert where id = (v_res ->> 'alert_id')::uuid;

  if v_alert.severity <> 'critical' then
    raise exception 'FAIL: drill alert severity is %, expected critical', v_alert.severity;
  end if;
  if v_alert.is_drill is not true then
    raise exception 'FAIL: drill alert is not flagged is_drill';
  end if;

  -- ------------------------------------------------------------------
  -- 8. Breaker environment vs provenance
  -- ------------------------------------------------------------------
  v_trip_def := pg_get_functiondef(
    'plm.trip_taxonomy_circuit_breaker(text,text,text,uuid,text,text,boolean,jsonb,text)'::regprocedure);

  -- The fallback must never be a PostgreSQL version number again.
  if position('server_version_num' in v_trip_def) > 0 then
    raise exception 'FAIL: trip_taxonomy_circuit_breaker still falls back to server_version_num';
  end if;
  if position('resolve_deployment_environment' in v_trip_def) = 0 then
    raise exception 'FAIL: trip_taxonomy_circuit_breaker does not resolve a deployment environment';
  end if;

  select * into v_breaker
  from plm.taxonomy_circuit_breaker where lane = 'coldlion_licensor_property';

  if v_breaker.environment ~ '^[0-9]+$' then
    raise exception 'FAIL: breaker environment is a bare number (%), not an environment', v_breaker.environment;
  end if;
  if v_breaker.environment like 'auto (%' then
    raise exception 'FAIL: breaker environment still holds provenance (%)', v_breaker.environment;
  end if;

  -- The provenance string must have been preserved, not discarded.
  if v_breaker.state = 'tripped'
     and v_breaker.tripped_by = 'auto-trip'
     and coalesce(v_breaker.trip_provenance, '') = '' then
    raise exception 'FAIL: an auto-trip lost its provenance instead of moving it to trip_provenance';
  end if;

  -- Every historical auto-trip event kept its provenance too.
  if exists (
    select 1 from plm.taxonomy_circuit_breaker_event
    where environment like 'auto (%' and trip_provenance is null
  ) then
    raise exception 'FAIL: a breaker event lost its provenance';
  end if;

  raise notice 'OK: drill still alerts; environment and provenance are separate';
end;
$$;

rollback;
