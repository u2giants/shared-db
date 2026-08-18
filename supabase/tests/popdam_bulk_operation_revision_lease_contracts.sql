-- =====================================================================================
-- PopDAM bulk-operation revision + submission-lease contract tests
-- Issue u2giants/shared-db#1171, claim #1174, for u2giants/popdam3#92.
--
-- Everything below runs inside one transaction that is rolled back, so it may write
-- the real admin_config BULK_OPERATIONS row freely.
--
-- Proves, in order:
--   1. legacy three-argument calls behave exactly as before on unprotected state
--   2. only ONE worker can claim a given revision/lease
--   3. an expired submission lease with no saved provider_batch_id becomes AMBIGUOUS
--      and never a second submission slot
--   4. legacy callers (single and batch) stay compatible but cannot overwrite
--      protected external-job state
--   5. p_only_if_status = 'running' and Stop protection still hold
-- =====================================================================================

begin;

-- The "Database Contract Tests" workflow replays migrations into an EMPTY database and
-- never applies supabase/ci-bootstrap, so public.admin_config does not exist there. It is
-- a four-column config table and the functions under test are what this file actually
-- proves, so the table is created if (and only if) it is missing. On preview, production
-- and any adopted database this is a no-op against the real table, and the whole
-- transaction is rolled back either way.
create table if not exists public.admin_config (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone default now() not null,
  updated_by uuid);

do $bootstrap$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.admin_config'::regclass and contype = 'p'
  ) then
    alter table public.admin_config add primary key (key);
  end if;
end $bootstrap$;

do $$
declare
  v_out    jsonb;
  v_stored jsonb;
  v_failed boolean;
begin
  -- ---------------------------------------------------------------------------------
  -- Clean, deterministic starting point for this transaction only.
  -- ---------------------------------------------------------------------------------
  insert into admin_config (key, value, updated_at)
  values ('BULK_OPERATIONS', '{}'::jsonb, now())
  on conflict (key) do update set value = '{}'::jsonb, updated_at = now();

  -- =================================================================================
  -- 1. LEGACY THREE-ARGUMENT COMPATIBILITY (unprotected state)
  -- =================================================================================
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 0)));

  if v_out -> 'ai-tag-untagged' ->> 'status' is distinct from 'running' then
    raise exception 'legacy call did not return the whole BULK_OPERATIONS object as before: %', v_out;
  end if;
  if v_out ? 'ok' then
    raise exception 'legacy call must NOT return the guarded proof envelope: %', v_out;
  end if;

  -- Historical conditional no-op: wrong expected status returns current state unchanged.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'idle'),
    'stopped');
  if v_out -> 'ai-tag-untagged' ->> 'status' is distinct from 'running' then
    raise exception 'p_only_if_status no-op changed state: %', v_out;
  end if;

  -- Matching expected status still writes.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'running', 'state_revision', 0),
    'running');
  if v_out -> 'ai-tag-untagged' ->> 'status' is distinct from 'running' then
    raise exception 'legacy conditional write did not apply: %', v_out;
  end if;

  -- =================================================================================
  -- 2. ONLY ONE WORKER CAN CLAIM A GIVEN REVISION / LEASE
  -- =================================================================================

  -- Worker A claims revision 0 and a 120 second submission lease.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-1')),
    'running',
    0,
    'worker-A',
    120);

  if (v_out ->> 'ok')::boolean is not true then
    raise exception 'worker A could not claim a free revision: %', v_out;
  end if;
  if (v_out ->> 'state_revision')::bigint <> 1 then
    raise exception 'guarded write did not stamp state_revision 1: %', v_out;
  end if;
  if v_out ->> 'submission_owner' is distinct from 'worker-A' then
    raise exception 'saved state does not prove the submission owner: %', v_out;
  end if;
  if v_out ->> 'lease_expires_at' is null then
    raise exception 'saved state does not prove a lease expiry: %', v_out;
  end if;
  if v_out ->> 'external_job_phase' is distinct from 'submitting' then
    raise exception 'saved state does not prove the external_job phase: %', v_out;
  end if;

  -- The envelope must reflect what is STORED, not what was passed in.
  select value -> 'ai-tag-untagged' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ->> 'submission_owner' is distinct from 'worker-A'
     or coalesce(v_stored ->> 'state_revision', '') <> '1' then
    raise exception 'stored row does not match the returned proof envelope: %', v_stored;
  end if;

  -- Worker B replays the SAME expected revision. This is the overlapping-Railway-deploy
  -- case: it must lose, and must not touch stored state.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-1')),
    'running',
    0,
    'worker-B',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'revision_conflict' then
    raise exception 'a second worker claimed the same revision: %', v_out;
  end if;
  select value -> 'ai-tag-untagged' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ->> 'submission_owner' is distinct from 'worker-A' then
    raise exception 'the losing claim mutated stored state: %', v_stored;
  end if;

  -- Worker B now uses the CURRENT revision but the lease is still live and held by A.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-1')),
    'running',
    1,
    'worker-B',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_held' then
    raise exception 'a live submission lease was stolen: %', v_out;
  end if;

  -- Worker A saves the accepted provider batch id and can PROVE it was stored.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object(
        'phase', 'pending',
        'run_id', 'run-1',
        'provider_batch_id', 'batch_abc',
        'submission_owner', 'worker-A',
        'lease_expires_at', (now() + interval '120 seconds'))),
    'running',
    1);
  if (v_out ->> 'ok')::boolean is not true
     or v_out ->> 'provider_batch_id' <> 'batch_abc'
     or (v_out ->> 'state_revision')::bigint <> 2 then
    raise exception 'saving the accepted provider batch id was not provable: %', v_out;
  end if;

  -- A saved provider batch id can never be re-pointed at a different provider job.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'pending', 'provider_batch_id', 'batch_OTHER')),
    'running',
    2);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'external_job_protected' then
    raise exception 'a saved provider_batch_id was re-pointed: %', v_out;
  end if;

  -- The owner that proved it read revision 2 may deliberately clear a finished job.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 100)),
    'running',
    2);
  if (v_out ->> 'ok')::boolean is not true
     or v_out ->> 'external_job_phase' is not null
     or (v_out ->> 'state_revision')::bigint <> 3 then
    raise exception 'the proving owner could not clear a completed external_job: %', v_out;
  end if;

  -- =================================================================================
  -- 3. EXPIRED LEASE WITH NO BATCH ID => AMBIGUITY, NEVER A RESUBMISSION
  -- =================================================================================
  update admin_config
     set value = jsonb_set(value, array['ai-tag-all'], jsonb_build_object(
           'status', 'running',
           'state_revision', 5,
           'external_job', jsonb_build_object(
             'phase', 'submitting',
             'run_id', 'run-9',
             'submission_owner', 'worker-A',
             'lease_expires_at', (now() - interval '10 seconds'))))
   where key = 'BULK_OPERATIONS';

  v_out := public.update_bulk_operation(
    'ai-tag-all',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-9')),
    'running',
    5,
    'worker-B',
    120);

  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'ambiguous_submission' then
    raise exception 'an expired lease with no provider_batch_id handed out a new submission slot: %', v_out;
  end if;
  if v_out ->> 'external_job_phase' <> 'ambiguous_submission' then
    raise exception 'the ambiguity was not made durable: %', v_out;
  end if;
  if (v_out ->> 'state_revision')::bigint <> 6 then
    raise exception 'the durable ambiguity did not advance the revision: %', v_out;
  end if;
  if v_out ->> 'submission_owner' is distinct from 'worker-A' then
    raise exception 'the ambiguity lost the prior submission owner: %', v_out;
  end if;

  select value -> 'ai-tag-all' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ->> 'phase' <> 'ambiguous_submission'
     or v_stored -> 'external_job' ->> 'ambiguous_reason'
        <> 'submission_lease_expired_without_provider_batch_id' then
    raise exception 'ambiguity is not readable from stored state: %', v_stored;
  end if;

  -- Retrying against the new revision still refuses: ambiguity is terminal until a
  -- human/explicit reconciliation flow resolves it.
  v_out := public.update_bulk_operation(
    'ai-tag-all',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-9')),
    'running',
    6,
    'worker-B',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'ambiguous_submission' then
    raise exception 'an ambiguous submission was auto-resubmitted: %', v_out;
  end if;

  -- A guarded caller with the exact current revision still cannot clear ambiguity.
  v_out := public.update_bulk_operation(
    'ai-tag-all',
    jsonb_build_object('status', 'idle'),
    null,
    6);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'ambiguous_submission' then
    raise exception 'ambiguity was cleared by an ordinary guarded write: %', v_out;
  end if;

  -- =================================================================================
  -- 4. LEGACY CALLERS: COMPATIBLE, BUT CANNOT OVERWRITE PROTECTED STATE
  -- =================================================================================

  -- 4a. A live protected job. Set one up on its own key.
  update admin_config
     set value = jsonb_set(value, array['ai-tag-groups'], jsonb_build_object(
           'status', 'running',
           'state_revision', 4,
           'external_job', jsonb_build_object(
             'phase', 'pending',
             'provider_batch_id', 'batch_live',
             'submission_owner', 'worker-A',
             'lease_expires_at', (now() + interval '5 minutes'))))
   where key = 'BULK_OPERATIONS';

  -- Legacy Start/Start Fresh style replacement that drops external_job: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-groups',
      jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 0)));
  exception when others then
    v_failed := position('would drop a protected external_job' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy full-state replacement dropped a live external_job';
  end if;

  -- Legacy write that re-points the provider batch id: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-groups',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 4,
        'external_job', jsonb_build_object('phase', 'pending', 'provider_batch_id', 'batch_OTHER')));
  exception when others then
    v_failed := position('would replace saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy write re-pointed a saved provider_batch_id';
  end if;

  -- Legacy write that regresses the revision: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-groups',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 1,
        'external_job', jsonb_build_object(
          'phase', 'pending',
          'provider_batch_id', 'batch_live',
          'submission_owner', 'worker-A',
          'lease_expires_at', (now() + interval '5 minutes'))));
  exception when others then
    v_failed := position('would regress state_revision' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy write regressed state_revision over protected state';
  end if;

  -- Legacy write that steals a live lease: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-groups',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 4,
        'external_job', jsonb_build_object(
          'phase', 'pending',
          'provider_batch_id', 'batch_live',
          'submission_owner', 'worker-B',
          'lease_expires_at', (now() + interval '5 minutes'))));
  exception when others then
    v_failed := position('submission lease is held by' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy write stole a live submission lease';
  end if;

  -- A legacy write that faithfully carries the protected job forward still works.
  v_out := public.update_bulk_operation(
    'ai-tag-groups',
    jsonb_build_object(
      'status', 'running',
      'state_revision', 4,
      'progress', jsonb_build_object('done', 7),
      'external_job', jsonb_build_object(
        'phase', 'pending',
        'provider_batch_id', 'batch_live',
        'submission_owner', 'worker-A',
        'lease_expires_at', (now() + interval '5 minutes'))));
  if v_out -> 'ai-tag-groups' -> 'progress' ->> 'done' <> '7' then
    raise exception 'a faithful legacy write was refused: %', v_out;
  end if;

  -- Unprotected keys are entirely untouched by any of this.
  v_out := public.update_bulk_operation(
    'thumbnail-scan',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 3)));
  if v_out -> 'thumbnail-scan' -> 'progress' ->> 'done' <> '3' then
    raise exception 'legacy behaviour regressed on an unprotected operation: %', v_out;
  end if;

  -- =================================================================================
  -- 5. THE BATCH WRITER CANNOT CLOBBER PROTECTED STATE
  -- =================================================================================

  -- Dropping a protected external_job through the batch writer: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'thumbnail-scan', jsonb_build_object('status', 'idle'),
      'ai-tag-groups',  jsonb_build_object('status', 'running')));
  exception when others then
    v_failed := position('would drop a protected external_job' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'update_bulk_operations_batch dropped a live external_job';
  end if;

  -- The refused batch call must be all-or-nothing: the unprotected sibling key it
  -- also carried must NOT have been written.
  select value -> 'thumbnail-scan' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored ->> 'status' <> 'running' then
    raise exception 'a refused batch call partially applied: %', v_stored;
  end if;

  -- Re-pointing the provider batch id through the batch writer: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'ai-tag-groups', jsonb_build_object(
        'status', 'running',
        'state_revision', 4,
        'external_job', jsonb_build_object('phase', 'pending', 'provider_batch_id', 'batch_OTHER'))));
  exception when others then
    v_failed := position('would replace saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'update_bulk_operations_batch re-pointed a saved provider_batch_id';
  end if;

  -- Regressing the revision through the batch writer: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'ai-tag-groups', jsonb_build_object(
        'status', 'running',
        'external_job', jsonb_build_object(
          'phase', 'pending',
          'provider_batch_id', 'batch_live',
          'submission_owner', 'worker-A',
          'lease_expires_at', (now() + interval '5 minutes')))));
  exception when others then
    v_failed := position('would regress state_revision' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'update_bulk_operations_batch regressed state_revision over protected state';
  end if;

  -- Clobbering an ambiguous submission through the batch writer: must RAISE.
  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'ai-tag-all', jsonb_build_object('status', 'idle')));
  exception when others then
    v_failed := position('would drop a protected external_job' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'update_bulk_operations_batch cleared an ambiguous submission';
  end if;

  -- Unprotected multi-key merging still behaves exactly as before.
  v_out := public.update_bulk_operations_batch(jsonb_build_object(
    'thumbnail-scan', jsonb_build_object('status', 'idle'),
    'some-other-op',  jsonb_build_object('status', 'queued')));
  if v_out -> 'thumbnail-scan' ->> 'status' <> 'idle'
     or v_out -> 'some-other-op' ->> 'status' <> 'queued' then
    raise exception 'the batch writer regressed on unprotected keys: %', v_out;
  end if;
  if v_out -> 'ai-tag-groups' -> 'external_job' ->> 'provider_batch_id' <> 'batch_live' then
    raise exception 'the batch writer disturbed a key it was not asked to write: %', v_out;
  end if;

  -- =================================================================================
  -- 6. p_only_if_status = 'running' AND STOP PROTECTION STILL HOLD
  -- =================================================================================
  update admin_config
     set value = jsonb_set(value, array['ai-tag-stopped'], jsonb_build_object(
           'status', 'stopped',
           'state_revision', 2))
   where key = 'BULK_OPERATIONS';

  -- The historical guard, now on the guarded path too.
  v_out := public.update_bulk_operation(
    'ai-tag-stopped',
    jsonb_build_object('status', 'running'),
    'running',
    2,
    'worker-A',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'status_conflict' then
    raise exception 'p_only_if_status = running protection was lost on the guarded path: %', v_out;
  end if;

  -- Even without p_only_if_status, a stopped operation is not resumed into provider work.
  v_out := public.update_bulk_operation(
    'ai-tag-stopped',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting')),
    null,
    2,
    'worker-A',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'stopped' then
    raise exception 'a stopped operation was resumed into a submission lease: %', v_out;
  end if;

  -- A legacy caller cannot un-stop it into a live external job either.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-stopped',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 2,
        'external_job', jsonb_build_object('phase', 'submitting')));
  exception when others then
    v_failed := position('would resume a live external_job' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy caller un-stopped an operation into a live external_job';
  end if;

  -- Acknowledging the stop (dismiss) is still allowed.
  v_out := public.update_bulk_operation(
    'ai-tag-stopped',
    jsonb_build_object('status', 'idle', 'state_revision', 2),
    'stopped');
  if v_out -> 'ai-tag-stopped' ->> 'status' <> 'idle' then
    raise exception 'dismissing a stopped operation was refused: %', v_out;
  end if;

  -- =================================================================================
  -- 7. ARGUMENT VALIDATION
  -- =================================================================================
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-untagged', jsonb_build_object('status', 'running'), null, null, 'worker-A', 120);
  exception when others then
    v_failed := position('p_expected_revision is required' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a lease claim was accepted without a compare-and-swap revision';
  end if;

  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-untagged', jsonb_build_object('status', 'running'), null, 3, 'worker-A', 0);
  exception when others then
    v_failed := position('p_lease_seconds must be between' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a zero-second submission lease was accepted';
  end if;

  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'ai-tag-untagged', jsonb_build_object('status', 'running'), null, 3, 'worker-A', 120);
  exception when others then
    v_failed := position('requires an external_job object' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a lease was claimed with no external_job to attach it to';
  end if;

  raise notice 'popdam_bulk_operation_revision_lease_contracts: all assertions held';
end $$;

rollback;
