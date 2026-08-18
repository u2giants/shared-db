-- Issue #1171 / claim #1174. Shared-database prerequisite for u2giants/popdam3#92
-- (plan_openrouter_batch_restart_recovery.md, Step 1).
--
-- WHAT THIS GUARDS
-- ----------------
-- PopDAM bulk-operation state is NOT a table. It is one JSONB value in
-- public.admin_config under key 'BULK_OPERATIONS'; each operation is one object
-- under its own op key. Two writers exist today and both replace whole operation
-- objects: public.update_bulk_operation (single key) and
-- public.update_bulk_operations_batch (many keys). Both serialize on
-- pg_advisory_xact_lock(hashtext('BULK_OPERATIONS')), which orders writers but
-- does NOT stop a stale writer from overwriting a newer state.
--
-- Once the PopDAM worker persists an accepted OpenRouter Batch API job inside an
-- operation, an overwrite is no longer a lost UI field: it abandons (or worse,
-- re-submits and re-bills) provider work. Overlapping Railway processes during a
-- deploy make that a normal event, and run_id is not a lock because nothing ever
-- compared it.
--
-- WHAT THIS MIGRATION ADDS
-- ------------------------
-- 1. A guarded compare-and-swap path on public.update_bulk_operation:
--      * caller states the revision it read (p_expected_revision);
--      * the stored revision must match exactly or the write is refused;
--      * a successful guarded write stamps state_revision = stored + 1;
--      * p_submission_owner + p_lease_seconds atomically claim a time-bounded
--        submission lease inside external_job in the SAME statement, under the
--        SAME advisory lock, so exactly one worker can ever hold a given revision;
--      * the guarded call returns an envelope carrying the SAVED revision, owner,
--        lease and provider_batch_id, so the worker can PROVE what was stored
--        instead of treating a missing response as success.
-- 2. Protected external-job state. An operation whose external_job.phase is live
--    ('prepared','submitting','pending','applying') or 'ambiguous_submission' may
--    not be silently dropped, re-pointed at a different provider batch, or
--    un-stopped by any caller, guarded or legacy.
-- 3. Ambiguity instead of automatic resubmission. A submission lease that expires
--    with NO provider_batch_id saved is the exact crash window where OpenRouter may
--    already hold (and bill) the job. Claiming that lease does not hand out a new
--    submission slot: it durably flips the phase to 'ambiguous_submission' and
--    refuses. Recovery is a human/explicit flow, never an automatic second POST.
-- 4. Backward compatibility only where it is safe. A three-argument legacy call
--    still behaves exactly as before -- same conditional-status no-op, same full
--    'BULK_OPERATIONS' object returned -- for every operation with no protected
--    external-job state. When protected state exists and the legacy write would
--    clobber it, the call RAISES. It never silently discards the write.
--
-- WHY update_bulk_operations_batch IS IN SCOPE
-- -------------------------------------------
-- It writes the same key and never looked at what it was overwriting, so it is the
-- one legacy caller that could clobber a protected job. It now applies the same
-- protection rules per key and raises loudly rather than merging over them.
--
-- Objects written by this migration (claim #1174):
--   function public.update_bulk_operation
--   function public.update_bulk_operations_batch
-- public.admin_config is read and upserted exactly as before; its shape is unchanged.

begin;

-- The legacy three-argument function must be dropped, not overloaded: adding
-- defaulted parameters via CREATE OR REPLACE would leave two candidates and make
-- every existing three-argument call ambiguous. Dropping and recreating keeps ONE
-- function whose defaults preserve the legacy call shape.
drop function if exists public.update_bulk_operation(text, jsonb, text);
drop function if exists public.update_bulk_operation(text, jsonb, text, bigint, text, integer);

create function public.update_bulk_operation(
  p_op_key text,
  p_op_state jsonb,
  p_only_if_status text default null,
  p_expected_revision bigint default null,
  p_submission_owner text default null,
  p_lease_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  -- Live phases are phases in which PopDAM believes a provider job exists or is
  -- about to exist. 'ambiguous_submission' is protected too, more strongly.
  c_live_phases constant text[] := array['prepared','submitting','pending','applying'];
  c_stop_status constant text[] := array['stop','stopping','stopped','stop_requested'];
  c_default_lease constant integer := 120;

  v_current        jsonb;
  v_stored         jsonb;
  v_stored_status  text;
  v_stored_rev     bigint;
  v_stored_job     jsonb;
  v_stored_phase   text;
  v_stored_batch   text;
  v_stored_owner   text;
  v_stored_lease   timestamptz;
  v_stored_live    boolean;
  v_stored_ambig   boolean;
  v_protected      boolean;

  v_in_job         jsonb;
  v_in_status      text;
  v_in_batch       text;
  v_in_phase       text;
  v_in_owner       text;
  v_in_rev         bigint;

  v_now            timestamptz := now();
  v_lease_until    timestamptz;
  v_new            jsonb;
  v_out_op         jsonb;
  v_ok             boolean := true;
  v_reason         text := 'ok';
begin
  if p_op_key is null or btrim(p_op_key) = '' then
    raise exception 'update_bulk_operation: p_op_key is required'
      using errcode = '22023';
  end if;

  -- Serialize all writers on the BULK_OPERATIONS config key (unchanged).
  perform pg_advisory_xact_lock(hashtext('BULK_OPERATIONS'));

  select value into v_current
  from admin_config
  where key = 'BULK_OPERATIONS';

  v_current := coalesce(v_current, '{}'::jsonb);

  v_stored := case when jsonb_typeof(v_current -> p_op_key) = 'object'
                   then v_current -> p_op_key end;
  v_stored_status := v_stored ->> 'status';
  v_stored_rev    := coalesce(nullif(v_stored ->> 'state_revision', '')::bigint, 0);
  v_stored_job    := case when jsonb_typeof(v_stored -> 'external_job') = 'object'
                          then v_stored -> 'external_job' end;
  v_stored_phase  := v_stored_job ->> 'phase';
  v_stored_batch  := nullif(v_stored_job ->> 'provider_batch_id', '');
  v_stored_owner  := nullif(v_stored_job ->> 'submission_owner', '');
  v_stored_lease  := nullif(v_stored_job ->> 'lease_expires_at', '')::timestamptz;
  v_stored_live   := coalesce(v_stored_phase = any(c_live_phases), false);
  v_stored_ambig  := coalesce(v_stored_phase = 'ambiguous_submission', false);
  v_protected     := v_stored_live or v_stored_ambig;

  v_in_job    := case when jsonb_typeof(p_op_state -> 'external_job') = 'object'
                      then p_op_state -> 'external_job' end;
  v_in_status := p_op_state ->> 'status';
  v_in_batch  := nullif(v_in_job ->> 'provider_batch_id', '');
  v_in_phase  := v_in_job ->> 'phase';
  v_in_owner  := nullif(v_in_job ->> 'submission_owner', '');
  v_in_rev    := nullif(p_op_state ->> 'state_revision', '')::bigint;

  -- ==========================================================================
  -- LEGACY PATH -- byte-for-byte the historical behaviour, except that it can no
  -- longer clobber protected external-job state.
  -- ==========================================================================
  if p_expected_revision is null and p_submission_owner is null then

    if p_only_if_status is not null
       and v_stored_status is distinct from p_only_if_status then
      -- Unchanged contract: return current state so the caller detects the no-op.
      return v_current;
    end if;

    if v_protected then
      -- A legacy caller has no revision to compare, so it is allowed through only
      -- when its payload demonstrably carries the same protected job forward.
      if v_in_job is null then
        raise exception
          'update_bulk_operation: legacy write to "%" refused -- it would drop a protected external_job (phase=%, provider_batch_id=%). Use the guarded path with p_expected_revision.',
          p_op_key, coalesce(v_stored_phase, '<none>'), coalesce(v_stored_batch, '<none>')
          using errcode = '55000';
      end if;

      if v_stored_ambig and coalesce(v_in_phase, '') <> 'ambiguous_submission' then
        raise exception
          'update_bulk_operation: legacy write to "%" refused -- external_job is ambiguous_submission and requires explicit reconciliation.',
          p_op_key
          using errcode = '55000';
      end if;

      if v_stored_batch is not null and v_in_batch is distinct from v_stored_batch then
        raise exception
          'update_bulk_operation: legacy write to "%" refused -- it would replace saved provider_batch_id % with %.',
          p_op_key, v_stored_batch, coalesce(v_in_batch, '<null>')
          using errcode = '55000';
      end if;

      if coalesce(v_stored_lease > v_now, false)
         and v_in_owner is distinct from v_stored_owner then
        raise exception
          'update_bulk_operation: legacy write to "%" refused -- submission lease is held by % until %.',
          p_op_key, v_stored_owner, v_stored_lease
          using errcode = '55000';
      end if;

      if coalesce(v_stored_rev > 0, false)
         and (v_in_rev is null or v_in_rev < v_stored_rev) then
        raise exception
          'update_bulk_operation: legacy write to "%" refused -- it would regress state_revision % to %.',
          p_op_key, v_stored_rev, coalesce(v_in_rev::text, '<null>')
          using errcode = '55000';
      end if;
    end if;

    -- Stop is never un-stopped by a writer that is driving provider work.
    if coalesce(v_stored_status = any(c_stop_status), false)
       and coalesce(v_in_status, '') <> all(c_stop_status)
       and coalesce(v_in_phase = any(c_live_phases), false) then
      raise exception
        'update_bulk_operation: legacy write to "%" refused -- operation status is "%" (stopped) and the write would resume a live external_job.',
        p_op_key, v_stored_status
        using errcode = '55000';
    end if;

    v_current := jsonb_set(v_current, array[p_op_key], p_op_state);

    insert into admin_config (key, value, updated_at)
    values ('BULK_OPERATIONS', v_current, now())
    on conflict (key) do update
      set value = excluded.value,
          updated_at = excluded.updated_at;

    return v_current;
  end if;

  -- ==========================================================================
  -- GUARDED COMPARE-AND-SWAP PATH
  -- ==========================================================================
  if p_expected_revision is null then
    raise exception
      'update_bulk_operation: p_expected_revision is required when p_submission_owner is supplied'
      using errcode = '22023';
  end if;

  if coalesce(jsonb_typeof(p_op_state), 'null') <> 'object' then
    raise exception 'update_bulk_operation: the guarded path requires a JSON object in p_op_state'
      using errcode = '22023';
  end if;

  if p_expected_revision < 0 then
    raise exception 'update_bulk_operation: p_expected_revision must be non-negative'
      using errcode = '22023';
  end if;

  if p_submission_owner is not null and btrim(p_submission_owner) = '' then
    raise exception 'update_bulk_operation: p_submission_owner must not be blank'
      using errcode = '22023';
  end if;

  if p_lease_seconds is not null and (p_lease_seconds <= 0 or p_lease_seconds > 3600) then
    raise exception 'update_bulk_operation: p_lease_seconds must be between 1 and 3600'
      using errcode = '22023';
  end if;

  if p_lease_seconds is not null and p_submission_owner is null then
    raise exception 'update_bulk_operation: p_lease_seconds requires p_submission_owner'
      using errcode = '22023';
  end if;

  v_out_op := v_stored;

  <<guarded>>
  begin
    -- The historical p_only_if_status protection still applies first.
    if p_only_if_status is not null
       and v_stored_status is distinct from p_only_if_status then
      v_ok := false; v_reason := 'status_conflict';
      exit guarded;
    end if;

    if v_stored_rev is distinct from p_expected_revision then
      v_ok := false; v_reason := 'revision_conflict';
      exit guarded;
    end if;

    -- An ambiguous submission outranks a matching revision: it may only be
    -- carried forward as ambiguous, never cleared or resumed here.
    if v_stored_ambig and coalesce(v_in_phase, '') <> 'ambiguous_submission' then
      v_ok := false; v_reason := 'ambiguous_submission';
      exit guarded;
    end if;

    -- A saved provider batch id may be carried forward or deliberately cleared by
    -- a caller that proved it saw this revision, but never re-pointed.
    if v_stored_batch is not null
       and v_in_job is not null
       and v_in_batch is distinct from v_stored_batch then
      v_ok := false; v_reason := 'external_job_protected';
      exit guarded;
    end if;

    if coalesce(v_stored_status = any(c_stop_status), false)
       and coalesce(v_in_status, '') <> all(c_stop_status)
       and (p_submission_owner is not null
            or coalesce(v_in_phase = any(c_live_phases), false)) then
      v_ok := false; v_reason := 'stopped';
      exit guarded;
    end if;

    if p_submission_owner is not null then
      -- A live lease belongs to exactly one owner.
      if v_stored_owner is not null
         and coalesce(v_stored_lease > v_now, false)
         and v_stored_owner <> p_submission_owner then
        v_ok := false; v_reason := 'lease_held';
        exit guarded;
      end if;

      -- THE AMBIGUITY RULE. An expired lease with no saved provider_batch_id means
      -- a submission may already have been accepted and billed. Do not hand out a
      -- new submission slot; make the ambiguity durable and refuse.
      if v_stored_job is not null
         and v_stored_batch is null
         and v_stored_owner is not null
         and v_stored_lease is not null
         and v_stored_lease <= v_now then

        v_new := coalesce(v_stored, '{}'::jsonb)
                 || jsonb_build_object(
                      'state_revision', v_stored_rev + 1,
                      'external_job', v_stored_job || jsonb_build_object(
                        'phase', 'ambiguous_submission',
                        'ambiguous_since', v_now,
                        'ambiguous_reason', 'submission_lease_expired_without_provider_batch_id',
                        'ambiguous_prior_phase', coalesce(v_stored_phase, 'unknown'),
                        'ambiguous_prior_owner', v_stored_owner));

        v_current := jsonb_set(v_current, array[p_op_key], v_new);

        insert into admin_config (key, value, updated_at)
        values ('BULK_OPERATIONS', v_current, now())
        on conflict (key) do update
          set value = excluded.value,
              updated_at = excluded.updated_at;

        v_out_op := v_new;
        v_ok := false; v_reason := 'ambiguous_submission';
        exit guarded;
      end if;

      if coalesce(jsonb_typeof(p_op_state -> 'external_job'), 'null') <> 'object' then
        raise exception
          'update_bulk_operation: a submission lease claim on "%" requires an external_job object in p_op_state'
          , p_op_key
          using errcode = '22023';
      end if;

      v_lease_until := v_now + make_interval(secs => coalesce(p_lease_seconds, c_default_lease));
    end if;

    -- Accept the write and stamp the next revision.
    v_new := p_op_state || jsonb_build_object('state_revision', v_stored_rev + 1);

    if p_submission_owner is not null then
      v_new := jsonb_set(
                 v_new,
                 array['external_job'],
                 (v_new -> 'external_job') || jsonb_build_object(
                   'submission_owner', p_submission_owner,
                   'lease_expires_at', v_lease_until,
                   'lease_claimed_at', v_now));
    end if;

    v_current := jsonb_set(v_current, array[p_op_key], v_new);

    insert into admin_config (key, value, updated_at)
    values ('BULK_OPERATIONS', v_current, now())
    on conflict (key) do update
      set value = excluded.value,
          updated_at = excluded.updated_at;

    v_out_op := v_new;
    v_ok := true; v_reason := 'ok';
  end guarded;

  -- Proof envelope. Everything reported here is read back out of what is now
  -- stored, never echoed from the caller's arguments.
  return jsonb_build_object(
    'ok', v_ok,
    'reason', v_reason,
    'op_key', p_op_key,
    'expected_revision', p_expected_revision,
    'state_revision', coalesce(nullif(v_out_op ->> 'state_revision', '')::bigint, 0),
    'status', v_out_op ->> 'status',
    'external_job_phase', v_out_op -> 'external_job' ->> 'phase',
    'submission_owner', v_out_op -> 'external_job' ->> 'submission_owner',
    'lease_expires_at', v_out_op -> 'external_job' ->> 'lease_expires_at',
    'provider_batch_id', v_out_op -> 'external_job' ->> 'provider_batch_id',
    'operation', v_out_op,
    'operations', v_current);
end;
$function$;

comment on function public.update_bulk_operation(text, jsonb, text, bigint, text, integer) is
  'Atomic writer for one operation inside the admin_config BULK_OPERATIONS JSONB value. '
  'Three-argument calls keep the historical behaviour and return the whole BULK_OPERATIONS object. '
  'Supplying p_expected_revision selects the guarded compare-and-swap path, which returns a proof '
  'envelope {ok, reason, state_revision, submission_owner, lease_expires_at, provider_batch_id, operation, operations}. '
  'p_submission_owner + p_lease_seconds atomically claim a submission lease. An expired lease with no saved '
  'provider_batch_id becomes external_job.phase = ambiguous_submission and is never an automatic resubmission. '
  'See u2giants/shared-db#1171 and u2giants/popdam3#92.';

revoke execute on function public.update_bulk_operation(text, jsonb, text, bigint, text, integer)
  from public, anon;
grant execute on function public.update_bulk_operation(text, jsonb, text, bigint, text, integer)
  to authenticated, service_role, postgres;

-- ==========================================================================
-- The legacy multi-key writer. Same signature, same return value, same merge --
-- but it can no longer merge over protected external-job state.
-- ==========================================================================
create or replace function public.update_bulk_operations_batch(p_updates jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  c_live_phases constant text[] := array['prepared','submitting','pending','applying'];
  c_stop_status constant text[] := array['stop','stopping','stopped','stop_requested'];

  v_current       jsonb;
  v_key           text;
  v_stored        jsonb;
  v_stored_status text;
  v_stored_rev    bigint;
  v_stored_job    jsonb;
  v_stored_phase  text;
  v_stored_batch  text;
  v_stored_owner  text;
  v_stored_lease  timestamptz;
  v_protected     boolean;
  v_in            jsonb;
  v_in_job        jsonb;
  v_in_status     text;
  v_in_batch      text;
  v_in_phase      text;
  v_in_owner      text;
  v_in_rev        bigint;
  v_now           timestamptz := now();
begin
  perform pg_advisory_xact_lock(hashtext('BULK_OPERATIONS'));

  select value into v_current
  from admin_config
  where key = 'BULK_OPERATIONS';

  v_current := coalesce(v_current, '{}'::jsonb);

  -- Merge each key from p_updates into the current state.
  for v_key in select jsonb_object_keys(p_updates) loop
    v_in := p_updates -> v_key;

    v_stored := case when jsonb_typeof(v_current -> v_key) = 'object'
                     then v_current -> v_key end;
    v_stored_status := v_stored ->> 'status';
    v_stored_rev    := coalesce(nullif(v_stored ->> 'state_revision', '')::bigint, 0);
    v_stored_job    := case when jsonb_typeof(v_stored -> 'external_job') = 'object'
                            then v_stored -> 'external_job' end;
    v_stored_phase  := v_stored_job ->> 'phase';
    v_stored_batch  := nullif(v_stored_job ->> 'provider_batch_id', '');
    v_stored_owner  := nullif(v_stored_job ->> 'submission_owner', '');
    v_stored_lease  := nullif(v_stored_job ->> 'lease_expires_at', '')::timestamptz;
    v_protected     := coalesce(v_stored_phase = any(c_live_phases), false)
                       or coalesce(v_stored_phase = 'ambiguous_submission', false);

    v_in_job    := case when jsonb_typeof(v_in -> 'external_job') = 'object'
                        then v_in -> 'external_job' end;
    v_in_status := v_in ->> 'status';
    v_in_batch  := nullif(v_in_job ->> 'provider_batch_id', '');
    v_in_phase  := v_in_job ->> 'phase';
    v_in_owner  := nullif(v_in_job ->> 'submission_owner', '');
    v_in_rev    := nullif(v_in ->> 'state_revision', '')::bigint;

    if v_protected then
      -- This function has no compare-and-swap argument, so it is a legacy writer
      -- by construction. It may only carry protected state forward untouched.
      if v_in_job is null then
        raise exception
          'update_bulk_operations_batch: refused -- key "%" would drop a protected external_job (phase=%, provider_batch_id=%). Use update_bulk_operation with p_expected_revision.',
          v_key, coalesce(v_stored_phase, '<none>'), coalesce(v_stored_batch, '<none>')
          using errcode = '55000';
      end if;

      if coalesce(v_stored_phase = 'ambiguous_submission', false)
         and coalesce(v_in_phase, '') <> 'ambiguous_submission' then
        raise exception
          'update_bulk_operations_batch: refused -- key "%" external_job is ambiguous_submission and requires explicit reconciliation.',
          v_key
          using errcode = '55000';
      end if;

      if v_stored_batch is not null and v_in_batch is distinct from v_stored_batch then
        raise exception
          'update_bulk_operations_batch: refused -- key "%" would replace saved provider_batch_id % with %.',
          v_key, v_stored_batch, coalesce(v_in_batch, '<null>')
          using errcode = '55000';
      end if;

      if coalesce(v_stored_lease > v_now, false)
         and v_in_owner is distinct from v_stored_owner then
        raise exception
          'update_bulk_operations_batch: refused -- key "%" submission lease is held by % until %.',
          v_key, v_stored_owner, v_stored_lease
          using errcode = '55000';
      end if;

      if coalesce(v_stored_rev > 0, false)
         and (v_in_rev is null or v_in_rev < v_stored_rev) then
        raise exception
          'update_bulk_operations_batch: refused -- key "%" would regress state_revision % to %.',
          v_key, v_stored_rev, coalesce(v_in_rev::text, '<null>')
          using errcode = '55000';
      end if;
    end if;

    if coalesce(v_stored_status = any(c_stop_status), false)
       and coalesce(v_in_status, '') <> all(c_stop_status)
       and coalesce(v_in_phase = any(c_live_phases), false) then
      raise exception
        'update_bulk_operations_batch: refused -- key "%" status is "%" (stopped) and the write would resume a live external_job.',
        v_key, v_stored_status
        using errcode = '55000';
    end if;

    v_current := jsonb_set(v_current, array[v_key], v_in);
  end loop;

  insert into admin_config (key, value, updated_at)
  values ('BULK_OPERATIONS', v_current, now())
  on conflict (key) do update
    set value = excluded.value,
        updated_at = excluded.updated_at;

  return v_current;
end;
$function$;

comment on function public.update_bulk_operations_batch(jsonb) is
  'Legacy multi-key writer for the admin_config BULK_OPERATIONS JSONB value. Behaviour and return value '
  'are unchanged for every operation with no protected external_job. It raises rather than merging over a '
  'live or ambiguous external_job, a saved provider_batch_id, a held submission lease, a regressing '
  'state_revision, or a stopped operation. See u2giants/shared-db#1171.';

revoke execute on function public.update_bulk_operations_batch(jsonb) from public, anon;
grant execute on function public.update_bulk_operations_batch(jsonb)
  to authenticated, service_role, postgres;

commit;
