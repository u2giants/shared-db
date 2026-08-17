begin;

do $$
declare
  v_fr_id uuid;
  v_reset_plan uuid := gen_random_uuid();
  v_special_plan constant uuid := '8c9a45b4-d465-5fd8-85c0-fad829ed07ae'::uuid;
  v_failed boolean;
begin
  select id into strict v_fr_id
  from core.licensor
  where code = 'FR' and name = 'FRIENDS TV';

  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'canonical_merge', v_reset_plan,
     repeat('1', 64), 'contract reset', array['status'], clock_timestamp() + interval '1 minute');
  update core.licensor
  set status = 'active', metadata = metadata - 'owner_ruling'
  where id = v_fr_id;

  perform set_config('app.shared_db_migration_version', 'wrong-version', true);
  v_failed := false;
  begin
    update core.licensor set status = 'inactive' where id = v_fr_id;
  exception when others then
    v_failed := position('no exact transaction-bound authorization' in sqlerrm) > 0;
  end;
  if not v_failed then raise exception 'wrong migration version was not refused'; end if;

  perform set_config('app.shared_db_migration_version', '20260802171000', true);
  v_failed := false;
  begin
    update core.licensor
    set status = 'inactive', metadata = metadata || '{"owner_ruling":{"migration":"wrong"}}'::jsonb
    where id = v_fr_id;
  exception when others then
    v_failed := position('metadata differs from the exact owner ruling' in sqlerrm) > 0;
  end;
  if not v_failed then raise exception 'wrong owner-ruling metadata was not refused'; end if;

  update core.licensor
  set status = 'inactive',
      metadata = metadata || jsonb_build_object(
        'owner_ruling', jsonb_build_object(
          'ruled_by', 'Albert Hazan (owner)',
          'ruled_on', '2026-08-02',
          'ruling', 'never a real licensor; created by mistake',
          'migration', '20260802171000'
        )
      )
  where id = v_fr_id;

  if not exists (
    select 1
    from plm.licensing_write_authorization
    where plan_id = v_special_plan
      and write_kind = 'owner_ruling_fr_inactivation'
      and consumed_at is not null
      and backend_pid = pg_backend_pid()
      and transaction_id = txid_current()
  ) then
    raise exception 'exact owner-ruling authorization was not created and consumed in one transaction';
  end if;
  if not exists (
    select 1
    from plm.licensing_write_guard_audit
    where plan_id = v_special_plan
      and write_kind = 'owner_ruling_fr_inactivation'
      and target_table = 'core.licensor'::regclass
      and operation = 'UPDATE'
      and protected_columns = array['status']::text[]
  ) then
    raise exception 'exact owner-ruling authorization left no immutable audit evidence';
  end if;

  v_failed := false;
  begin
    update core.licensor set status = 'active' where id = v_fr_id;
  exception when others then
    v_failed := position('no exact transaction-bound authorization' in sqlerrm) > 0;
  end;
  if not v_failed then raise exception 'one-use owner-ruling authorization was replayable'; end if;
end $$;

rollback;
