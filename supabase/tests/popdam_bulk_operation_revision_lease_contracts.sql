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
--   6. a guarded write that does NOT claim the lease cannot move the lease, by any
--      field embedded in the free-form payload (review finding 1)
--   7. the ambiguity rule is enforced on the legacy and batch paths too, and there it
--      RAISES rather than returning anything a historical caller reads as success, so
--      no caller can drive a duplicate, duplicate-billed provider submission (finding 2
--      and review finding B)
--   8. a non-claiming guarded write can neither plant a provider_batch_id where none
--      is stored nor move the phase of a live-leased job (review finding A)
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
  v_job    jsonb;
  v_field  text;
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

  -- 2b. A NON-CLAIMING WRITE MAY NOT PLANT A provider_batch_id (review finding A).
  --
  -- Worker B reads revision 1, carries A's seven lease fields forward byte-for-byte
  -- (so the immutability rule is satisfied) and states no p_submission_owner -- then
  -- writes a provider_batch_id of its own invention. If that were accepted, worker A
  -- could never save the REAL id its POST returned, and the billed job would be
  -- orphaned behind B's fake one.
  select value -> 'ai-tag-untagged' -> 'external_job' into v_job
  from admin_config where key = 'BULK_OPERATIONS';

  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', v_job || jsonb_build_object('provider_batch_id', 'batch_FAKE')),
    'running',
    1);
  if (v_out ->> 'ok')::boolean is not false
     or v_out ->> 'reason' <> 'external_job_protected' then
    raise exception 'a non-claiming write planted a provider_batch_id: %', v_out;
  end if;
  select value -> 'ai-tag-untagged' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ? 'provider_batch_id'
     or (v_stored ->> 'state_revision')::bigint <> 1 then
    raise exception 'the refused batch-id plant still mutated stored state: %', v_stored;
  end if;

  -- 2c. NOR MAY IT MOVE THE PHASE OF A LIVE-LEASED JOB.
  -- Same shape, same faithful carry-forward, no claim -- it just parks A's healthy
  -- job as ambiguous (denial of service) or walks it back to a submittable phase.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', v_job || jsonb_build_object('phase', 'ambiguous_submission')),
    'running',
    1);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'phase_protected' then
    raise exception 'a non-claiming write declared a healthy job ambiguous: %', v_out;
  end if;

  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', v_job || jsonb_build_object('phase', 'prepared')),
    'running',
    1);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'phase_protected' then
    raise exception 'a non-claiming write moved the phase of a live-leased job: %', v_out;
  end if;
  select value -> 'ai-tag-untagged' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ->> 'phase' <> 'submitting'
     or (v_stored ->> 'state_revision')::bigint <> 1 then
    raise exception 'a refused phase move still mutated stored state: %', v_stored;
  end if;

  -- A non-claiming write that touches neither the phase nor the batch id is still
  -- fine: progress reporting under someone else's live lease is normal traffic.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'progress', jsonb_build_object('done', 3),
      'external_job', v_job),
    'running',
    1);
  if (v_out ->> 'ok')::boolean is not true or (v_out ->> 'state_revision')::bigint <> 2 then
    raise exception 'ordinary progress reporting under a live lease was refused: %', v_out;
  end if;

  -- Worker A saves the accepted provider batch id and can PROVE it was stored. It
  -- re-states its ownership on the same call, which is the ONLY proof that the
  -- caller is the worker that actually POSTed and got this id back. The lease is
  -- renewed by the same owner, which is allowed.
  select value -> 'ai-tag-untagged' -> 'external_job' into v_job
  from admin_config where key = 'BULK_OPERATIONS';

  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', v_job || jsonb_build_object(
        'phase', 'pending',
        'provider_batch_id', 'batch_abc')),
    'running',
    2,
    'worker-A',
    120);
  if (v_out ->> 'ok')::boolean is not true
     or v_out ->> 'provider_batch_id' <> 'batch_abc'
     or v_out ->> 'submission_owner' <> 'worker-A'
     or (v_out ->> 'state_revision')::bigint <> 3 then
    raise exception 'saving the accepted provider batch id was not provable: %', v_out;
  end if;

  -- 2d. AND CLAIMING DOES NOT HELP A BYSTANDER EITHER. On a fresh key with a live
  -- lease held by worker-A and no saved id yet, worker-B states itself as owner and
  -- brings a batch id of its own: the lease check refuses it before anything is
  -- stored, so there is no route -- claiming or not -- for a non-holder to bind this
  -- operation to a provider job.
  v_out := public.update_bulk_operation(
    'bystander-batch',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-by')),
    null,
    0,
    'worker-A',
    300);
  if (v_out ->> 'ok')::boolean is not true then
    raise exception 'could not set up the bystander fixture: %', v_out;
  end if;

  v_out := public.update_bulk_operation(
    'bystander-batch',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'pending', 'provider_batch_id', 'batch_B')),
    null,
    1,
    'worker-B',
    120);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_held' then
    raise exception 'a bystander claimed the lease to save a batch id: %', v_out;
  end if;
  select value -> 'bystander-batch' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ? 'provider_batch_id' then
    raise exception 'the refused bystander claim still stored a batch id: %', v_stored;
  end if;

  -- A saved provider batch id can never be re-pointed at a different provider job.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'pending', 'provider_batch_id', 'batch_OTHER')),
    'running',
    3);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'external_job_protected' then
    raise exception 'a saved provider_batch_id was re-pointed: %', v_out;
  end if;

  -- A non-claiming guarded write may not drop an external_job whose lease is still
  -- live: dropping it and re-creating it on the next revision is lease theft in two
  -- steps. Only once the lease has lapsed may the proving caller clear a finished
  -- job (the saved provider_batch_id means this is NOT the ambiguous crash window).
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 100)),
    'running',
    3);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_held' then
    raise exception 'a non-claiming guarded write dropped a live-leased external_job: %', v_out;
  end if;

  update admin_config
     set value = jsonb_set(value, array['ai-tag-untagged','external_job','lease_expires_at'],
                           to_jsonb((now() - interval '1 second')::text))
   where key = 'BULK_OPERATIONS';

  -- The owner that proved it read revision 3 may deliberately clear a finished job.
  v_out := public.update_bulk_operation(
    'ai-tag-untagged',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 100)),
    'running',
    3);
  if (v_out ->> 'ok')::boolean is not true
     or v_out ->> 'external_job_phase' is not null
     or (v_out ->> 'state_revision')::bigint <> 4 then
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

  -- =================================================================================
  -- 8. A GUARDED WRITE THAT DOES NOT CLAIM THE LEASE CANNOT MOVE THE LEASE
  --    (review finding 1: two workers could otherwise both believe they own one
  --     submission, using only this API.)
  -- =================================================================================
  v_out := public.update_bulk_operation(
    'lease-attack',
    jsonb_build_object(
      'status', 'running',
      'external_job', jsonb_build_object('phase', 'submitting', 'run_id', 'run-att')),
    null,
    0,
    'worker-A',
    300);
  if (v_out ->> 'ok')::boolean is not true or v_out ->> 'submission_owner' <> 'worker-A' then
    raise exception 'could not set up the live-lease fixture: %', v_out;
  end if;

  select value -> 'lease-attack' -> 'external_job' into v_job
  from admin_config where key = 'BULK_OPERATIONS';

  -- 8a. THE ATTACK. p_submission_owner is null, so no lease is claimed and every
  -- lease check that keys off it is skipped -- but the payload names worker-B as
  -- the submission owner. If this is applied, worker-B reads back a state naming
  -- worker-B as owner while worker-A's live lease says worker-A. Must be refused.
  v_out := public.update_bulk_operation(
    'lease-attack',
    jsonb_build_object(
      'status', 'running',
      'external_job', v_job || jsonb_build_object('submission_owner', 'worker-B')),
    null,
    1);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_fields_immutable' then
    raise exception 'a no-owner guarded write took over a live submission lease: %', v_out;
  end if;
  select value -> 'lease-attack' -> 'external_job' into v_stored
  from admin_config where key = 'BULK_OPERATIONS';
  if v_stored ->> 'submission_owner' <> 'worker-A' then
    raise exception 'the refused write still moved the stored submission owner: %', v_stored;
  end if;

  -- 8b. FAITHFUL CARRY-FORWARD MUST STILL SUCCEED. Same call shape, lease fields
  -- carried forward exactly as stored, ordinary fields changed. The PHASE is not an
  -- ordinary field while the lease is live -- only the holder moves it (2c) -- so an
  -- ordinary external_job field is changed here instead.
  v_out := public.update_bulk_operation(
    'lease-attack',
    jsonb_build_object(
      'status', 'running',
      'progress', jsonb_build_object('done', 42),
      'external_job', v_job || jsonb_build_object('attempt', 2)),
    null,
    1);
  if (v_out ->> 'ok')::boolean is not true
     or v_out ->> 'submission_owner' <> 'worker-A'
     or (v_out ->> 'state_revision')::bigint <> 2 then
    raise exception 'a faithful no-owner carry-forward was refused: %', v_out;
  end if;

  select value -> 'lease-attack' -> 'external_job' into v_job
  from admin_config where key = 'BULK_OPERATIONS';

  -- 8c. THE SAME ATTACK THROUGH EVERY OTHER LEASE-CONTROLLING FIELD. Overriding any
  -- one of them without claiming the lease -- extending the expiry, restamping the
  -- claim time, or forging an ambiguity verdict -- must be refused just as hard.
  foreach v_field in array array['lease_expires_at','lease_claimed_at','ambiguous_since',
                                 'ambiguous_reason','ambiguous_prior_phase','ambiguous_prior_owner'] loop
    v_out := public.update_bulk_operation(
      'lease-attack',
      jsonb_build_object(
        'status', 'running',
        'external_job', v_job || jsonb_build_object(v_field, 'forged-by-worker-B')),
      null,
      2);
    if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_fields_immutable' then
      raise exception 'a no-owner guarded write forged external_job.%: %', v_field, v_out;
    end if;
  end loop;

  -- Dropping external_job entirely while the lease is live is the same theft in two
  -- steps (clear now, re-create as yourself on the next revision). Also refused.
  v_out := public.update_bulk_operation(
    'lease-attack',
    jsonb_build_object('status', 'running'),
    null,
    2);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_held' then
    raise exception 'a no-owner guarded write dropped a live-leased external_job: %', v_out;
  end if;

  -- 8d. A payload may not restate a state_revision other than the stored one.
  v_out := public.update_bulk_operation(
    'lease-attack',
    jsonb_build_object(
      'status', 'running',
      'state_revision', 99,
      'external_job', v_job),
    null,
    2);
  if (v_out ->> 'ok')::boolean is not false or v_out ->> 'reason' <> 'lease_fields_immutable' then
    raise exception 'a no-owner guarded write restated state_revision: %', v_out;
  end if;

  -- =================================================================================
  -- 9. THE AMBIGUITY RULE ON THE LEGACY AND BATCH PATHS
  --    (review finding 2: the money-losing rule was enforced on the guarded path
  --     only, so a legacy caller could still drive a duplicate provider submission.)
  -- =================================================================================

  -- 9a. LEGACY THREE-ARGUMENT PATH over an expired lease with NO saved batch id.
  --     It must RAISE. A three-argument caller cannot be handed a proof envelope,
  --     it reads "no exception" as success, and the money path is write-then-POST,
  --     so any quiet return -- flip or not -- is a silent failure that arrives after
  --     the provider has been billed. Nothing is flipped and nothing is written: the
  --     stored row stays in the refusing state, so the refusal repeats forever.
  update admin_config
     set value = jsonb_set(value, array['legacy-ambiguous'], jsonb_build_object(
           'status', 'running',
           'state_revision', 3,
           'external_job', jsonb_build_object(
             'phase', 'submitting',
             'run_id', 'run-legacy',
             'submission_owner', 'worker-A',
             'lease_expires_at', (now() - interval '30 seconds'))))
   where key = 'BULK_OPERATIONS';

  -- This is the write that would otherwise walk the operation back to a submittable
  -- state and drive a second, duplicate-billed POST to the provider.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'legacy-ambiguous',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 3,
        'external_job', jsonb_build_object('phase', 'prepared', 'run_id', 'run-legacy-2')));
  exception when others then
    v_failed := position('expired at' in sqlerrm) > 0
                and position('no saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'the legacy path did not RAISE on the expired-lease-no-batch-id rule';
  end if;

  -- Nothing was applied and nothing was flipped.
  select value -> 'legacy-ambiguous' into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored -> 'external_job' ->> 'phase' <> 'submitting'
     or v_stored -> 'external_job' ->> 'run_id' <> 'run-legacy'
     or (v_stored ->> 'state_revision')::bigint <> 3 then
    raise exception 'the legacy refusal still mutated stored state: %', v_stored;
  end if;

  -- And it is not a one-off: the SAME call raises again, because the stored row
  -- still matches the rule. Safety does not depend on a durable flip.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'legacy-ambiguous',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 3,
        'external_job', jsonb_build_object('phase', 'prepared', 'run_id', 'run-legacy-2')));
  exception when others then
    v_failed := position('no saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'the legacy refusal was not repeatable';
  end if;

  -- A legacy caller that has actually reconciled with the provider may still record
  -- the verdict explicitly, which is the documented escape.
  v_out := public.update_bulk_operation(
    'legacy-ambiguous',
    jsonb_build_object(
      'status', 'running',
      'state_revision', 3,
      'external_job', jsonb_build_object(
        'phase', 'ambiguous_submission',
        'run_id', 'run-legacy',
        'submission_owner', 'worker-A',
        'lease_expires_at', (now() - interval '30 seconds'))));
  if v_out -> 'legacy-ambiguous' -> 'external_job' ->> 'phase' <> 'ambiguous_submission' then
    raise exception 'explicit legacy reconciliation was refused: %', v_out;
  end if;

  -- Once ambiguous, a legacy write still cannot resume it.
  v_failed := false;
  begin
    perform public.update_bulk_operation(
      'legacy-ambiguous',
      jsonb_build_object(
        'status', 'running',
        'state_revision', 4,
        'external_job', jsonb_build_object('phase', 'prepared')));
  exception when others then
    v_failed := position('requires explicit reconciliation' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'a legacy write resumed an ambiguous submission';
  end if;

  -- 9b. BATCH PATH over an expired lease with NO saved batch id: same verdict.
  update admin_config
     set value = jsonb_set(value, array['batch-ambiguous'], jsonb_build_object(
           'status', 'running',
           'state_revision', 7,
           'external_job', jsonb_build_object(
             'phase', 'submitting',
             'run_id', 'run-batch',
             'submission_owner', 'worker-A',
             'lease_expires_at', (now() - interval '30 seconds'))))
   where key = 'BULK_OPERATIONS';

  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'batch-sibling',   jsonb_build_object('status', 'queued'),
      'batch-ambiguous', jsonb_build_object(
        'status', 'running',
        'state_revision', 7,
        'external_job', jsonb_build_object('phase', 'prepared', 'run_id', 'run-batch-2'))));
  exception when others then
    v_failed := position('no saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'the batch path did not RAISE on the expired-lease-no-batch-id rule';
  end if;

  -- All-or-nothing, and no flip: neither key was written.
  select value into v_stored from admin_config where key = 'BULK_OPERATIONS';
  if v_stored ? 'batch-sibling' then
    raise exception 'the batch path partially applied around the ambiguity rule: %', v_stored;
  end if;
  if v_stored -> 'batch-ambiguous' -> 'external_job' ->> 'phase' <> 'submitting'
     or v_stored -> 'batch-ambiguous' -> 'external_job' ->> 'run_id' <> 'run-batch'
     or (v_stored -> 'batch-ambiguous' ->> 'state_revision')::bigint <> 7 then
    raise exception 'the batch refusal still mutated stored state: %', v_stored;
  end if;

  -- Repeatable for the same reason: the stored row still matches the rule.
  v_failed := false;
  begin
    perform public.update_bulk_operations_batch(jsonb_build_object(
      'batch-ambiguous', jsonb_build_object(
        'status', 'running',
        'state_revision', 7,
        'external_job', jsonb_build_object('phase', 'prepared'))));
  exception when others then
    v_failed := position('no saved provider_batch_id' in sqlerrm) > 0;
  end;
  if not v_failed then
    raise exception 'the batch refusal was not repeatable';
  end if;

  -- 9c. None of this touches ordinary callers: a legitimate legacy write on an
  -- unprotected key still succeeds, single and batch.
  v_out := public.update_bulk_operation(
    'plain-op',
    jsonb_build_object('status', 'running', 'progress', jsonb_build_object('done', 11)));
  if v_out -> 'plain-op' -> 'progress' ->> 'done' <> '11' then
    raise exception 'a legitimate legacy write on an unprotected key was refused: %', v_out;
  end if;

  v_out := public.update_bulk_operations_batch(jsonb_build_object(
    'plain-op', jsonb_build_object('status', 'idle')));
  if v_out -> 'plain-op' ->> 'status' <> 'idle' then
    raise exception 'a legitimate legacy batch write on an unprotected key was refused: %', v_out;
  end if;

  raise notice 'popdam_bulk_operation_revision_lease_contracts: all assertions held';
end $$;

rollback;
