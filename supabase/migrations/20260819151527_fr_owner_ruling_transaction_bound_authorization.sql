-- #1090 / #1140: make the FR owner-ruling authorization ACTUALLY narrow.
--
-- WHAT WAS ALREADY HERE, AND WHY IT IS NOT ENOUGH
-- -----------------------------------------------
-- 20260817124545 installed the transaction-bound licensing write guard.
-- 20260817225127 (#1140's first instalment) only widened the write_kind CHECK
-- constraint to admit the value 'owner_ruling_fr_inactivation'. It taught the
-- guard function NOTHING. As merged, an authorization row carrying that
-- write_kind is therefore the WIDEST authorization in the system: it will pass
-- any core.licensor row, to any status value, in any order, with any metadata
-- change, because app.enforce_licensing_write_authority has no branch for it.
-- Every other write_kind ('coldlion_status', 'scrape_consolidation', ...) has
-- one. This migration closes that hole and nothing else.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
--   1. Adds the binding columns an owner-ruling authorization must carry: which
--      exact row, which exact old and new status, which exact ruling migration,
--      and the exact metadata delta the historical statement writes.
--   2. Adds a table CHECK that refuses a malformed owner-ruling authorization at
--      INSERT time, and refuses those same columns on every other write_kind.
--   3. Adds evidence columns to the immutable guard audit so the audit row
--      states the row, the values and the ruling migration, not just "status".
--   4. Re-derives app.enforce_licensing_write_authority from its CURRENT body
--      (20260817124545, still the live definition -- no later migration replaces
--      it) and adds ONE new branch for 'owner_ruling_fr_inactivation'.
--
-- WHAT IT DELIBERATELY DOES NOT DO
-- --------------------------------
--   * It applies NOTHING to core.licensor. No row is read for a write, no status
--     is changed, no ruling is recorded. This is a compatibility contract only.
--   * It does not promote, unblock or reorder anything. AGENTS.md 6.5 still
--     forbids 20260802170000, 20260817225127 and 20260818174350 from reaching
--     production outside the one bounded FR bundle.
--   * It does not touch core.taxonomy_owner_ruling. The new guard READS that
--     table to prove ordering; it never writes it.
--
-- WHY THE NEW CONSTRAINT IS `NOT VALID`
-- -------------------------------------
-- Guarded forward migration 20260818174350 already ran on preview and left a
-- CONSUMED 'owner_ruling_fr_inactivation' row whose new binding columns are
-- necessarily NULL -- they did not exist when it ran. Validating against history
-- would either fail this migration or force a backfill that rewrites an
-- immutable evidence row. NOT VALID leaves that historical row exactly as it is
-- while enforcing the contract on every INSERT and UPDATE from here on, which is
-- the only direction that can still be got wrong. The guard function below does
-- NOT rely on the constraint: it re-proves every binding itself, so a row that
-- somehow evaded the constraint is still refused at write time.

alter table plm.licensing_write_authorization
  add column if not exists ruling_migration        text,
  add column if not exists target_row_id           uuid,
  add column if not exists target_row_code         text,
  add column if not exists target_row_name         text,
  add column if not exists expected_current_status text,
  add column if not exists expected_new_status     text,
  add column if not exists expected_metadata_delta jsonb;

comment on column plm.licensing_write_authorization.ruling_migration is
  'For owner-ruling authorizations only: the migration version whose exact historical '
  'statement this authorization permits. NULL for every other write_kind.';
comment on column plm.licensing_write_authorization.expected_metadata_delta is
  'For owner-ruling authorizations only: the exact jsonb that must be merged onto '
  'core.licensor.metadata. The guard refuses any other resulting metadata.';

alter table plm.licensing_write_authorization
  drop constraint if exists licensing_write_authorization_owner_ruling_binding;

alter table plm.licensing_write_authorization
  add constraint licensing_write_authorization_owner_ruling_binding check (
    case
      when write_kind = 'owner_ruling_fr_inactivation' then
             target_table = 'core.licensor'::regclass
         and protected_columns = array['status']::text[]
         and ruling_migration in ('20260802171000', '20260818174350')
         and target_row_id is not null
         and target_row_code = 'FR'
         and target_row_name = 'FRIENDS TV'
         and expected_current_status = 'active'
         and expected_new_status = 'inactive'
         and expected_metadata_delta is not null
      else
             ruling_migration is null
         and target_row_id is null
         and target_row_code is null
         and target_row_name is null
         and expected_current_status is null
         and expected_new_status is null
         and expected_metadata_delta is null
    end
  ) not valid;

alter table plm.licensing_write_guard_audit
  add column if not exists target_row_id    uuid,
  add column if not exists ruling_migration text,
  add column if not exists old_status       text,
  add column if not exists new_status       text;

-- The audit table is already immutable by grant (20260817124545 revoked
-- everything from every non-superuser role, including service_role UPDATE and
-- DELETE). Nothing here re-grants any of it.

create or replace function app.enforce_licensing_write_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app, core, plm
as $$
declare
  v_changed text[] := '{}'::text[];
  v_auth plm.licensing_write_authorization%rowtype;
  v_old_metadata jsonb;
  v_new_metadata jsonb;
  v_delta_keys text[];
  v_ruling_ruled_by text;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_audit_row_id uuid;
  v_audit_old_status text;
  v_audit_new_status text;
begin
  if tg_table_name = 'licensor' then
    if tg_op = 'INSERT' or new.name is distinct from old.name then v_changed := array_append(v_changed, 'name'); end if;
    if tg_op = 'INSERT' or new.code is distinct from old.code then v_changed := array_append(v_changed, 'code'); end if;
    if tg_op = 'INSERT' or new.status is distinct from old.status then v_changed := array_append(v_changed, 'status'); end if;
  elsif tg_table_name = 'property' then
    if tg_op = 'INSERT' or new.licensor_id is distinct from old.licensor_id then v_changed := array_append(v_changed, 'licensor_id'); end if;
    if tg_op = 'INSERT' or new.name is distinct from old.name then v_changed := array_append(v_changed, 'name'); end if;
    if tg_op = 'INSERT' or new.code is distinct from old.code then v_changed := array_append(v_changed, 'code'); end if;
    if tg_op = 'INSERT' or new.status is distinct from old.status then v_changed := array_append(v_changed, 'status'); end if;
  end if;
  if cardinality(v_changed) = 0 then return new; end if;

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
  if v_auth.write_kind = 'coldlion_status' and (tg_table_name <> 'property' or v_changed <> array['status']::text[] or new.status not in ('active','inactive')) then
    raise exception 'coldlion_status authorization may change only Property status to active or inactive';
  end if;
  if v_auth.write_kind in ('scrape_consolidation','licensing_review_create') and tg_table_name = 'property' and tg_op = 'INSERT' and new.status <> 'potential' then
    raise exception '% authorization must create Property as potential', v_auth.write_kind;
  end if;
  if v_auth.write_kind = 'scrape_consolidation' and tg_table_name = 'property' and tg_op = 'UPDATE' and new.status is distinct from old.status then
    raise exception 'scrape_consolidation cannot change matched Property status';
  end if;

  -- ---------------------------------------------------------------------
  -- #1140: the FR owner-ruling branch. Everything below is new.
  -- Each condition is refused BY NAME so that a failure says which one, and
  -- so that a test can falsify exactly one condition at a time.
  -- ---------------------------------------------------------------------
  if v_auth.write_kind = 'owner_ruling_fr_inactivation' then
    if tg_table_name <> 'licensor' or tg_op <> 'UPDATE' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only an UPDATE of core.licensor, not % on %', tg_op, tg_table_name;
    end if;
    if v_changed <> array['status']::text[] then
      raise exception 'owner_ruling_fr_inactivation authorization permits only the status column, not %', v_changed;
    end if;
    if v_auth.ruling_migration is null
       or v_auth.ruling_migration not in ('20260802171000', '20260818174350') then
      raise exception 'owner_ruling_fr_inactivation authorization names no known ruling migration (got %)', coalesce(v_auth.ruling_migration, '<null>');
    end if;
    if v_auth.target_row_id is null or new.id <> v_auth.target_row_id then
      raise exception 'owner_ruling_fr_inactivation authorization is bound to a different licensor row';
    end if;
    if old.code is distinct from v_auth.target_row_code
       or new.code is distinct from v_auth.target_row_code
       or v_auth.target_row_code <> 'FR' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only licensor code FR';
    end if;
    if old.name is distinct from v_auth.target_row_name
       or new.name is distinct from v_auth.target_row_name
       or v_auth.target_row_name <> 'FRIENDS TV' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only licensor name FRIENDS TV';
    end if;
    if old.status::text is distinct from v_auth.expected_current_status
       or v_auth.expected_current_status <> 'active' then
      raise exception 'owner_ruling_fr_inactivation authorization expects the row to be active before the write, found %', coalesce(old.status::text, '<null>');
    end if;
    if new.status::text is distinct from v_auth.expected_new_status
       or v_auth.expected_new_status <> 'inactive' then
      raise exception 'owner_ruling_fr_inactivation authorization permits only the target status inactive, not %', coalesce(new.status::text, '<null>');
    end if;

    -- The ruling record must ALREADY exist. The historical statement records
    -- the ruling and only then applies it, so this proves ordering and makes a
    -- standalone status flip -- one with no owner ruling behind it -- impossible.
    select r.ruled_by into v_ruling_ruled_by
    from core.taxonomy_owner_ruling r
    where r.entity_table = 'licensor'
      and r.entity_id = v_auth.target_row_id
      and r.ruled_at = v_ruled_at
    order by r.created_at
    limit 1;
    if v_ruling_ruled_by is null then
      raise exception 'owner_ruling_fr_inactivation refused: the 2026-08-02 owner ruling for this licensor is not recorded in this database yet (record it before the write)';
    end if;

    -- The metadata delta. The guard's changed-column detection deliberately
    -- ignores metadata, so without this an authorized status flip could smuggle
    -- an arbitrary metadata rewrite through alongside it.
    v_old_metadata := coalesce(old.metadata, '{}'::jsonb);
    v_new_metadata := coalesce(new.metadata, '{}'::jsonb);
    if v_auth.expected_metadata_delta is null
       or jsonb_typeof(v_auth.expected_metadata_delta) <> 'object' then
      raise exception 'owner_ruling_fr_inactivation authorization carries no expected metadata delta';
    end if;
    if v_new_metadata <> (v_old_metadata || v_auth.expected_metadata_delta) then
      raise exception 'owner_ruling_fr_inactivation refused: resulting metadata is not exactly the pre-existing metadata merged with the authorized delta';
    end if;
    select array_agg(k order by k) into v_delta_keys
    from jsonb_object_keys(v_auth.expected_metadata_delta) as k;
    if v_delta_keys is distinct from array['owner_ruling']::text[] then
      raise exception 'owner_ruling_fr_inactivation metadata delta must carry exactly the owner_ruling key, got %', coalesce(v_delta_keys::text, '<null>');
    end if;
    if jsonb_typeof(v_auth.expected_metadata_delta -> 'owner_ruling') <> 'object' then
      raise exception 'owner_ruling_fr_inactivation metadata delta owner_ruling must be an object';
    end if;
    select array_agg(k order by k) into v_delta_keys
    from jsonb_object_keys(v_auth.expected_metadata_delta -> 'owner_ruling') as k;
    if v_delta_keys is null
       or not (array['migration','ruled_by','ruled_on','ruling']::text[] <@ v_delta_keys)
       or not (v_delta_keys <@ array['migration','ruled_by','ruled_on','ruling','supersedes']::text[]) then
      raise exception 'owner_ruling_fr_inactivation metadata delta owner_ruling has the wrong key set: %', coalesce(v_delta_keys::text, '<null>');
    end if;
    if v_auth.expected_metadata_delta -> 'owner_ruling' ->> 'ruled_on' <> '2026-08-02' then
      raise exception 'owner_ruling_fr_inactivation metadata delta must state the 2026-08-02 ruling date';
    end if;
    if v_auth.expected_metadata_delta -> 'owner_ruling' ->> 'ruling'
       <> 'never a real licensor; created by mistake' then
      raise exception 'owner_ruling_fr_inactivation metadata delta must state the exact historical ruling text';
    end if;
    if v_auth.expected_metadata_delta -> 'owner_ruling' ->> 'migration' is distinct from v_auth.ruling_migration then
      raise exception 'owner_ruling_fr_inactivation metadata delta names a different migration than the authorization';
    end if;
    -- Not a hardcoded person: the delta must agree with the ruling row already
    -- recorded in this database, whoever that names.
    if v_auth.expected_metadata_delta -> 'owner_ruling' ->> 'ruled_by' is distinct from v_ruling_ruled_by then
      raise exception 'owner_ruling_fr_inactivation metadata delta names a different ruler than the recorded owner ruling';
    end if;

    -- One use means one. A transaction may not stockpile spare authorizations
    -- to replay the ruling, and none may be left behind unconsumed.
    if exists (
      select 1 from plm.licensing_write_authorization a2
      where a2.write_kind = 'owner_ruling_fr_inactivation'
        and a2.id <> v_auth.id
        and a2.consumed_at is null
    ) then
      raise exception 'owner_ruling_fr_inactivation refused: another unconsumed FR owner-ruling authorization exists; exactly one may be outstanding';
    end if;

    v_audit_row_id := v_auth.target_row_id;
    v_audit_old_status := old.status::text;
    v_audit_new_status := new.status::text;
  end if;

  insert into plm.licensing_write_guard_audit
    (authorization_id, target_table, operation, write_kind, protected_columns, plan_id, plan_hash, actor,
     target_row_id, ruling_migration, old_status, new_status)
  values (v_auth.id, tg_relid, tg_op, v_auth.write_kind, v_changed, v_auth.plan_id, v_auth.plan_hash, v_auth.actor,
          v_audit_row_id, v_auth.ruling_migration, v_audit_old_status, v_audit_new_status);
  update plm.licensing_write_authorization
  set consumed_at = clock_timestamp()
  where id = v_auth.id;
  return new;
end;
$$;

revoke all on function app.enforce_licensing_write_authority() from public;
