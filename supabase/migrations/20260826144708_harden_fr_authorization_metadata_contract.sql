-- #1259: finish binding the FR authorization metadata shapes without weakening
-- the transaction-bound licensing write guard.
--
-- 20260819151527 already rejects arbitrary supersedes VALUES, but it still
-- admits the key on historical statement 20260802171000 and permits replacement
-- statement 20260818174350 to omit it. This fix-forward definition binds each
-- admitted migration to its exact metadata shape.
--
-- The exactly-one-outstanding check remains deliberately expiry-blind. An
-- expired, committed FR authorization is evidence of an abandoned or failed
-- bundle and fails closed until a superuser investigates and removes that one
-- stale row. It is not silently ignored.
--
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
  v_ruling jsonb;
  v_ruling_keys text[];
  v_recorded_ruler text;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_audit_row_id uuid;
  v_audit_ruling_migration text;
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
  -- Preserve the later #1429 lifecycle contract: ColdLion may make an
  -- exact-column UPDATE of status on either canonical Licensor or Property.
  -- This CREATE OR REPLACE must not regress that forward expansion merely
  -- because the FR branch was derived from the earlier guard definition.
  if v_auth.write_kind = 'coldlion_status' and (tg_table_name not in ('licensor','property') or tg_op <> 'UPDATE' or v_changed <> array['status']::text[] or new.status not in ('active','inactive')) then
    raise exception 'coldlion_status authorization may change only Licensor or Property status to active or inactive';
  end if;
  if v_auth.write_kind in ('scrape_consolidation','licensing_review_create') and tg_table_name = 'property' and tg_op = 'INSERT' and new.status <> 'potential' then
    raise exception '% authorization must create Property as potential', v_auth.write_kind;
  end if;
  if v_auth.write_kind = 'scrape_consolidation' and tg_table_name = 'property' and tg_op = 'UPDATE' and new.status is distinct from old.status then
    raise exception 'scrape_consolidation cannot change matched Property status';
  end if;

  -- ---------------------------------------------------------------------
  -- #1140: the FR owner-ruling branch. Everything below is new.
  -- Each condition is refused BY NAME, so a failure says which one failed and
  -- a test can falsify exactly one condition at a time.
  -- ---------------------------------------------------------------------
  if v_auth.write_kind = 'owner_ruling_fr_inactivation' then
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

    -- The ruling record must ALREADY exist. Both the held historical statement
    -- and its guarded replacement record the ruling and only then apply it, so
    -- this proves ordering and makes a standalone status flip -- one with no
    -- owner ruling behind it -- impossible.
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

    -- The metadata. The guard's changed-column detection deliberately ignores
    -- metadata, so without this an authorized status flip could smuggle an
    -- arbitrary metadata rewrite through alongside it. The ONLY difference
    -- permitted between the old and the new metadata is the owner_ruling key.
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
    -- `is distinct from`, NOT `<>`. A JSON null makes `->>` return SQL NULL, and
    -- `NULL <> '2026-08-02'` is UNKNOWN -- the `if` would not fire and a
    -- present-but-null ruling date would sail straight through. Same defect
    -- class as #1219: a present-but-null value passing a test written for a
    -- missing one. Every value comparison in this branch uses `is distinct
    -- from` for that reason. Do not "simplify" them back to `<>`.
    if v_ruling ->> 'ruled_on' is distinct from '2026-08-02' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata must state the 2026-08-02 ruling date, not %', coalesce(v_ruling ->> 'ruled_on', '<null>');
    end if;
    if v_ruling ->> 'ruling' is distinct from 'never a real licensor; created by mistake' then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata must state the exact historical ruling text';
    end if;
    -- The set is closed BY NAME: the held historical statement and its merged
    -- guarded replacement, and nothing else. A future forward migration must
    -- add itself here deliberately.
    if v_ruling ->> 'migration' is null
       or v_ruling ->> 'migration' not in ('20260802171000', '20260818174350') then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata names an unknown ruling migration (%)', coalesce(v_ruling ->> 'migration', '<null>');
    end if;
    -- The metadata shapes are bound one-for-one to the two admitted statements.
    -- Historical 20260802171000 never carried a supersedes key. Replacement
    -- 20260818174350 must carry the exact pointer to that historical statement.
    if v_ruling ->> 'migration' = '20260802171000'
       and v_ruling ? 'supersedes' then
      raise exception 'owner_ruling_fr_inactivation refused: historical ruling migration 20260802171000 must not carry supersedes';
    end if;
    if v_ruling ->> 'migration' = '20260818174350'
       and (
         not (v_ruling ? 'supersedes')
         or v_ruling ->> 'supersedes' is distinct from '20260802171000'
       ) then
      raise exception 'owner_ruling_fr_inactivation refused: replacement ruling migration 20260818174350 must supersede 20260802171000, not %', coalesce(v_ruling ->> 'supersedes', '<missing>');
    end if;
    -- Not a hardcoded person: the metadata must agree with the ruling already
    -- recorded in this database, whoever that names.
    if v_ruling ->> 'ruled_by' is distinct from v_recorded_ruler then
      raise exception 'owner_ruling_fr_inactivation refused: owner_ruling metadata names a different ruler than the recorded owner ruling';
    end if;

    -- One use means one. A transaction may not stockpile spare authorizations
    -- to replay the ruling, and none may be left behind unconsumed. This check
    -- deliberately ignores expires_at: an expired, committed FR authorization
    -- is a fail-closed operational latch and must be investigated and removed
    -- by a superuser before the guarded statement is retried.
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

  insert into plm.licensing_write_guard_audit
    (authorization_id, target_table, operation, write_kind, protected_columns, plan_id, plan_hash, actor,
     target_row_id, ruling_migration, old_status, new_status)
  values (v_auth.id, tg_relid, tg_op, v_auth.write_kind, v_changed, v_auth.plan_id, v_auth.plan_hash, v_auth.actor,
          v_audit_row_id, v_audit_ruling_migration, v_audit_old_status, v_audit_new_status);
  update plm.licensing_write_authorization
  set consumed_at = clock_timestamp()
  where id = v_auth.id;
  return new;
end;
$$;

revoke all on function app.enforce_licensing_write_authority() from public;
