-- Synthetic append-only history checks; disposable database transaction only.
do $$
declare privilege_name text;
begin
  foreach privilege_name in array array['UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
    if has_table_privilege('service_role','public.bulk_operation_runs',privilege_name) then
      raise exception 'service_role unexpectedly holds % on immutable history', privilege_name;
    end if;
  end loop;
  if not has_table_privilege('service_role','public.bulk_operation_runs','INSERT')
     or not has_table_privilege('service_role','public.bulk_operation_runs','SELECT') then
    raise exception 'worker cannot append and read its history';
  end if;
  if has_table_privilege('anon','public.bulk_operation_runs','SELECT')
     or has_table_privilege('authenticated','public.bulk_operation_runs','INSERT') then
    raise exception 'browser history privileges widened';
  end if;
end $$;
set local role service_role;
insert into public.bulk_operation_runs(operation,run_id,status,error,started_at)
values ('zztest-history','zztest-failed','failed','synthetic failure','2026-01-01T00:00:00Z');
insert into public.bulk_operation_runs(operation,run_id,status,started_at,ended_at)
values ('zztest-history','zztest-success','succeeded','2026-01-02T00:00:00Z','2026-01-02T01:00:00Z');
do $$
begin
  if (select count(*) from public.bulk_operation_runs where operation='zztest-history') <> 2
     or not exists (select 1 from public.bulk_operation_runs where operation='zztest-history' and run_id='zztest-failed' and error='synthetic failure') then
    raise exception 'later success erased earlier failed outcome';
  end if;
  begin
    update public.bulk_operation_runs set error='overwritten' where operation='zztest-history';
    raise exception 'history update was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.bulk_operation_runs where operation='zztest-history';
    raise exception 'history deletion was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.bulk_operation_runs(operation,run_id,status,error,started_at)
    values ('zztest-history','zztest-failed','failed','retry','2026-01-01T00:00:00Z');
    raise exception 'duplicate run was allowed';
  exception when unique_violation then null;
  end;
  begin
    insert into public.bulk_operation_runs(operation,run_id,status,started_at)
    values ('zztest-history','zztest-silent','failed','2026-01-03T00:00:00Z');
    raise exception 'silent failure was allowed';
  exception when check_violation then null;
  end;
end $$;
reset role;

-- Exercise the actual JWT-aware app role functions, not an always-true stub.
-- The surrounding database-contract harness owns BEGIN/ROLLBACK.
select set_config('request.jwt.claim.sub', 'a2439000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"a2439000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"roles":["administrator"]}}', true);
set local role authenticated;
do $$
begin
  if not app.has_any_role(array['administrator']::app.app_role[]) then
    raise exception 'administrator fixture did not resolve through real role helper';
  end if;
  if (select count(*) from public.bulk_operation_runs where operation='zztest-history') <> 2 then
    raise exception 'administrator cannot read retained history';
  end if;
  begin
    insert into public.bulk_operation_runs(operation,run_id,status,started_at)
    values ('zztest-history','zztest-browser','succeeded',now());
    raise exception 'administrator browser append was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"sub":"a2439000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"roles":["viewer"]}}', true);
set local role authenticated;
do $$
begin
  if app.has_any_role(array['administrator']::app.app_role[]) then
    raise exception 'nonadministrator fixture unexpectedly has administrator role';
  end if;
  if exists (select 1 from public.bulk_operation_runs where operation='zztest-history') then
    raise exception 'ordinary browser can read private worker history';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $$
begin
  begin
    perform 1 from public.bulk_operation_runs;
    raise exception 'anonymous history read was allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role service_role;
do $$
begin
  begin
    truncate public.bulk_operation_runs;
    raise exception 'worker history truncation was allowed';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from public.bulk_operation_runs where operation='zztest-history') <> 2 then
    raise exception 'history changed during role denial checks';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- Issue #2670 -- the terminal-status vocabulary must match what production emits.
-- Production (qsllyeztdwjgirsysgai, 2026-09-10) writes 'completed' for a finished
-- run and never writes 'succeeded'. It also writes live-state words -- 'idle' with
-- a null run_id -- which are NOT run outcomes and must still be refused.
--
-- The refusal counter below is the point: each negative case increments it only
-- from inside a check_violation handler. If a rejection stopped rejecting, the
-- bare `raise exception` after the insert fires instead (SQLSTATE P0001, which the
-- handler does not catch) and this test fails; if a handler were ever widened to
-- swallow everything, the counter would still be short and the final assertion
-- fails. A check that cannot fail proves nothing, so this one is wired to fail
-- two different ways.
-- ---------------------------------------------------------------------------
set local role service_role;
do $$
declare
  refusals integer := 0;
  bad_status text;
begin
  -- ALLOWED: the exact status and shape production produced for the nightly
  -- style-group rebuild on 2026-09-10. A successful run carries no error and no
  -- reason_code, so this also proves bulk_operation_runs_failure_is_explained no
  -- longer demands an explanation from a success spelled 'completed'.
  insert into public.bulk_operation_runs
    (operation, run_id, status, source_status, progress, started_at, ended_at)
  values
    ('zztest-vocab', 'zztest-completed', 'completed', 'completed',
     '{"groups": 35974, "assigned": 98035}'::jsonb,
     '2026-09-10T06:00:03.776Z', '2026-09-10T08:12:40.259Z');

  if not exists (
       select 1 from public.bulk_operation_runs
        where operation = 'zztest-vocab' and run_id = 'zztest-completed'
          and succeeded
          and source_status = 'completed') then
    raise exception 'live production success status was not classified as a success';
  end if;

  -- ALLOWED: the other word production emits. Not a success, so it must explain
  -- itself, and it must NOT be classified as succeeded.
  insert into public.bulk_operation_runs
    (operation, run_id, status, source_status, reason_code, started_at)
  values
    ('zztest-vocab', 'zztest-interrupted', 'interrupted', 'interrupted',
     'worker_lost', '2026-09-10T06:00:00Z');

  if exists (
       select 1 from public.bulk_operation_runs
        where operation = 'zztest-vocab' and run_id = 'zztest-interrupted'
          and succeeded) then
    raise exception 'interrupted run was classified as a success';
  end if;

  -- ALLOWED, still: the vocabulary 20260909202801 published. This widening must
  -- not have narrowed anything.
  insert into public.bulk_operation_runs
    (operation, run_id, status, error, started_at)
  values ('zztest-vocab', 'zztest-legacy-failed', 'failed', 'synthetic', now());
  insert into public.bulk_operation_runs
    (operation, run_id, status, started_at)
  values ('zztest-vocab', 'zztest-legacy-succeeded', 'succeeded', now());

  if (select count(*) from public.bulk_operation_runs
       where operation = 'zztest-vocab' and succeeded) <> 2 then
    raise exception 'success classification does not cover both success spellings';
  end if;

  -- REFUSED: live-state words are not outcomes. 'idle' is the one production has
  -- sitting in seven operation keys right now, every one with a null run_id.
  foreach bad_status in array array['idle', 'running', 'stop_requested', 'stopping'] loop
    begin
      insert into public.bulk_operation_runs
        (operation, run_id, status, error, started_at)
      values ('zztest-vocab', 'zztest-bad-' || bad_status, bad_status, 'synthetic', now());
      raise exception 'non-terminal live status % was accepted into the run history', bad_status;
    exception when check_violation then
      refusals := refusals + 1;
    end;
  end loop;

  -- REFUSED: a blank raw status is not evidence of anything.
  begin
    insert into public.bulk_operation_runs
      (operation, run_id, status, source_status, started_at)
    values ('zztest-vocab', 'zztest-blank-source', 'completed', '   ', now());
    raise exception 'blank source_status was accepted';
  exception when check_violation then
    refusals := refusals + 1;
  end;

  -- REFUSED, unchanged: a non-success that explains nothing.
  begin
    insert into public.bulk_operation_runs
      (operation, run_id, status, started_at)
    values ('zztest-vocab', 'zztest-silent-interrupt', 'interrupted', now());
    raise exception 'unexplained non-success was accepted';
  exception when check_violation then
    refusals := refusals + 1;
  end;

  if refusals <> 6 then
    raise exception 'expected 6 vocabulary refusals, observed % -- a guard is not firing', refusals;
  end if;

  if (select count(*) from public.bulk_operation_runs where operation = 'zztest-vocab') <> 4 then
    raise exception 'a refused row was written to the run history anyway';
  end if;
end $$;
reset role;
