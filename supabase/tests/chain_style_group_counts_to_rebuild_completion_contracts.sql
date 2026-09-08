-- Contracts for 20260908204414_chain_style_group_counts_to_rebuild_completion.sql (#2440).
--
-- What is being pinned:
--   1. Catalog posture of public.queue_nightly_rebuild_style_groups(): zero arguments,
--      RETURNS void, LANGUAGE plpgsql, SECURITY DEFINER, search_path=public, and EXECUTE
--      granted to authenticated, service_role and postgres.
--   2. Cron state. The clock-driven reconcile job is GONE - `nightly-reconcile-sg-asset-counts`
--      must not exist - and `nightly-rebuild-style-groups` runs on `*/10 * * * *` with its
--      command unchanged. This is the whole point of #2440 and the one thing a later
--      migration could silently undo.
--   3. Requirement 1: a rebuild that did NOT reach status 'completed' triggers no
--      reconcile. Set up a 'failed' run and prove the reconcile marker never moves.
--   4. Requirement 2: idempotence is keyed on run_id, not on status. A 'completed' run
--      whose run_id was already reconciled triggers nothing, however many times the poll
--      fires.
--   5. Requirement 3: the floor arm exists and is time-based - an operation sitting at
--      'failed' with a reconcile older than 7 days DOES reconcile, so the counts cannot
--      go silent indefinitely.
--   6. The marker lives under its own top-level BULK_OPERATIONS key, NOT inside the
--      'rebuild-style-groups' object that public.update_bulk_operation replaces wholesale.
--
-- Every behavioural step below FAILS against the pre-#2440 body, which had no arms at all:
-- it would enqueue (or skip) and never write a 'style-group-counts-reconcile' key.
--
-- Steps 5 and 7 actually run the reconcile, which walks every style group. They are
-- therefore GUARDED on the size of public.style_groups and are skipped with a notice on a
-- production-sized dataset; the negative steps, which carry the two guarantees most at
-- risk, always run.

begin;

do $catalog$
declare
  v_oid     oid;
  v_prokind "char";
  v_secdef  boolean;
  v_lang    name;
  v_rettype text;
  v_config  text[];
  v_missing text;
begin
  select p.oid, p.prokind, p.prosecdef, l.lanname,
         pg_catalog.format_type(p.prorettype, null), p.proconfig
    into v_oid, v_prokind, v_secdef, v_lang, v_rettype, v_config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  where n.nspname = 'public'
    and p.proname = 'queue_nightly_rebuild_style_groups'
    and p.pronargs = 0;

  if v_oid is null then
    raise exception 'CONTRACT: public.queue_nightly_rebuild_style_groups() is missing. Issue #2440 replaces this exact signature and must not change it.';
  end if;

  if v_prokind is distinct from 'f' then
    raise exception 'CONTRACT: queue_nightly_rebuild_style_groups is no longer a plain function (prokind=%).', v_prokind;
  end if;

  if v_rettype is distinct from 'void' then
    raise exception 'CONTRACT: queue_nightly_rebuild_style_groups must return void, found %. The pg_cron command SELECTs it directly.', v_rettype;
  end if;

  if v_lang is distinct from 'plpgsql' then
    raise exception 'CONTRACT: queue_nightly_rebuild_style_groups must be plpgsql (the three arms need control flow), found %.', v_lang;
  end if;

  if not v_secdef then
    raise exception 'CONTRACT: queue_nightly_rebuild_style_groups lost SECURITY DEFINER. pg_cron runs it as postgres, but the admin_config write and the reconcile both depend on definer rights.';
  end if;

  if v_config is null or not (v_config @> array['search_path=public']) then
    raise exception 'CONTRACT: queue_nightly_rebuild_style_groups must pin search_path=public on a SECURITY DEFINER function. proconfig=%', v_config;
  end if;

  select string_agg(r.rolname, ', ' order by r.rolname)
    into v_missing
  from (values ('authenticated'), ('service_role'), ('postgres')) as r(rolname)
  where not has_function_privilege(r.rolname, v_oid, 'EXECUTE');

  if v_missing is not null then
    raise exception 'CONTRACT: EXECUTE on queue_nightly_rebuild_style_groups() is missing for: %', v_missing;
  end if;

  raise notice 'OK: catalog posture of queue_nightly_rebuild_style_groups() is intact.';
end $catalog$;

do $cron_state$
declare
  v_count    integer;
  v_schedule text;
  v_command  text;
  v_active   boolean;
begin
  if to_regclass('cron.job') is null then
    raise notice 'SKIP: pg_cron is not installed in this database; cron contracts not evaluated.';
    return;
  end if;

  -- (1) The clock-driven reconcile is gone. This is #2440's stated outcome.
  select count(*) into v_count
  from cron.job
  where jobname = 'nightly-reconcile-sg-asset-counts';

  if v_count <> 0 then
    raise exception 'CONTRACT: cron job "nightly-reconcile-sg-asset-counts" still exists (% row(s)). Issue #2440 deletes its 45 3 * * * schedule; the reconcile is now driven by the rebuild completing.', v_count;
  end if;

  -- (2) The driver job kept its name and command; only the cadence changed.
  select schedule, command, active
    into v_schedule, v_command, v_active
  from cron.job
  where jobname = 'nightly-rebuild-style-groups';

  if v_schedule is null then
    raise exception 'CONTRACT: cron job "nightly-rebuild-style-groups" is missing. It is the poll that drives all three arms; without it nothing rebuilds and nothing reconciles.';
  end if;

  if v_schedule is distinct from '*/10 * * * *' then
    raise exception 'CONTRACT: "nightly-rebuild-style-groups" must poll every 10 minutes, found schedule "%". A daily schedule would delay the chained reconcile by up to a day, which is the defect #2440 removes.', v_schedule;
  end if;

  if v_command not like '%queue_nightly_rebuild_style_groups%' then
    raise exception 'CONTRACT: "nightly-rebuild-style-groups" no longer calls queue_nightly_rebuild_style_groups(). Command is: %', v_command;
  end if;

  if not coalesce(v_active, false) then
    raise exception 'CONTRACT: cron job "nightly-rebuild-style-groups" is inactive.';
  end if;

  raise notice 'OK: reconcile job unscheduled; rebuild driver polls on */10 * * * *.';
end $cron_state$;

do $behaviour$
declare
  c_op     constant text := 'rebuild-style-groups';
  c_marker constant text := 'style-group-counts-reconcile';
  c_guard  constant integer := 2000;

  v_groups   bigint;
  v_baseline jsonb;
  v_marker   jsonb;
  v_reason   text;
  v_run      text;
  v_at       text;
begin
  select count(*) into v_groups from public.style_groups;

  -- ------------------------------------------------------------------
  -- Requirement 1: a run that did not complete must not trigger anything.
  -- ------------------------------------------------------------------
  v_baseline := jsonb_build_object(
    c_op, jsonb_build_object(
      'status', 'failed',
      'run_id', '11111111-1111-1111-1111-111111111111'
    ),
    c_marker, jsonb_build_object(
      'last_enqueued_at',       now()::text,          -- blocks the enqueue arm today
      'last_reconciled_at',     now()::text,          -- blocks the floor arm
      'last_reconciled_run_id', '00000000-0000-0000-0000-000000000000',
      'last_reconcile_reason',  'seed'
    )
  );

  insert into public.admin_config (key, value, updated_at)
  values ('BULK_OPERATIONS', v_baseline, now())
  on conflict (key) do update
    set value = excluded.value, updated_at = excluded.updated_at;

  perform public.queue_nightly_rebuild_style_groups();

  select value -> c_marker into v_marker from public.admin_config where key = 'BULK_OPERATIONS';

  if v_marker ->> 'last_reconcile_reason' is distinct from 'seed' then
    raise exception 'CONTRACT (#2440 req 1): a rebuild with status "failed" triggered a reconcile (reason became %). The trigger condition must be status = ''completed'', never "the status changed".',
      v_marker ->> 'last_reconcile_reason';
  end if;

  if (select value -> c_op ->> 'status' from public.admin_config where key = 'BULK_OPERATIONS') = 'queued' then
    raise exception 'CONTRACT: the enqueue arm fired despite an enqueue already recorded for today. The once-per-UTC-day gate is broken and the poll would queue a rebuild every 10 minutes.';
  end if;

  raise notice 'OK req 1: a failed rebuild triggers no reconcile.';

  -- ------------------------------------------------------------------
  -- Requirement 2: idempotence is keyed on run_id, not on status alone.
  -- ------------------------------------------------------------------
  v_baseline := jsonb_build_object(
    c_op, jsonb_build_object(
      'status', 'completed',
      'run_id', '22222222-2222-2222-2222-222222222222'
    ),
    c_marker, jsonb_build_object(
      'last_enqueued_at',       now()::text,
      'last_reconciled_at',     now()::text,
      'last_reconciled_run_id', '22222222-2222-2222-2222-222222222222',  -- same run
      'last_reconcile_reason',  'seed'
    )
  );

  update public.admin_config set value = v_baseline, updated_at = now()
  where key = 'BULK_OPERATIONS';

  perform public.queue_nightly_rebuild_style_groups();

  select value -> c_marker into v_marker from public.admin_config where key = 'BULK_OPERATIONS';

  if v_marker ->> 'last_reconcile_reason' is distinct from 'seed' then
    raise exception 'CONTRACT (#2440 req 2): a completed run that was ALREADY reconciled was reconciled again (reason became %). Keyed on status alone, a stuck "completed" would re-run the full recompute every 10 minutes forever.',
      v_marker ->> 'last_reconcile_reason';
  end if;

  raise notice 'OK req 2: an already-reconciled run_id is not reconciled twice.';

  -- ------------------------------------------------------------------
  -- Requirement 6: the marker is its own top-level key, not part of the
  -- worker-owned operation object.
  -- ------------------------------------------------------------------
  if (select value -> c_op -> 'last_reconciled_at' from public.admin_config where key = 'BULK_OPERATIONS') is not null then
    raise exception 'CONTRACT: the reconcile marker was written inside the "%" object. public.update_bulk_operation replaces that object wholesale on every worker progress update, so the marker would be erased and idempotence lost.', c_op;
  end if;

  raise notice 'OK: marker is a separate top-level BULK_OPERATIONS key.';

  if v_groups > c_guard then
    raise notice 'SKIP: public.style_groups holds % rows (> %); the two positive reconcile steps would run the full recompute and are not executed here.', v_groups, c_guard;
    return;
  end if;

  -- ------------------------------------------------------------------
  -- Requirement 2 (positive half): a NEW completed run does reconcile.
  -- ------------------------------------------------------------------
  v_baseline := jsonb_build_object(
    c_op, jsonb_build_object(
      'status', 'completed',
      'run_id', '33333333-3333-3333-3333-333333333333'
    ),
    c_marker, jsonb_build_object(
      'last_enqueued_at',       now()::text,
      'last_reconciled_at',     now()::text,
      'last_reconciled_run_id', '22222222-2222-2222-2222-222222222222',  -- a different run
      'last_reconcile_reason',  'seed'
    )
  );

  update public.admin_config set value = v_baseline, updated_at = now()
  where key = 'BULK_OPERATIONS';

  perform public.queue_nightly_rebuild_style_groups();

  select value -> c_marker into v_marker from public.admin_config where key = 'BULK_OPERATIONS';
  v_reason := v_marker ->> 'last_reconcile_reason';
  v_run    := v_marker ->> 'last_reconciled_run_id';

  if v_reason is distinct from 'rebuild_completed' then
    raise exception 'CONTRACT (#2440 req 2): a newly completed run did NOT trigger the chained reconcile (reason = %). Without this arm the counts are never refreshed at all, because the clock job is gone.', coalesce(v_reason, '<null>');
  end if;

  if v_run is distinct from '33333333-3333-3333-3333-333333333333' then
    raise exception 'CONTRACT: the reconciled run_id was not recorded (found %). Without it the next poll reconciles the same run again.', coalesce(v_run, '<null>');
  end if;

  if v_marker -> 'last_reconcile_rows_written' is null then
    raise exception 'CONTRACT: last_reconcile_rows_written was not recorded. It is part of the detector that makes the new silent failure mode observable.';
  end if;

  raise notice 'OK req 2 (positive): a new completed run reconciles once and records its run_id.';

  -- ------------------------------------------------------------------
  -- Requirement 3: the floor. Silence must be bounded even if the rebuild
  -- never reaches 'completed' again.
  -- ------------------------------------------------------------------
  v_baseline := jsonb_build_object(
    c_op, jsonb_build_object(
      'status', 'failed',
      'run_id', '44444444-4444-4444-4444-444444444444'
    ),
    c_marker, jsonb_build_object(
      'last_enqueued_at',       now()::text,
      'last_reconciled_at',     (now() - interval '30 days')::text,
      'last_reconciled_run_id', '22222222-2222-2222-2222-222222222222',
      'last_reconcile_reason',  'seed'
    )
  );

  update public.admin_config set value = v_baseline, updated_at = now()
  where key = 'BULK_OPERATIONS';

  perform public.queue_nightly_rebuild_style_groups();

  select value -> c_marker into v_marker from public.admin_config where key = 'BULK_OPERATIONS';
  v_reason := v_marker ->> 'last_reconcile_reason';
  v_run    := v_marker ->> 'last_reconciled_run_id';
  v_at     := v_marker ->> 'last_reconciled_at';

  if v_reason is distinct from 'floor' then
    raise exception 'CONTRACT (#2440 req 3): the weekly floor did not fire after 30 days without a reconcile (reason = %). Issue #2437''s rule: a change that introduces a new failure mode must not ship without a detector, and this design''s new failure mode is silence.', coalesce(v_reason, '<null>');
  end if;

  if v_run is distinct from '22222222-2222-2222-2222-222222222222' then
    raise exception 'CONTRACT: a floor pass overwrote last_reconciled_run_id with % . It must carry the previous value forward, or the failed run would be treated as reconciled and skipped once it finally succeeds.', coalesce(v_run, '<null>');
  end if;

  if v_at::timestamptz < now() - interval '1 day' then
    raise exception 'CONTRACT: the floor pass did not stamp last_reconciled_at (still %), so it would re-fire on every poll.', v_at;
  end if;

  raise notice 'OK req 3: the 7-day floor fires and bounds the silence.';
end $behaviour$;

rollback;
