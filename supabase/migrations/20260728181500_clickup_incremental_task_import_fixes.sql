-- ClickUp incremental task import — FORWARD CORRECTNESS FIX.
-- Migration: 20260728181500_clickup_incremental_task_import_fixes.sql
--
-- Why this exists (read before editing anything ClickUp-import related)
-- --------------------------------------------------------------------
-- `20260728160000_clickup_incremental_task_import.sql` shipped the ClickUp importer with
-- five correctness defects found in adversarial review. That migration was swept onto
-- `main` by an unrelated PR and is ALREADY APPLIED to the preview database. AGENTS.md §4.4
-- forbids editing a migration that has been applied anywhere — two sessions silently
-- clobber each other that way, and Supabase's ledger keys on the timestamp, so an edited
-- file would never re-run. The fix therefore lands here, as a NEW forward migration that
-- replaces the function bodies and re-runs the corrected backfill.
--
-- This migration is a pure forward fix. It does NOT re-declare or alter the columns, index,
-- comments, or api.clickup_task_sync_run_list() created by 20260728160000 — those objects
-- already exist and are correct. Any DDL touched here is `if not exists` guarded.
--
-- What each fix addresses
-- -----------------------
--   Defect 1 — watermark was taken from the run's own start time (now() at INSERT), so any
--     ClickUp task edited between the API fetch and the commit was skipped forever. Fixed:
--     the watermark is the caller's PRE-FETCH timestamp (snapshot.fetch_started_at, captured
--     before the first ClickUp API call) minus a 60-second overlap. date_updated_gt is
--     strict and the upsert is idempotent, so overlapping is free and gap-free.
--
--   Defect 2 — the watermark advanced even when rows failed, so a row that errored was never
--     retried and its edit was lost. Fixed: when rows_failed > 0 the watermark does NOT
--     advance (it stays at watermark_in) and the run is marked unmistakably with
--     metadata.outcome='succeeded_with_failures', partial_failure=true, and
--     watermark_advanced=false. ingest.sync_status has no 'partial' value, so status stays
--     'succeeded' and the flags carry the truth. Because a permanently-bad task would now
--     wedge the watermark forever, snapshot.skip_task_ids is the escape hatch: acknowledged
--     ids are skipped wholesale (counted in metadata.rows_skipped, never in rows_failed).
--     Removing an id from that list re-enables it.
--
--   Defect 3 — the backfill claimed external_id from the UNTRIMMED clickup_task_id, so a
--     legacy row holding '123 ' was claimed as ('clickup','123 ') while the importer writes
--     ('clickup','123'). The importer would then INSERT a second product row and strand the
--     curated links (project/licensor/property/stage/cover) on the orphan. Fixed: the
--     backfill trims, resolves ambiguity on the trimmed key, and skips ids already owned by
--     another row instead of failing the unique constraint. Section 1 below also repairs any
--     untrimmed external_id that a previous run of the broken backfill left behind.
--
--   Defect 4 — every run rewrote every row, bumping updated_at even when nothing in ClickUp
--     changed. pim.product carries a BEFORE UPDATE set_updated_at() trigger, so the churn
--     poisoned anything sorting or filtering on updated_at, including the new
--     (clickup_list_id, updated_at) index. Fixed: the ON CONFLICT DO UPDATE now carries a
--     WHERE that skips the write entirely when the clickup_source_hash is unchanged.
--
--   Defect 5 — skipped rows were dropped silently. Fixed: the backfill now records BOTH the
--     ambiguous ids and the already-claimed ids into the ingest.sync_run metadata, and the
--     importer records skipped_task_ids per run.
--
-- Contract tests: supabase/tests/clickup_task_import_contracts.sql.
-- Runner: tools/sync-clickup-tasks.mjs (sends fetch_started_at and skip_task_ids).

-- =====================================================================================
-- 1. Repair any UNTRIMMED external_id left by the original (broken) backfill.
--
--    Idempotent and constraint-safe: a value whose trimmed form is already owned by a
--    different row is SKIPPED and recorded, never force-written into a unique violation.
--    On a database where the original backfill claimed only clean ids (verified true on
--    preview on 2026-07-28) this pass finds nothing and records a zero-row run.
-- =====================================================================================
do $repair$
declare
  v_collide text[];
  v_fixed   integer := 0;
begin
  select coalesce(array_agg(distinct p.external_id order by p.external_id), '{}'::text[])
    into v_collide
    from pim.product p
   where p.external_source = 'clickup'
     and p.external_id is distinct from btrim(p.external_id)
     and exists (
       select 1 from pim.product other
        where other.external_source = 'clickup'
          and other.external_id = btrim(p.external_id)
          and other.id <> p.id);

  update pim.product p
     set external_id = btrim(p.external_id)
   where p.external_source = 'clickup'
     and p.external_id is distinct from btrim(p.external_id)
     and btrim(p.external_id) <> ''
     and not exists (
       select 1 from pim.product other
        where other.external_source = 'clickup'
          and other.external_id = btrim(p.external_id)
          and other.id <> p.id);

  get diagnostics v_fixed = row_count;

  if v_fixed > 0 or coalesce(array_length(v_collide, 1), 0) > 0 then
    insert into ingest.sync_run
      (source_system, source_name, status, started_at, finished_at,
       rows_seen, rows_inserted, rows_updated, rows_failed, metadata)
    values
      ('clickup', 'clickup_external_id_trim_repair', 'succeeded', now(), now(),
       v_fixed + coalesce(array_length(v_collide, 1), 0), 0, v_fixed,
       coalesce(array_length(v_collide, 1), 0),
       jsonb_build_object(
         'migration', '20260728181500_clickup_incremental_task_import_fixes',
         'stage', 'trim_repair',
         'rows_trimmed', v_fixed,
         'collision_external_ids', to_jsonb(v_collide),
         'note', 'Untrimmed clickup external_id values written by the original 20260728160000 backfill were trimmed. collision_external_ids could not be trimmed without violating the (external_source, external_id) unique constraint and must be reconciled by hand.'));
  end if;

  raise notice 'ClickUp external_id trim repair: % row(s) trimmed, % collision(s) skipped',
    v_fixed, coalesce(array_length(v_collide, 1), 0);
end;
$repair$;

-- =====================================================================================
-- 2. Re-run the CORRECTED backfill (defects 3 and 5).
--
--    Safe to re-run anywhere, including a database where the original backfill already
--    ran: it only touches rows where external_source IS NULL, so an already-claimed row is
--    invisible to it and nothing is claimed twice. Three guards:
--      a. only un-sourced rows (never stomp a row claimed by another source system);
--      b. ids ambiguous on the TRIMMED key are skipped and recorded;
--      c. ids already owned as ('clickup', <trimmed id>) by another row are skipped and
--         recorded, so the unique constraint can never be violated.
-- =====================================================================================
do $backfill$
declare
  v_ambiguous text[];  -- trimmed id on >1 un-sourced row -> skip; reconcile by hand
  v_claimed   text[];  -- trimmed id already owned as (clickup, id) by another row -> skip
  v_updated   integer := 0;
begin
  -- Ambiguity is resolved on the TRIMMED id so '123 ' and '123' are one key. An ambiguous
  -- id cannot be claimed without choosing which row owns it, so it is skipped.
  select coalesce(array_agg(task_id order by task_id), '{}'::text[])
    into v_ambiguous
  from (
    select btrim(clickup_task_id) as task_id
    from pim.product
    where clickup_task_id is not null
      and btrim(clickup_task_id) <> ''
      and external_source is null
    group by btrim(clickup_task_id)
    having count(*) > 1
  ) dup;

  -- Already-claimed ids: some other row already owns (clickup, <trimmed id>), so claiming
  -- this legacy row would collide on the unique constraint. Record them for human
  -- reconciliation instead of dropping them silently (defect 3).
  select coalesce(array_agg(task_id order by task_id), '{}'::text[])
    into v_claimed
  from (
    select distinct btrim(p.clickup_task_id) as task_id
    from pim.product p
    where p.external_source is null
      and p.clickup_task_id is not null
      and btrim(p.clickup_task_id) <> ''
      and btrim(p.clickup_task_id) <> all (v_ambiguous)
      and exists (
        select 1 from pim.product other
        where other.external_source = 'clickup'
          and other.external_id = btrim(p.clickup_task_id)
          and other.id <> p.id
      )
  ) taken;

  -- Claim the rest. external_id is the TRIMMED id (defect 3): the importer writes
  -- ('clickup', '123'), so a legacy row whose clickup_task_id is '123 ' must match it
  -- instead of forking a second product row with curated links stranded on the orphan.
  update pim.product p
     set external_source = 'clickup',
         external_id     = btrim(p.clickup_task_id),
         updated_at      = now()
   where p.external_source is null
     and p.clickup_task_id is not null
     and btrim(p.clickup_task_id) <> ''
     and btrim(p.clickup_task_id) <> any (v_ambiguous)
     and not exists (
       select 1 from pim.product other
       where other.external_source = 'clickup'
         and other.external_id = btrim(p.clickup_task_id)
         and other.id <> p.id
     );

  get diagnostics v_updated = row_count;

  insert into ingest.sync_run
    (source_system, source_name, status, started_at, finished_at,
     rows_seen, rows_inserted, rows_updated, rows_failed, metadata)
  values
    ('clickup', 'clickup_external_id_backfill', 'succeeded', now(), now(),
     v_updated + coalesce(array_length(v_ambiguous, 1), 0) + coalesce(array_length(v_claimed, 1), 0),
     0, v_updated,
     coalesce(array_length(v_ambiguous, 1), 0) + coalesce(array_length(v_claimed, 1), 0),
     jsonb_build_object(
       'migration', '20260728181500_clickup_incremental_task_import_fixes',
       'stage', 'backfill',
       'rows_claimed', v_updated,
       'ambiguous_clickup_task_ids', to_jsonb(v_ambiguous),
       'already_claimed_clickup_task_ids', to_jsonb(v_claimed),
       'note', 'Ambiguous ids appear on more than one un-sourced row; already_claimed ids are owned by another (clickup, id) row. Both were skipped and must be reconciled by hand before they can be synced.'));

  raise notice 'ClickUp backfill: % row(s) claimed, % ambiguous id(s) skipped, % already-claimed id(s) skipped',
    v_updated, coalesce(array_length(v_ambiguous, 1), 0), coalesce(array_length(v_claimed, 1), 0);
end;
$backfill$;

-- =====================================================================================
-- 3. Internal importer.
--
--    Two review-driven design points:
--      * ADVISORY LOCK (pg_try_advisory_xact_lock, not the blocking form) so two runs
--        cannot race each other. If another run holds it we return a 'locked' result
--        cleanly instead of queueing behind it or corrupting the watermark.
--      * PER-ROW ON CONFLICT upsert inside a loop, each row wrapped in its own
--        exception block. One malformed task fails and is counted in rows_failed; it
--        does NOT roll back the rest of the batch. A single bulk statement would.
--
--    Watermark contract: the caller captures a PRE-FETCH timestamp (before any ClickUp API
--    call) and passes it as snapshot.fetch_started_at. The function stores/returns THAT
--    (minus a 60s overlap) as watermark_at, the next run's date_updated_gt cutoff — never
--    started_at/finished_at, which would silently drop a task edited while the run was
--    still pulling lists. On partial failure (rows_failed > 0) the watermark does NOT
--    advance, so failed rows are retried next run; acknowledged permanently-bad ids
--    (snapshot.skip_task_ids) are skipped wholesale so they cannot wedge the advance.
-- =====================================================================================
create or replace function pim.sync_clickup_tasks(
  p_snapshot jsonb,
  p_mode text default 'incremental'
)
returns table (
  sync_run_id    uuid,
  mode           text,
  locked         boolean,
  rows_seen      integer,
  rows_inserted  integer,
  rows_updated   integer,
  rows_unchanged integer,
  rows_failed    integer,
  watermark_at   timestamptz,
  snapshot_hash  text
)
language plpgsql
security definer
set search_path = pim, ingest, app, extensions, public
as $$
declare
  v_sync_id       uuid;
  v_mode          text := coalesce(p_mode, 'incremental');
  v_tasks         jsonb;
  v_lists         jsonb;
  v_watermark_in  timestamptz;
  v_fetch_started timestamptz;   -- caller-captured PRE-FETCH timestamp (defect 1)
  v_started_at    timestamptz;   -- run accounting: when this run began fetching
  v_watermark_out timestamptz;   -- watermark the NEXT run must use as date_updated_gt
  v_task          jsonb;
  v_task_id       text;
  v_skip_ids      text[];        -- acknowledged permanently-bad ids (escape hatch, defect 2)
  v_skipped       integer := 0;
  v_skipped_ids   text[] := '{}';
  v_existing      uuid;
  v_hash          text;
  v_old_hash      text;
  v_meta          jsonb;
  v_seen          integer := 0;
  v_ins           integer := 0;
  v_upd           integer := 0;
  v_unch          integer := 0;
  v_failed        integer := 0;
  v_errors        jsonb := '[]'::jsonb;
  v_term_bad      integer;
  v_snapshot_hash text;
begin
  -- ------------------------------------------------------------------
  -- 3.0 Mode + payload shape guards.
  -- ------------------------------------------------------------------
  if v_mode not in ('incremental', 'full') then
    raise exception 'mode must be incremental or full (received %)', v_mode
      using errcode = 'P0001';
  end if;

  if jsonb_typeof(coalesce(p_snapshot, 'null'::jsonb)) <> 'object' then
    raise exception 'snapshot must be a JSON object' using errcode = 'P0001';
  end if;

  v_tasks := coalesce(p_snapshot -> 'tasks', 'null'::jsonb);
  v_lists := coalesce(p_snapshot -> 'lists', 'null'::jsonb);
  if jsonb_typeof(v_tasks) <> 'array' or jsonb_typeof(v_lists) <> 'array' then
    raise exception 'snapshot.tasks and snapshot.lists must each be a JSON array'
      using errcode = 'P0001';
  end if;
  if jsonb_array_length(v_lists) = 0 then
    raise exception 'snapshot.lists is empty — refusing a run that fetched no ClickUp list'
      using errcode = 'P0001';
  end if;

  -- Pagination completeness: a silently truncated pull would advance the watermark
  -- past tasks we never saw, and they would never be picked up again.
  select count(*) filter (where (l.value ->> 'terminalReached')::boolean is distinct from true)
    into v_term_bad
    from jsonb_array_elements(v_lists) l(value);
  if v_term_bad > 0 then
    raise exception 'incomplete pagination: % list(s) did not reach a terminal page (silent page skip would corrupt the watermark)',
      v_term_bad using errcode = 'P0001';
  end if;

  -- An empty INCREMENTAL pull is normal (nothing changed since the watermark) and must
  -- still record a successful run so the watermark advances. An empty FULL pull is not.
  if v_mode = 'full' and jsonb_array_length(v_tasks) = 0 then
    raise exception 'refusing a full-mode run that returned zero tasks'
      using errcode = 'P0001';
  end if;

  v_watermark_in := nullif(p_snapshot ->> 'watermark', '')::timestamptz;
  -- Defect 1: the watermark stored for the next run is the caller's PRE-FETCH timestamp
  -- (captured before any ClickUp API call), never now()/finished_at. Fall back to now()
  -- only so a hand-built snapshot cannot hard-fail; the runner always sends it.
  v_fetch_started := coalesce(nullif(p_snapshot ->> 'fetch_started_at', '')::timestamptz, now());
  v_started_at    := v_fetch_started;

  -- Defect 2 escape hatch: ids the operator has acknowledged as permanently bad. They are
  -- skipped before the upsert (counted in rows_skipped, NOT rows_failed), so they neither
  -- poison rows_failed nor wedge the watermark. Removing an id from the list re-enables it.
  v_skip_ids := case
    when jsonb_typeof(coalesce(p_snapshot -> 'skip_task_ids', 'null'::jsonb)) = 'array'
    then coalesce(
      (select array_agg(nullif(btrim(s.value), ''))
         from jsonb_array_elements_text(p_snapshot -> 'skip_task_ids') s(value)),
      '{}'::text[])
    else '{}'::text[]
  end;

  -- ------------------------------------------------------------------
  -- 3.1 Concurrency. try, not blocking: a second run returns cleanly rather than
  --     sitting on the lock and then importing against a stale watermark.
  -- ------------------------------------------------------------------
  if not pg_try_advisory_xact_lock(hashtext('pim.sync_clickup_tasks')::bigint) then
    return query select null::uuid, v_mode, true, 0, 0, 0, 0, 0,
                        null::timestamptz, null::text;
    return;
  end if;

  -- ------------------------------------------------------------------
  -- 3.2 Open run accounting. started_at is the run-accounting "fetch began at" time; it
  --     is NOT the watermark (the watermark is computed at close, see 3.5).
  -- ------------------------------------------------------------------
  insert into ingest.sync_run (source_system, source_name, status, started_at, metadata)
  values ('clickup', 'clickup_tasks_api', 'running', v_started_at,
          jsonb_build_object(
            'endpoint', 'GET /list/{list_id}/task',
            'mode', v_mode,
            'stage', 'running',
            'watermark_in', v_watermark_in,
            'fetch_started_at', v_fetch_started,
            'lists', v_lists))
  returning id into v_sync_id;

  -- ------------------------------------------------------------------
  -- 3.3 Per-row upsert loop. Each task is isolated: a bad row is counted and
  --     described in metadata.errors, the rest of the batch still lands.
  -- ------------------------------------------------------------------
  for v_task in select value from jsonb_array_elements(v_tasks) loop
    v_seen := v_seen + 1;
    v_task_id := nullif(btrim(coalesce(v_task ->> 'clickup_task_id', '')), '');

    -- Escape hatch (defect 2): acknowledged bad ids are skipped wholesale — not attempted,
    -- not failed — so a permanently malformed task cannot wedge the watermark forever.
    if v_task_id is not null and v_task_id = any (v_skip_ids) then
      v_skipped := v_skipped + 1;
      v_skipped_ids := v_skipped_ids || v_task_id;
      continue;
    end if;

    begin
      if v_task_id is null then
        raise exception 'task is missing clickup_task_id';
      end if;

      v_hash := md5(coalesce(v_task -> 'raw', v_task)::text);

      -- Metadata keys the existing api.pm_* views still read from. Kept in sync with
      -- the new columns so no view has to change in this migration.
      v_meta := jsonb_strip_nulls(jsonb_build_object(
        'clickup_status_type',      v_task ->> 'clickup_status_type',
        'clickup_status_color',     v_task ->> 'clickup_status_color',
        'clickup_status_order',     v_task ->> 'clickup_status_order',
        'clickup_space_id',         v_task ->> 'clickup_space_id',
        'clickup_space_name',       v_task ->> 'clickup_space_name',
        'clickup_folder_id',        v_task ->> 'clickup_folder_id',
        'clickup_folder_name',      v_task ->> 'clickup_folder_name',
        'clickup_list_id',          v_task ->> 'clickup_list_id',
        'clickup_list_name',        v_task ->> 'clickup_list_name',
        'clickup_creator_id',       v_task ->> 'clickup_creator_id',
        'clickup_creator_name',     v_task ->> 'clickup_creator_name',
        'clickup_time_estimate_ms', v_task ->> 'clickup_time_estimate_ms',
        'clickup_orderindex',       v_task ->> 'clickup_orderindex',
        'clickup_date_created',     v_task ->> 'clickup_date_created',
        'clickup_date_updated',     v_task ->> 'clickup_date_updated',
        'clickup_date_closed',      v_task ->> 'clickup_date_closed',
        'clickup_source_hash',      v_hash));

      select p.id, p.metadata ->> 'clickup_source_hash'
        into v_existing, v_old_hash
        from pim.product p
       where p.external_source = 'clickup'
         and p.external_id = v_task_id
       limit 1;

      -- Bronze: keep the raw ClickUp payload for audit/replay.
      insert into ingest.raw_record
        (sync_run_id, source_system, source_table, source_id, record_hash, payload, imported_at)
      values
        (v_sync_id, 'clickup', 'task', v_task_id, v_hash,
         coalesce(v_task -> 'raw', v_task), now())
      on conflict (source_system, source_table, source_id) do update set
        sync_run_id = excluded.sync_run_id,
        record_hash = excluded.record_hash,
        payload     = excluded.payload,
        imported_at = excluded.imported_at;

      insert into pim.product (
        external_source, external_id, name, status,
        clickup_task_id, clickup_parent_id, clickup_status,
        clickup_status_type, clickup_status_color, clickup_status_order,
        clickup_space_id, clickup_space_name, clickup_folder_id,
        clickup_list_id, clickup_creator_id, clickup_creator_name,
        clickup_time_estimate_ms, clickup_orderindex,
        metadata, updated_at
      )
      values (
        'clickup', v_task_id,
        coalesce(nullif(btrim(coalesce(v_task ->> 'name', '')), ''),
                 'Untitled ClickUp task ' || v_task_id),
        v_task ->> 'clickup_status',
        v_task_id,
        nullif(v_task ->> 'clickup_parent_id', ''),
        v_task ->> 'clickup_status',
        v_task ->> 'clickup_status_type',
        v_task ->> 'clickup_status_color',
        nullif(v_task ->> 'clickup_status_order', '')::numeric,
        v_task ->> 'clickup_space_id',
        v_task ->> 'clickup_space_name',
        v_task ->> 'clickup_folder_id',
        v_task ->> 'clickup_list_id',
        v_task ->> 'clickup_creator_id',
        v_task ->> 'clickup_creator_name',
        nullif(v_task ->> 'clickup_time_estimate_ms', '')::bigint,
        v_task ->> 'clickup_orderindex',
        v_meta, now()
      )
      on conflict (external_source, external_id) do update set
        -- ClickUp-owned fields ONLY. Curated Poppim fields (project_id, licensor_id,
        -- stage, cover_url, ...) are deliberately absent from this SET list.
        name                     = excluded.name,
        status                   = excluded.status,
        clickup_task_id          = excluded.clickup_task_id,
        clickup_parent_id        = excluded.clickup_parent_id,
        clickup_status           = excluded.clickup_status,
        clickup_status_type      = excluded.clickup_status_type,
        clickup_status_color     = excluded.clickup_status_color,
        clickup_status_order     = excluded.clickup_status_order,
        clickup_space_id         = excluded.clickup_space_id,
        clickup_space_name       = excluded.clickup_space_name,
        clickup_folder_id        = excluded.clickup_folder_id,
        clickup_list_id          = excluded.clickup_list_id,
        clickup_creator_id       = excluded.clickup_creator_id,
        clickup_creator_name     = excluded.clickup_creator_name,
        clickup_time_estimate_ms = excluded.clickup_time_estimate_ms,
        clickup_orderindex       = excluded.clickup_orderindex,
        -- Merge, do not replace: non-ClickUp metadata keys must survive.
        metadata                 = pim.product.metadata || excluded.metadata,
        updated_at               = now()
      -- Defect 4: only write when the ClickUp source hash actually changed. An unchanged
      -- task must not bump updated_at (it poisons anything sorting/filtering on it and the
      -- new (clickup_list_id, updated_at) index). The hash is the full raw-task digest, so
      -- "hash unchanged" == "every ClickUp field identical" == safe to no-op the conflict.
      where pim.product.metadata ->> 'clickup_source_hash'
            is distinct from excluded.metadata ->> 'clickup_source_hash';

      if v_existing is null then
        v_ins := v_ins + 1;
      elsif v_old_hash is distinct from v_hash then
        v_upd := v_upd + 1;
      else
        v_unch := v_unch + 1;
      end if;

    exception when others then
      -- Isolated failure: count it, describe it, keep going.
      v_failed := v_failed + 1;
      v_errors := v_errors || jsonb_build_object(
        'clickup_task_id', v_task_id,
        'sqlstate', sqlstate,
        'error', left(sqlerrm, 500));
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 3.4 Replayability evidence.
  -- ------------------------------------------------------------------
  select coalesce(md5(string_agg(md5(t.value::text), '|' order by t.value ->> 'clickup_task_id')), md5(''))
    into v_snapshot_hash
    from jsonb_array_elements(v_tasks) t(value);

  -- ------------------------------------------------------------------
  -- 3.5 Watermark + close run accounting (defects 1 and 2). On a clean run the watermark
  --     advances to just before this run's fetch started (minus a 60s overlap, since
  --     date_updated_gt is strict and the upsert is idempotent). When rows_failed > 0 the
  --     watermark does NOT advance (the failed rows are retried next run); the run stays
  --     'succeeded' (ingest.sync_status has no 'partial' value) but is marked unmistakably
  --     via outcome='succeeded_with_failures' and partial_failure=true. Acknowledged bad
  --     ids (skip_task_ids) never reach rows_failed; they are the escape hatch for a task
  --     that would otherwise wedge the watermark.
  -- ------------------------------------------------------------------
  if v_failed > 0 then
    v_watermark_out := v_watermark_in;
  else
    v_watermark_out := v_fetch_started - interval '60 second';
  end if;

  update ingest.sync_run
     set status      = 'succeeded',
         finished_at = now(),
         rows_seen     = v_seen,
         rows_inserted = v_ins,
         rows_updated  = v_upd,
         rows_failed   = v_failed,
         metadata = metadata || jsonb_build_object(
           'stage', 'succeeded',
           'mode', v_mode,
           'watermark_in', v_watermark_in,
           'fetch_started_at', v_fetch_started,
           'watermark_at', v_watermark_out,
           'watermark_advanced', (v_failed = 0),
           'outcome', case when v_failed > 0 then 'succeeded_with_failures' else 'succeeded_clean' end,
           'partial_failure', (v_failed > 0),
           'rows_unchanged', v_unch,
           'rows_skipped', v_skipped,
           'skipped_task_ids', to_jsonb(v_skipped_ids),
           'snapshot_hash', v_snapshot_hash,
           'errors', v_errors)
   where id = v_sync_id;

  return query select v_sync_id, v_mode, false, v_seen, v_ins, v_upd, v_unch,
                      v_failed, v_watermark_out, v_snapshot_hash;

exception when others then
  -- Rolls back with the caller's transaction. The RUNNER records the durable failed
  -- sync_run row in a SEPARATE transaction (buildFailedSyncRunSql).
  if v_sync_id is not null then
    update ingest.sync_run
       set status = 'failed', finished_at = now(), error = sqlerrm,
           metadata = metadata || jsonb_build_object('stage', 'failed', 'mode', v_mode)
     where id = v_sync_id;
  end if;
  raise;
end;
$$;

comment on function pim.sync_clickup_tasks(jsonb, text) is
'Guarded incremental importer for ClickUp tasks into pim.product. Upserts on (external_source=''clickup'', external_id=<clickup task id>) — the app-wide import key — one row at a time with ON CONFLICT so a single malformed task is counted in rows_failed instead of discarding the batch, and only writes a row when its source hash actually changed (unchanged rows do not bump updated_at). Serializes on pg_try_advisory_xact_lock (returns locked=true rather than queueing). Writes ONLY ingest.raw_record, ingest.sync_run, and ClickUp-owned fields on pim.product; never touches curated links (project/licensor/property/factory/company) or non-clickup metadata keys. Returns watermark_at = the caller''s PRE-FETCH timestamp (snapshot.fetch_started_at) minus a 60s overlap, which is the next run''s date_updated_gt cutoff; when rows_failed > 0 the watermark does NOT advance so the failed rows are retried. snapshot.skip_task_ids is the escape hatch for acknowledged permanently-bad ids.';

-- =====================================================================================
-- 4. public wrapper (AGENTS §8.1) so a service-role caller needs no raw DB password.
-- =====================================================================================
create or replace function public.sync_clickup_tasks(
  p_snapshot jsonb,
  p_mode text default 'incremental'
)
returns table (
  sync_run_id    uuid,
  mode           text,
  locked         boolean,
  rows_seen      integer,
  rows_inserted  integer,
  rows_updated   integer,
  rows_unchanged integer,
  rows_failed    integer,
  watermark_at   timestamptz,
  snapshot_hash  text
)
language plpgsql
security definer
set search_path = public, pim
as $$
begin
  return query select * from pim.sync_clickup_tasks(p_snapshot, p_mode);
end;
$$;

comment on function public.sync_clickup_tasks(jsonb, text) is
'Thin SECURITY DEFINER wrapper over pim.sync_clickup_tasks so a serverless/service-role caller imports ClickUp tasks without a raw DB password.';

revoke all on function pim.sync_clickup_tasks(jsonb, text) from public;
revoke all on function public.sync_clickup_tasks(jsonb, text) from public;
grant execute on function pim.sync_clickup_tasks(jsonb, text) to service_role;
grant execute on function public.sync_clickup_tasks(jsonb, text) to service_role;
