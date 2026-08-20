-- #1090 / #1339: ERASE licensor FR "FRIENDS TV" from core.licensor.
--
-- WHAT THIS IS, IN ONE LINE
-- ------------------------
-- The removal half of AGENTS.md 6.5. Until this file existed,
-- FR_REMOVAL_VERSIONS in scripts/production_migration_guard.py was empty, so
-- five merged FR migrations could not legally reach production at all. This
-- file is registered there in the SAME commit.
--
-- THE OWNER RULING
-- ----------------
-- Albert Hazan ruled on 2026-08-03 that FR "FRIENDS TV" was never a real
-- licensor and must be REMOVED, not merely flagged. Asked again on 2026-08-20
-- whether FRIENDS TV should disappear entirely or survive as a retired record
-- that old rows could still point at, he answered: "erase FRIENDS TV
-- completely" (issue #1339, owner-answer comment). So this migration performs a
-- genuine DELETE. It is not a status flip and it is not a tombstone. After it,
-- no retired FR row survives in core.licensor.
--
-- DECISION 1 -- THE GUARD IS EXTENDED TO COVER DELETE. READ THE REASONING.
-- -----------------------------------------------------------------------
-- 20260817124545 installed the licensing write guard as
-- `before insert or update` on core.licensor and core.property. A DELETE of the
-- FR row is therefore NOT covered by anything today: the single most
-- destructive operation available on canonical licensing identity is the one
-- operation the guard never sees.
--
-- There were three ways to reach the owner's end state, and only one of them is
-- defensible:
--
--   (a) Delete around the guard -- disable the trigger, use a privileged path,
--       or delete through a view. This spends the guard to avoid extending it,
--       and leaves the hole open for the next author. REJECTED.
--   (b) Keep the covered UPDATE path and "remove" FR by flipping a status or
--       writing a tombstone. Directly contrary to the 2026-08-20 answer, and
--       AGENTS.md 6.5 already refuses to leave production sitting at
--       `inactive`. REJECTED.
--   (c) Extend the guard to DELETE and then perform an AUTHORIZED delete
--       through it. CHOSEN. The one delete this database will ever want on
--       canonical licensing identity is the one that pays for closing the hole.
--
-- Concretely, `app.enforce_licensing_write_authority` now handles `tg_op =
-- 'DELETE'`, the core.licensor trigger is recreated as
-- `before insert or update or delete`, and a DELETE is refused unless it
-- carries a one-use transaction-bound authorization of the new write_kind
-- `owner_ruling_fr_removal`. No other write_kind may ever authorize a DELETE,
-- and `owner_ruling_fr_removal` may never authorize anything BUT a DELETE.
--
-- KNOWN REMAINING GAP, STATED RATHER THAN HIDDEN: core.property's guard trigger
-- is still `before insert or update`, so a DELETE of a canonical Property is
-- still uncovered. core.property is NOT in this migration's object claim -- it
-- belongs to #1238 (and #1177), and claiming it here would be a collision the
-- CI guard is right to refuse. The function below is already DELETE-aware and
-- refuses any DELETE on a table other than core.licensor, so closing the
-- Property half later is a one-line trigger change in #1238's lane. Do not
-- "helpfully" widen the Property trigger from this file.
--
-- DECISION 2 -- THE MECHANISM IS THE ONE 20260819151527 ESTABLISHED.
-- ------------------------------------------------------------------
-- No second mechanism is invented. The delete consumes a transaction-bound,
-- one-use authorization row through `app.enforce_licensing_write_authority`,
-- exactly as the FR inactivation does, and the binding is derived from the row
-- being deleted and from the owner ruling already recorded in this database --
-- never from columns a migration author could forget to fill in.
--
-- DECISION 3 -- WHAT PROVES ANY OF THIS HAPPENED, ONCE FR IS GONE.
-- ----------------------------------------------------------------
-- After this migration the database holds NO trace of FR. Two records are
-- therefore the only surviving explanation, and both are written BEFORE the
-- delete, in the same transaction:
--   * core.taxonomy_owner_ruling gains a row stating in terms that the licensor
--     row was ERASED, on the owner's 2026-08-03 ruling reaffirmed 2026-08-20.
--     The guard REFUSES the delete if that row is missing, so the explanation
--     cannot be skipped.
--   * plm.licensing_write_guard_audit gains an immutable row naming the deleted
--     row id, the operation, the ruling migration and the status the row held
--     when it died. That table was revoked from every non-superuser role by
--     20260817124545 and nothing here re-grants any of it.
--
-- AGENTS.md 6.14 (PUBLIC REPO / no personal identifiers) -- CHECKED, and
-- `ruled_by = 'Albert Hazan (owner)'` STAYS, for the reasons already recorded
-- at length in 20260818174350: 6.14 exempts personal names that are THE DATA
-- ITSELF, core.taxonomy_owner_ruling.ruled_by is exactly that, and the same
-- literal is already stored in that column by two applied/merged migrations.
--
-- PRECONDITIONS, MEASURED LIVE ON PRODUCTION qsllyeztdwjgirsysgai 2026-08-20
-- --------------------------------------------------------------------------
-- (target proved from the Supabase project URL immediately before each read)
--   core.licensor FR "FRIENDS TV" 2b2caddf-4fb0-4fc3-8245-ccd8f8177e48: present,
--     status = 'active'.
--   Of the 24 foreign keys that reference core.licensor, exactly five carry a
--     row pointing at FR:
--       public.assets            2   on delete SET NULL, column nullable
--       public.style_groups      1   on delete SET NULL, column nullable
--       plm.property_import      1   on delete SET NULL, column nullable
--       plm.licensor_import      1   on delete RESTRICT, column NOT NULL
--       core.property            1   on delete RESTRICT, column NOT NULL
--     Every other referrer is 0.
--
-- The four dependants this migration owns are re-homed EXPLICITLY below rather
-- than left to the foreign key's own ON DELETE action, so the counts are
-- asserted and the intent is stated rather than inferred from a constraint.
--
-- *** THE SEQUENCING BLOCK, STATED LOUDLY ***
-- core.property.licensor_id is NOT NULL and ON DELETE RESTRICT, and one row
-- (FK "FRIDA KAHLO", cb26ec58-0edb-4d45-8c0b-ba283ffb23f8) still points at FR.
-- That row is NOT this migration's to touch: owner ruling AGENTS.md 6.15
-- (2026-08-19) puts core.property Universe A on #1238's deletion path, and
-- #1339 records the decision to leave it there. So this migration CANNOT
-- complete until #1238 has removed it. It says so, by name, in a refusal
-- message rather than dying on a bare foreign-key error. AGENTS.md 6.5's own
-- description of "the removal work" includes re-pointing FK FRIDA KAHLO; that
-- part now belongs to #1238, and this file is the rest of it.
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO
-- --------------------------------------------
--   * It does not write, re-point or delete anything in core.property.
--   * It does not promote or reorder anything. AGENTS.md 6.5 still requires ONE
--     bounded production apply carrying 20260802170000, 20260817225127,
--     20260818174350, this version and (ordering permitting) 20260819151527.
--   * It does not weaken the guard's co-presence check. Registering this
--     version in FR_REMOVAL_VERSIONS is a DATA change to the guard, which is
--     the only legitimate way that hold releases.
--   * It changes catalogue shape (a constraint, a function and a trigger), so
--     it makes no claim of being a pure-data change and declares no such token.

-- ---------------------------------------------------------------------------
-- 1. Admit the new, narrow write kind.
-- ---------------------------------------------------------------------------
alter table plm.licensing_write_authorization
  drop constraint if exists licensing_write_authorization_write_kind_check;

alter table plm.licensing_write_authorization
  add constraint licensing_write_authorization_write_kind_check
  check (write_kind in (
    'scrape_consolidation',
    'licensing_review_create',
    'coldlion_status',
    'canonical_merge',
    'owner_ruling_fr_inactivation',
    'owner_ruling_fr_removal'
  ));

-- ---------------------------------------------------------------------------
-- 2. The guard, re-derived from its CURRENT body (20260819151527) with DELETE
--    handling added. Every pre-existing branch is reproduced unchanged; the
--    only edits are the DELETE plumbing and the new removal branch.
--
--    NOTE the `if tg_op <> 'DELETE'` fences around the pre-existing branches.
--    In a DELETE trigger NEW is unassigned, and referencing it raises before
--    any of those conditions can be judged. The fences are load-bearing, not
--    tidiness -- do not "simplify" them away.
-- ---------------------------------------------------------------------------
create or replace function app.enforce_licensing_write_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app, core, plm
as $$
declare
  v_changed text[] := '{}'::text[];
  v_auth plm.licensing_write_authorization%rowtype;
  v_result record;
  v_old_metadata jsonb;
  v_new_metadata jsonb;
  v_ruling jsonb;
  v_ruling_keys text[];
  v_recorded_ruler text;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_erased_at constant timestamptz := timestamptz '2026-08-20 12:00:00+00';
  v_audit_row_id uuid;
  v_audit_ruling_migration text;
  v_audit_old_status text;
  v_audit_new_status text;
begin
  if tg_op = 'DELETE' then
    v_result := old;
  else
    v_result := new;
  end if;

  if tg_op = 'DELETE' then
    -- #1339: DELETE coverage. Only core.licensor is covered today, and only
    -- because that is the only guard trigger this migration is entitled to
    -- touch. Any other table reaching this branch means a trigger was widened
    -- without widening this function, so refuse rather than fall through to a
    -- permissive path.
    if tg_table_name <> 'licensor' then
      raise exception 'licensing canonical write refused: DELETE is not authorized on %.%', tg_table_schema, tg_table_name;
    end if;
    -- A delete removes the whole protected identity, so it must be authorized
    -- for the whole protected identity.
    v_changed := array['name','code','status'];
  elsif tg_table_name = 'licensor' then
    if tg_op = 'INSERT' or new.name is distinct from old.name then v_changed := array_append(v_changed, 'name'); end if;
    if tg_op = 'INSERT' or new.code is distinct from old.code then v_changed := array_append(v_changed, 'code'); end if;
    if tg_op = 'INSERT' or new.status is distinct from old.status then v_changed := array_append(v_changed, 'status'); end if;
  elsif tg_table_name = 'property' then
    if tg_op = 'INSERT' or new.licensor_id is distinct from old.licensor_id then v_changed := array_append(v_changed, 'licensor_id'); end if;
    if tg_op = 'INSERT' or new.name is distinct from old.name then v_changed := array_append(v_changed, 'name'); end if;
    if tg_op = 'INSERT' or new.code is distinct from old.code then v_changed := array_append(v_changed, 'code'); end if;
    if tg_op = 'INSERT' or new.status is distinct from old.status then v_changed := array_append(v_changed, 'status'); end if;
  end if;
  if cardinality(v_changed) = 0 then return v_result; end if;

  select * into v_auth
  from plm.licensing_write_authorization a
  where a.backend_pid = pg_backend_pid()
    and a.transaction_id = txid_current()
    and a.target_table = tg_relid
    and a.expires_at > clock_timestamp()
    and a.consumed_at is null
    and a.protected_columns @> v_changed
    and v_changed @> a.protected_columns
  order by a.created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'licensing canonical write refused: no exact transaction-bound authorization for %.% columns %', tg_table_schema, tg_table_name, v_changed;
  end if;

  -- The two halves of the DELETE contract, stated separately so a failure names
  -- which half failed: no other write kind may delete, and the removal kind may
  -- do nothing but delete.
  if tg_op = 'DELETE' and v_auth.write_kind <> 'owner_ruling_fr_removal' then
    raise exception 'licensing canonical write refused: write_kind % may not authorize a DELETE of %.%', v_auth.write_kind, tg_table_schema, tg_table_name;
  end if;
  if v_auth.write_kind = 'owner_ruling_fr_removal' and tg_op <> 'DELETE' then
    raise exception 'owner_ruling_fr_removal authorization permits only a DELETE of core.licensor, not % on %', tg_op, tg_table_name;
  end if;

  if tg_op <> 'DELETE' then
    if v_auth.write_kind = 'coldlion_status' and (tg_table_name <> 'property' or v_changed <> array['status']::text[] or new.status not in ('active','inactive')) then
      raise exception 'coldlion_status authorization may change only Property status to active or inactive';
    end if;
    if v_auth.write_kind in ('scrape_consolidation','licensing_review_create') and tg_table_name = 'property' and tg_op = 'INSERT' and new.status <> 'potential' then
      raise exception '% authorization must create Property as potential', v_auth.write_kind;
    end if;
    if v_auth.write_kind = 'scrape_consolidation' and tg_table_name = 'property' and tg_op = 'UPDATE' and new.status is distinct from old.status then
      raise exception 'scrape_consolidation cannot change matched Property status';
    end if;
  end if;

  -- ---------------------------------------------------------------------
  -- #1140: the FR owner-ruling INACTIVATION branch. Reproduced unchanged from
  -- 20260819151527 apart from its DELETE fence.
  -- ---------------------------------------------------------------------
  if tg_op <> 'DELETE' and v_auth.write_kind = 'owner_ruling_fr_inactivation' then
    if tg_table_name <> 'licensor' or tg_op <> 'UPDATE' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only an UPDATE of core.licensor, not % on %', tg_op, tg_table_name;
    end if;
    if v_changed <> array['status']::text[] then
      raise exception 'owner_ruling_fr_inactivation authorization permits only the status column, not %', v_changed;
    end if;
    if old.code is distinct from 'FR' or new.code is distinct from 'FR' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only licensor code FR, not %', coalesce(new.code, '<null>');
    end if;
    if old.name is distinct from 'FRIENDS TV' or new.name is distinct from 'FRIENDS TV' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only licensor name FRIENDS TV, not %', coalesce(new.name, '<null>');
    end if;
    if old.status::text <> 'active' then
      raise exception 'owner_ruling_fr_inactivation expects the row to be active before the write, found %', coalesce(old.status::text, '<null>');
    end if;
    if new.status::text <> 'inactive' then
      raise exception 'owner_ruling_fr_inactivation permits only the target status inactive, not %', coalesce(new.status::text, '<null>');
    end if;

    select r.ruled_by into v_recorded_ruler
    from core.taxonomy_owner_ruling r
    where r.entity_table = 'licensor'
      and r.entity_id = new.id
      and r.ruled_at = v_ruled_at
    order by r.created_at
    limit 1;
    if v_recorded_ruler is null then
      raise exception 'owner_ruling_fr_inactivation refused: the 2026-08-02 owner ruling for this licensor is not recorded in this database yet (record it before the write)';
    end if;

    v_old_metadata := coalesce(old.metadata, '{}'::jsonb);
    v_new_metadata := coalesce(new.metadata, '{}'::jsonb);
    v_ruling := v_new_metadata -> 'owner_ruling';
    if v_ruling is null then
      raise exception 'owner_ruling_fr_inactivation refused: the write records no owner_ruling metadata';
    end if;
    if v_new_metadata <> (v_old_metadata || jsonb_build_object('owner_ruling', v_ruling)) then
      raise exception 'owner_ruling_fr_inactivation refused: the write changes metadata outside the owner_ruling record';
    end if;
    if jsonb_typeof(v_ruling) <> 'object' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata must be an object, not %', jsonb_typeof(v_ruling);
    end if;
    select array_agg(k order by k) into v_ruling_keys from jsonb_object_keys(v_ruling) as k;
    if v_ruling_keys is null
       or not (array['migration','ruled_by','ruled_on','ruling']::text[] <@ v_ruling_keys)
       or not (v_ruling_keys <@ array['migration','ruled_by','ruled_on','ruling','supersedes']::text[]) then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata has the wrong key set: %', coalesce(v_ruling_keys::text, '<null>');
    end if;
    -- `is distinct from`, NOT `<>`. See 20260819151527 for why every value
    -- comparison in this branch is written this way. Do not simplify them.
    if v_ruling ->> 'ruled_on' is distinct from '2026-08-02' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata must state the 2026-08-02 ruling date, not %', coalesce(v_ruling ->> 'ruled_on', '<null>');
    end if;
    if v_ruling ->> 'ruling' is distinct from 'never a real licensor; created by mistake' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata must state the exact historical ruling text';
    end if;
    if v_ruling ->> 'migration' is null
       or v_ruling ->> 'migration' not in ('20260802171000', '20260818174350') then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata names an unknown ruling migration (%)', coalesce(v_ruling ->> 'migration', '<null>');
    end if;
    if v_ruling ? 'supersedes'
       and v_ruling ->> 'supersedes' is distinct from '20260802171000' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata supersedes an unexpected migration (%)', coalesce(v_ruling ->> 'supersedes', '<null>');
    end if;
    if v_ruling ->> 'ruled_by' is distinct from v_recorded_ruler then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata names a different ruler than the recorded owner ruling';
    end if;

    if exists (
      select 1 from plm.licensing_write_authorization a2
      where a2.write_kind = 'owner_ruling_fr_inactivation'
        and a2.id <> v_auth.id
        and a2.consumed_at is null
    ) then
      raise exception 'owner_ruling_fr_inactivation refused: another unconsumed FR owner-ruling authorization exists; exactly one may be outstanding';
    end if;

    v_audit_row_id := new.id;
    v_audit_ruling_migration := v_ruling ->> 'migration';
    v_audit_old_status := old.status::text;
    v_audit_new_status := new.status::text;
  end if;

  -- ---------------------------------------------------------------------
  -- #1339: the FR owner-ruling ERASURE branch. Everything below is new.
  -- Each condition is refused BY NAME, so a failure says which one failed and
  -- a test can falsify exactly one condition at a time.
  -- ---------------------------------------------------------------------
  if v_auth.write_kind = 'owner_ruling_fr_removal' then
    if tg_table_name <> 'licensor' then
      raise exception 'owner_ruling_fr_removal authorization permits only core.licensor, not %', tg_table_name;
    end if;
    if v_changed <> array['name','code','status']::text[] then
      raise exception 'owner_ruling_fr_removal authorization must cover the whole protected identity, not %', v_changed;
    end if;
    if old.code is distinct from 'FR' then
      raise exception 'owner_ruling_fr_removal authorization permits only licensor code FR, not %', coalesce(old.code, '<null>');
    end if;
    if old.name is distinct from 'FRIENDS TV' then
      raise exception 'owner_ruling_fr_removal authorization permits only licensor name FRIENDS TV, not %', coalesce(old.name, '<null>');
    end if;

    -- Both rulings must ALREADY be recorded: the original 2026-08-02 finding
    -- that FR was never a real licensor, and the 2026-08-20 reaffirmation that
    -- the row is to be ERASED rather than retired. Once the row is gone those
    -- records are the only explanation left in this database, so a delete that
    -- has not written them first is refused. This is the same ordering proof
    -- the inactivation branch makes, applied to the irreversible step.
    if not exists (
      select 1 from core.taxonomy_owner_ruling r
      where r.entity_table = 'licensor' and r.entity_id = old.id and r.ruled_at = v_ruled_at
    ) then
      raise exception 'owner_ruling_fr_removal refused: the original 2026-08-02 owner ruling for this licensor is not recorded in this database';
    end if;
    select r.ruled_by into v_recorded_ruler
    from core.taxonomy_owner_ruling r
    where r.entity_table = 'licensor'
      and r.entity_id = old.id
      and r.ruled_at = v_erased_at
    order by r.created_at
    limit 1;
    if v_recorded_ruler is null then
      raise exception 'owner_ruling_fr_removal refused: the 2026-08-20 erasure ruling for this licensor is not recorded in this database yet (record it before the delete)';
    end if;

    -- One use means one, exactly as for the inactivation.
    if exists (
      select 1 from plm.licensing_write_authorization a2
      where a2.write_kind = 'owner_ruling_fr_removal'
        and a2.id <> v_auth.id
        and a2.consumed_at is null
    ) then
      raise exception 'owner_ruling_fr_removal refused: another unconsumed FR removal authorization exists; exactly one may be outstanding';
    end if;

    v_audit_row_id := old.id;
    v_audit_ruling_migration := '20260820183334';
    v_audit_old_status := old.status::text;
    v_audit_new_status := null;
  end if;

  insert into plm.licensing_write_guard_audit
    (authorization_id, target_table, operation, write_kind, protected_columns, plan_id, plan_hash, actor,
     target_row_id, ruling_migration, old_status, new_status)
  values (v_auth.id, tg_relid, tg_op, v_auth.write_kind, v_changed, v_auth.plan_id, v_auth.plan_hash, v_auth.actor,
          v_audit_row_id, v_audit_ruling_migration, v_audit_old_status, v_audit_new_status);
  update plm.licensing_write_authorization
  set consumed_at = clock_timestamp()
  where id = v_auth.id;
  return v_result;
end;
$$;

revoke all on function app.enforce_licensing_write_authority() from public;

-- ---------------------------------------------------------------------------
-- 3. Widen the core.licensor trigger to DELETE. A trigger's event list cannot
--    be altered in place, so it is dropped and recreated under the SAME name.
--    core.property's trigger is deliberately untouched -- see the header.
-- ---------------------------------------------------------------------------
drop trigger if exists licensor_licensing_write_guard on core.licensor;
create trigger licensor_licensing_write_guard before insert or update or delete on core.licensor
for each row execute function app.enforce_licensing_write_authority();

-- ---------------------------------------------------------------------------
-- 4. Record the ruling, re-home the dependants this migration owns, and erase
--    the row.
--
--    The whole block is skipped when FR is already absent. That is not a soft
--    failure: this migration's contract is "no FRIENDS TV row exists in
--    core.licensor", and a database where it never existed already satisfies
--    it. The from-empty CI replay is exactly that database. When the row IS
--    present, every step below is strict and a wrong precondition aborts the
--    transaction loudly.
-- ---------------------------------------------------------------------------
do $fr_erase$
declare
  v_fr_id constant uuid := '2b2caddf-4fb0-4fc3-8245-ccd8f8177e48'::uuid;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_erased_at constant timestamptz := timestamptz '2026-08-20 12:00:00+00';
  v_ruler constant text := 'Albert Hazan (owner)';
  v_plan constant uuid := '3c9a1f64-2b57-5d18-9a3e-6f0b1c7d4e22'::uuid;
  v_evidence constant text :=
    'Owner ruling given on 2026-08-03 (AGENTS.md 6.5) that FR "FRIENDS TV" was '
    'never a real licensor and must be removed, reaffirmed in plain terms on '
    '2026-08-20 as "erase FRIENDS TV completely" (issue #1339 owner answer). '
    'Applied by migration 20260820183334.';
  v_row core.licensor%rowtype;
  v_rows integer;
  v_blockers integer;
  v_assets integer;
  v_style_groups integer;
  v_property_import integer;
  v_licensor_import integer;
begin
  select * into v_row from core.licensor where id = v_fr_id;
  if not found then
    -- Nothing to erase. Prove that no OTHER row is wearing the identity before
    -- calling this satisfied, so a re-keyed FR can never pass silently.
    if exists (select 1 from core.licensor where code = 'FR' or name = 'FRIENDS TV') then
      raise exception 'FR erasure refused: % is absent but another core.licensor row still carries code FR or name FRIENDS TV', v_fr_id;
    end if;
    raise notice 'FR "FRIENDS TV" is already absent from core.licensor; nothing to erase.';
    return;
  end if;
  if v_row.code is distinct from 'FR' or v_row.name is distinct from 'FRIENDS TV' then
    raise exception 'FR erasure refused: % is % / %, not FR / FRIENDS TV', v_fr_id, coalesce(v_row.code, '<null>'), coalesce(v_row.name, '<null>');
  end if;

  -- 4a. The ruling record. Written FIRST, because the guard refuses the delete
  --     without it and because it is the only explanation that outlives the row.
  insert into core.taxonomy_owner_ruling (
    entity_table, entity_id, entity_code, entity_name, ruling, ruled_by,
    ruled_at, ruling_evidence, action_taken, open_questions
  )
  select 'licensor', v_fr_id, 'FR', 'FRIENDS TV',
    'Licensor FR "FRIENDS TV" was never a real licensor. It was created by '
    'mistake, and the owner ruled that it be ERASED entirely rather than kept '
    'as a retired or inactive record.',
    v_ruler, v_erased_at, v_evidence,
    'core.licensor row 2b2caddf-4fb0-4fc3-8245-ccd8f8177e48 was ERASED '
    '(deleted) by migration 20260820183334, under a one-use '
    'transaction-bound owner_ruling_fr_removal authorization consumed through '
    'app.enforce_licensing_write_authority. Dependent rows in public.assets '
    '(2), public.style_groups (1) and plm.property_import (1) had their '
    'licensor link cleared; the plm.licensor_import staging row (1) was '
    'deleted. This ruling row and the plm.licensing_write_guard_audit row are '
    'the only remaining record that FRIENDS TV ever existed as a licensor.',
    'The FR-parented core.property row is outside this migration''s object '
    'claim and is handled by issue #1238 under owner ruling AGENTS.md 6.15.'
  where not exists (
    select 1 from core.taxonomy_owner_ruling
    where entity_table = 'licensor' and entity_id = v_fr_id and ruled_at = v_erased_at
  );

  if not exists (
    select 1 from core.taxonomy_owner_ruling
    where entity_table = 'licensor' and entity_id = v_fr_id and ruled_at = v_ruled_at
  ) then
    raise exception 'FR erasure refused: the original 2026-08-02 owner ruling is not recorded. Migration 20260818174350 must run before this one.';
  end if;

  -- 4b. Re-home the dependants this migration owns. Explicit, counted and
  --     stated -- not left to each foreign key's ON DELETE action.
  update public.assets set licensor_id = null where licensor_id = v_fr_id;
  get diagnostics v_assets = row_count;
  update public.style_groups set licensor_id = null where licensor_id = v_fr_id;
  get diagnostics v_style_groups = row_count;
  update plm.property_import set licensor_id = null where licensor_id = v_fr_id;
  get diagnostics v_property_import = row_count;
  -- plm.licensor_import is the DesignFlow staging row that created FR in the
  -- first place. Its licensor_id is NOT NULL, so the link cannot be cleared,
  -- and a staging row for a licensor that was never real has no meaning once
  -- the licensor is gone. It is deleted.
  delete from plm.licensor_import where licensor_id = v_fr_id;
  get diagnostics v_licensor_import = row_count;
  raise notice 'FR dependants re-homed: assets %, style_groups %, property_import %, licensor_import rows deleted %',
    v_assets, v_style_groups, v_property_import, v_licensor_import;

  -- 4c. The one dependant this migration must NOT touch.
  select count(*) into v_blockers from core.property where licensor_id = v_fr_id;
  if v_blockers > 0 then
    raise exception 'FR erasure BLOCKED: % core.property row(s) still reference FR. core.property.licensor_id is NOT NULL and ON DELETE RESTRICT, and core.property is outside this migration''s object claim (owner ruling AGENTS.md 6.15, issue #1238). Land #1238''s removal of the FR-parented Property row before this bundle is applied. Do not re-point or delete that row from here.', v_blockers;
  end if;

  -- 4d. The authorized erasure.
  insert into plm.licensing_write_authorization (
    backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash,
    actor, protected_columns, expires_at
  ) values (
    pg_backend_pid(), txid_current(), 'core.licensor',
    'owner_ruling_fr_removal', v_plan,
    '9b1f0c3d5e7a2846b0d9f4c17e35a8629d40bb71c2e6f8039a5d7c41e8b26f03',
    'shared-db migration 20260820183334', array['name','code','status'],
    clock_timestamp() + interval '1 minute'
  );

  delete from core.licensor where id = v_fr_id;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'FR erasure deleted % rows, expected 1', v_rows;
  end if;

  if exists (select 1 from core.licensor where id = v_fr_id or code = 'FR' or name = 'FRIENDS TV') then
    raise exception 'FR erasure left a FRIENDS TV row behind in core.licensor';
  end if;
  if not exists (
    select 1 from plm.licensing_write_authorization
    where plan_id = v_plan and consumed_at is not null
      and backend_pid = pg_backend_pid() and transaction_id = txid_current()
  ) then
    raise exception 'FR removal authorization was not consumed in its transaction';
  end if;
  if not exists (
    select 1 from plm.licensing_write_guard_audit
    where plan_id = v_plan and write_kind = 'owner_ruling_fr_removal'
      and target_table = 'core.licensor'::regclass and operation = 'DELETE'
      and target_row_id = v_fr_id and ruling_migration = '20260820183334'
      and protected_columns = array['name','code','status']::text[]
  ) then
    raise exception 'FR erasure left no immutable guard audit';
  end if;
end;
$fr_erase$;

-- ---------------------------------------------------------------------------
-- 5. Verify. Shape is asserted from the catalogue; the only rows counted are in
--    this migration's own tables and are reached by indexed or tiny predicates,
--    so nothing here is an expensive statement.
-- ---------------------------------------------------------------------------
do $verify$
declare
  v_events text;
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'licensing_write_authorization_write_kind_check'
      and conrelid = 'plm.licensing_write_authorization'::regclass
      and pg_get_constraintdef(oid) like '%owner_ruling_fr_removal%'
  ) then
    raise exception 'verify: the write_kind constraint does not admit owner_ruling_fr_removal';
  end if;

  -- pg_trigger.tgtype bits: 4 = INSERT, 8 = DELETE, 16 = UPDATE.
  select case when t.tgtype & 4 > 0 then 'insert ' else '' end
      || case when t.tgtype & 8 > 0 then 'delete ' else '' end
      || case when t.tgtype & 16 > 0 then 'update' else '' end
    into v_events
  from pg_trigger t
  where t.tgrelid = 'core.licensor'::regclass
    and t.tgname = 'licensor_licensing_write_guard'
    and not t.tgisinternal;
  if v_events is null then
    raise exception 'verify: the core.licensor licensing write guard trigger is missing';
  end if;
  if position('insert' in v_events) = 0
     or position('delete' in v_events) = 0
     or position('update' in v_events) = 0 then
    raise exception 'verify: the core.licensor guard trigger does not cover insert, update AND delete (it covers: %)', v_events;
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'enforce_licensing_write_authority'
      and p.prosrc like '%owner_ruling_fr_removal%'
  ) then
    raise exception 'verify: the guard function has no owner_ruling_fr_removal branch';
  end if;

  if exists (select 1 from core.licensor where code = 'FR' or name = 'FRIENDS TV') then
    raise exception 'verify: a FRIENDS TV licensor row still exists in core.licensor';
  end if;

  if exists (
    select 1 from plm.licensing_write_authorization
    where write_kind = 'owner_ruling_fr_removal' and consumed_at is null
  ) then
    raise exception 'verify: an unconsumed FR removal authorization was left outstanding';
  end if;
end;
$verify$;
