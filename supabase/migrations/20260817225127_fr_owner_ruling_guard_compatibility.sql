-- #1090 / #1140: narrowly authorize the already-held 20260802171000 owner
-- ruling when it later ships inside the complete AGENTS.md section 6.5 bundle.

alter table plm.licensing_write_authorization
  drop constraint licensing_write_authorization_write_kind_check;

alter table plm.licensing_write_authorization
  add constraint licensing_write_authorization_write_kind_check
  check (write_kind in (
    'scrape_consolidation',
    'licensing_review_create',
    'coldlion_status',
    'canonical_merge',
    'owner_ruling_fr_inactivation'
  ));

create or replace function app.enforce_licensing_write_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app, core, plm
as $$
declare
  v_changed text[] := '{}'::text[];
  v_auth plm.licensing_write_authorization%rowtype;
  v_expected_metadata jsonb;
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

  if tg_table_name = 'licensor'
     and tg_op = 'UPDATE'
     and current_setting('app.shared_db_migration_version', true) = '20260802171000'
     and session_user = current_user
     and old.code = 'FR'
     and old.name = 'FRIENDS TV'
     and old.status = 'active'
     and new.code = old.code
     and new.name = old.name
     and new.status = 'inactive'
     and v_changed = array['status']::text[] then
    v_expected_metadata := old.metadata || jsonb_build_object(
      'owner_ruling', jsonb_build_object(
        'ruled_by', 'Albert Hazan (owner)',
        'ruled_on', '2026-08-02',
        'ruling', 'never a real licensor; created by mistake',
        'migration', '20260802171000'
      )
    );
    if new.metadata is distinct from v_expected_metadata then
      raise exception '20260802171000 authorization refused: metadata differs from the exact owner ruling';
    end if;
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
    values
      (pg_backend_pid(), txid_current(), tg_relid, 'owner_ruling_fr_inactivation',
       '8c9a45b4-d465-5fd8-85c0-fad829ed07ae'::uuid,
       'dd2e2b959a5d05a4683656dc626e7625132e519eb5deeb8eb86f10c42340da02',
       'shared-db migration 20260802171000', array['status'], clock_timestamp() + interval '1 minute')
    returning * into v_auth;
  else
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
  end if;
  if v_auth.id is null then
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

  insert into plm.licensing_write_guard_audit
    (authorization_id, target_table, operation, write_kind, protected_columns, plan_id, plan_hash, actor)
  values (v_auth.id, tg_relid, tg_op, v_auth.write_kind, v_changed, v_auth.plan_id, v_auth.plan_hash, v_auth.actor);
  update plm.licensing_write_authorization
  set consumed_at = clock_timestamp()
  where id = v_auth.id;
  return new;
end;
$$;

revoke all on function app.enforce_licensing_write_authority() from public;
