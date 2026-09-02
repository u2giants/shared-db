-- Concurrency contract for issue #2008:
-- api.db_data_admin_decide_property_match, CONCURRENT idempotency branch.
--
-- The sequential branch is covered by property_match_decision_contracts.sql.
-- This file covers the OTHER branch: the in-function exception handler that
-- runs when a second caller commits first and the losing call's insert hits a
-- unique violation. That branch must apply the SAME test as the sequential one
-- -- same reviewed row, same decision, same member set -- and must raise
-- rather than hand back another caller's verdict as if it were this caller's
-- own repeat. Returning the wrong verdict here is a royalty-attribution error.
--
-- Reaching that branch REQUIRES a real committed race: an uncommitted row is
-- waited on, not conflicted with, so the winning decision has to be committed
-- by a second connection while the loser is already inside the function. That
-- is what dblink is for here; without it the file SKIPs loudly rather than
-- pretending to have proven anything.
--
-- Consequence, stated plainly: the winner's rows COMMIT and the decision ledger
-- is append-only by design, so those rows cannot be removed afterwards. Every
-- fixture is synthetic and negative-keyed, no licensed row is used, the
-- residual identities end APPROVED (never pending, so they cannot appear in the
-- review queue), and the only cleanup possible -- the temporary role grants --
-- is performed.
-- The racing connections are opened by dblink, which refuses a passwordless
-- connection for a non-superuser. dblink runs INSIDE the server, so it must use
-- the server's own local socket -- the host and port psql was given are mapped
-- from outside and are not reachable from in there. Only the password is taken
-- from the environment psql is already using: nothing is hardcoded and no
-- credential is written into this repository.
\set pm_race_pw ''
\getenv pm_race_pw PGPASSWORD

select set_config(
  'pm_race.dsn',
  'dbname=' || current_database()
    || case when :'pm_race_pw' <> '' then ' password=' || :'pm_race_pw' else '' end,
  false);

begin;

do $t$
declare
  v_conn_a text := 'pm_race_win';
  v_conn_b text := 'pm_race_lose';
  v_dsn text;
  v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  v_search text;
  v_opa_a bigint;
  v_opa_b bigint;
  v_profile uuid;
  v_auth uuid;
  v_role_id uuid;
  v_pending_1 uuid := gen_random_uuid();
  v_pending_2 uuid := gen_random_uuid();
  v_request_1 uuid := gen_random_uuid();
  v_request_2 uuid := gen_random_uuid();
  v_status text;
  v_version bigint;
  v_repeat boolean;
  v_raised boolean := false;
  v_message text;
  v_result text;
begin
  v_search := 'Issue2008C-' || v_suffix;
  v_opa_a := -200800002001 - (abs(hashtext(v_suffix)) % 1000) * 10;
  v_opa_b := v_opa_a - 1;

  if not exists (select 1 from pg_extension where extname = 'dblink') then
    begin
      create extension dblink;
    exception when others then
      raise notice 'SKIP property_match_decision_concurrency: dblink unavailable (%)', sqlerrm;
      return;
    end;
  end if;

  v_dsn := coalesce(nullif(current_setting('pm_race.dsn', true), ''),
                    'dbname=' || current_database());

  select p.id, p.auth_user_id into v_profile, v_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id
  limit 1;
  if v_profile is null then
    raise exception 'no active profile fixture is available';
  end if;
  select r.id into v_role_id from app.role r where r.slug = 'licensing'::app.app_role;

  perform dblink_connect(v_conn_a, v_dsn);
  perform dblink_connect(v_conn_b, v_dsn);

  -- Committed setup. The racing sessions cannot see anything this test
  -- transaction writes, so the authorization and the fixtures must be real.
  perform dblink_exec(v_conn_a, format(
    'insert into app.user_role (profile_id, role_id) values (%L, %L) on conflict do nothing',
    v_profile, v_role_id));
  perform dblink_exec(v_conn_a, format(
    'insert into app.app_access (profile_id, app) values (%L, %L) on conflict do nothing',
    v_profile, 'plm'));

  perform dblink_exec(v_conn_a, format(
    'insert into plm.opa_property (licensed_property_id, property_name)
     values (%s, %L), (%s, %L)',
    v_opa_a, v_search || ' OPA A', v_opa_b, v_search || ' OPA B'));
  perform dblink_exec(v_conn_a, format(
    'insert into plm.dcp_property (source_system, source_id, display_name)
     values (%L, %L, %L), (%L, %L, %L)',
    'disney_dcpvault', v_search || '/1', v_search || ' One',
    'disney_dcpvault', v_search || '/2', v_search || ' Two'));

  perform dblink_exec(v_conn_a, format(
    'insert into plm.dcp_opa_property_resolution (
       resolution_id, source_system, source_table, source_property_id,
       decision_version, approval_status, evidence_reference, evidence_sha256,
       decision_reason)
     values (%L, %L, %L, %L, 1, %L, %L, %L, %L),
            (%L, %L, %L, %L, 1, %L, %L, %L, %L)',
    v_pending_1, 'disney_dcpvault', 'plm.dcp_property', v_search || '/1',
      'pending', 'synthetic-race-1', repeat('d', 64), 'synthetic pending one',
    v_pending_2, 'disney_dcpvault', 'plm.dcp_property', v_search || '/2',
      'pending', 'synthetic-race-2', repeat('e', 64), 'synthetic pending two'));

  -- ------------------------------------------------------------------
  -- RACE 1 -- DIVERGENT. The winner approves; the loser reuses the same
  -- client request id for a REJECT. The loser must raise, not inherit.
  -- ------------------------------------------------------------------
  perform dblink_exec(v_conn_a, 'begin');
  perform dblink_exec(v_conn_a, format('set local request.jwt.claim.sub = %L', v_auth::text));
  perform 1 from dblink(v_conn_a, format(
    'select api.db_data_admin_decide_property_match(%L, %L, array[%s, %s]::bigint[], %L, %L)::text',
    v_pending_1, 'approve', v_opa_a, v_opa_b, 'race winner approval', v_request_1)
  ) as w(x text);

  perform dblink_exec(v_conn_b, 'begin');
  perform dblink_exec(v_conn_b, format('set local request.jwt.claim.sub = %L', v_auth::text));
  perform dblink_send_query(v_conn_b, format(
    'select api.db_data_admin_decide_property_match(%L, %L, %L::bigint[], %L, %L)::text',
    v_pending_1, 'reject', '{}', 'race loser rejection', v_request_1));

  -- The loser must be INSIDE the function and blocked on the winner's
  -- uncommitted key before the winner commits. Without this the loser could
  -- read the committed row in its ordinary pre-check and never reach the
  -- concurrent branch at all -- the test would pass while proving nothing.
  perform pg_sleep(1.0);
  if (select count(*) from pg_stat_activity a
      where a.wait_event_type = 'Lock'
        and a.query like '%db_data_admin_decide_property_match%') = 0 then
    raise exception 'the losing call never blocked: the concurrent branch was not exercised';
  end if;

  -- Releasing the winner unblocks the loser inside the function, on the
  -- committed row rather than on a lock.
  perform dblink_exec(v_conn_a, 'commit');

  begin
    select x into v_result from dblink_get_result(v_conn_b) as r(x text);
  exception when others then
    v_raised := true;
    v_message := sqlerrm;
  end;

  if not v_raised then
    raise exception
      'concurrent branch returned % instead of refusing a different decision on a spent client request id',
      coalesce(v_result, '<null>');
  end if;
  if position('already recorded a different decision' in v_message) = 0 then
    raise exception 'concurrent branch refused for the wrong reason: %', v_message;
  end if;

  begin
    perform dblink_get_result(v_conn_b);
    perform dblink_exec(v_conn_b, 'rollback');
  exception when others then
    null;
  end;

  -- The winner's decision must stand, unaltered by the refused loser.
  select r.approval_status, r.decision_version
    into v_status, v_version
  from plm.dcp_opa_property_resolution r
  where r.resolution_id = v_request_1;
  if v_status is distinct from 'approved' or v_version is distinct from 2 then
    raise exception 'the winning decision was not preserved: % / %', v_status, v_version;
  end if;
  if (select count(*) from plm.dcp_opa_property_resolution_member m
      where m.resolution_id = v_request_1) <> 2 then
    raise exception 'the winning decision lost its members';
  end if;

  -- ------------------------------------------------------------------
  -- RACE 2 -- IDENTICAL. The same guard must NOT turn a genuine retry
  -- into a failure: an identical losing call is still an idempotent repeat.
  -- ------------------------------------------------------------------
  perform dblink_exec(v_conn_a, 'begin');
  perform dblink_exec(v_conn_a, format('set local request.jwt.claim.sub = %L', v_auth::text));
  perform 1 from dblink(v_conn_a, format(
    'select api.db_data_admin_decide_property_match(%L, %L, array[%s]::bigint[], %L, %L)::text',
    v_pending_2, 'approve', v_opa_a, 'race winner approval two', v_request_2)
  ) as w(x text);

  perform dblink_exec(v_conn_b, 'begin');
  perform dblink_exec(v_conn_b, format('set local request.jwt.claim.sub = %L', v_auth::text));
  perform dblink_send_query(v_conn_b, format(
    'select api.db_data_admin_decide_property_match(%L, %L, array[%s]::bigint[], %L, %L)::text',
    v_pending_2, 'approve', v_opa_a, 'race winner approval two', v_request_2));

  perform pg_sleep(1.0);
  if (select count(*) from pg_stat_activity a
      where a.wait_event_type = 'Lock'
        and a.query like '%db_data_admin_decide_property_match%') = 0 then
    raise exception 'the identical losing call never blocked: the concurrent branch was not exercised';
  end if;

  perform dblink_exec(v_conn_a, 'commit');

  v_raised := false;
  v_result := null;
  begin
    select x into v_result from dblink_get_result(v_conn_b) as r(x text);
  exception when others then
    v_raised := true;
    v_message := sqlerrm;
  end;

  if v_raised then
    raise exception 'an identical concurrent retry was refused: %', v_message;
  end if;
  if v_result is null then
    raise exception 'an identical concurrent retry returned nothing';
  end if;
  v_repeat := (v_result::jsonb ->> 'idempotent_repeat')::boolean;
  if not coalesce(v_repeat, false) then
    raise exception 'an identical concurrent retry was not reported as a repeat: %', v_result;
  end if;
  if (v_result::jsonb ->> 'resolution_id') <> v_request_2::text then
    raise exception 'an identical concurrent retry returned the wrong decision: %', v_result;
  end if;

  begin
    perform dblink_get_result(v_conn_b);
    perform dblink_exec(v_conn_b, 'rollback');
  exception when others then
    null;
  end;

  -- Exactly one version 2 exists per raced identity: the loser appended
  -- nothing behind the winner's back.
  if (select count(*) from plm.dcp_opa_property_resolution r
      where r.supersedes_resolution_id in (v_pending_1, v_pending_2)) <> 2 then
    raise exception 'a raced decision appended an extra version';
  end if;

  -- Cleanup of everything that CAN be cleaned. The ledger is append-only, so
  -- the two decided identities remain -- approved, never pending.
  perform dblink_exec(v_conn_a, format(
    'delete from app.app_access where profile_id = %L and app = %L', v_profile, 'plm'));
  perform dblink_exec(v_conn_a, format(
    'delete from app.user_role where profile_id = %L and role_id = %L', v_profile, v_role_id));

  perform dblink_disconnect(v_conn_a);
  perform dblink_disconnect(v_conn_b);
exception when others then
  begin
    perform dblink_disconnect(v_conn_a);
  exception when others then null;
  end;
  begin
    perform dblink_disconnect(v_conn_b);
  exception when others then null;
  end;
  raise;
end $t$;

rollback;
