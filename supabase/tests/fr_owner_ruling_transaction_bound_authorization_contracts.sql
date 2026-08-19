-- #1140: the FR owner-ruling authorization must be narrow, one-use, ordered,
-- transaction-bound, and must leave immutable evidence.
--
-- EVERY assertion below fails if migration 20260819151527 is absent: before it,
-- 'owner_ruling_fr_inactivation' is the widest authorization in the system and
-- each of these refusals simply does not happen.
--
-- No `exception when others` swallows anything. Every handler re-raises unless
-- the message is the exact refusal being proven, so a typo in this file is red,
-- not green. Every proof increments a counter and the counter is asserted at the
-- end, so a block that silently never runs is red too. There is not one
-- `raise warning` in this file, by design.

begin;

-- The test needs the owner-ruling table. On preview it already exists. On the
-- from-empty CI database it does NOT: both 20260802171000 and 20260818174350
-- abort on their `select ... into strict` for the FR/FK rows, so their
-- `create table` rolls back with them. Creating it here (inside this
-- transaction, rolled back at the end) is test scaffolding, not a schema change.
create table if not exists core.taxonomy_owner_ruling (
  id uuid primary key default gen_random_uuid(),
  entity_schema text not null default 'core',
  entity_table text not null,
  entity_id uuid,
  entity_code text,
  entity_name text,
  ruling text not null,
  ruled_by text not null,
  ruled_at timestamptz not null,
  ruling_evidence text not null,
  action_taken text not null,
  open_questions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
declare
  v_checks integer := 0;
  v_expected_checks constant integer := 31;
  v_case record;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_ruler constant text := 'contract-test ruler';
  v_fr uuid;
  v_auth uuid;
  v_delta jsonb;
  v_audit_before bigint;
  v_metadata_before jsonb;
  v_status_before text;

  -- Inserts one valid FR owner-ruling authorization and returns its id.
  -- Declared as a local helper would need a function; instead each block below
  -- inserts explicitly, which also keeps every binding visible at the point of
  -- the assertion it is meant to falsify.
begin
  v_delta := jsonb_build_object('owner_ruling', jsonb_build_object(
    'ruled_by', v_ruler,
    'ruled_on', '2026-08-02',
    'ruling', 'never a real licensor; created by mistake',
    'migration', '20260802171000'
  ));

  -- ------------------------------------------------------------------
  -- Fixture: an FR "FRIENDS TV" licensor, created through the ordinary
  -- guard, plus the recorded 2026-08-02 owner ruling about it.
  -- ------------------------------------------------------------------
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'licensing_review_create', gen_random_uuid(), repeat('a',64),
     'fr-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  insert into core.licensor (name, code, status) values ('FRIENDS TV', 'FR', 'active') returning id into v_fr;

  insert into core.taxonomy_owner_ruling
    (entity_table, entity_id, entity_code, entity_name, ruling, ruled_by, ruled_at, ruling_evidence, action_taken)
  values
    ('licensor', v_fr, 'FR', 'FRIENDS TV', 'never a real licensor', v_ruler, v_ruled_at,
     'contract test fixture', 'contract test fixture');

  -- ==================================================================
  -- 1. The table constraint refuses a malformed FR authorization.
  -- ==================================================================
  begin
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
    values
      (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
       'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes');
    raise exception 'an FR owner-ruling authorization with no bindings was accepted';
  exception when check_violation then
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 2. The binding columns are refused on any other write_kind.
  -- ==================================================================
  begin
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
       ruling_migration, target_row_id, target_row_code, target_row_name,
       expected_current_status, expected_new_status, expected_metadata_delta)
    values
      (pg_backend_pid(), txid_current(), 'core.licensor', 'canonical_merge', gen_random_uuid(), repeat('b',64),
       'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
       '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta);
    raise exception 'owner-ruling bindings were accepted on a non-owner-ruling authorization';
  exception when check_violation then
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 3. A different target status is refused by the constraint.
  -- ==================================================================
  begin
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
       ruling_migration, target_row_id, target_row_code, target_row_name,
       expected_current_status, expected_new_status, expected_metadata_delta)
    values
      (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
       'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
       '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'archived', v_delta);
    raise exception 'an FR owner-ruling authorization targeting archived was accepted';
  exception when check_violation then
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 4. A different licensor row is refused at write time.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', gen_random_uuid(), 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta)
  returning id into v_auth;
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || v_delta
     where id = v_fr;
    raise exception 'the guard accepted a write to a licensor the authorization was not bound to';
  exception when others then
    if position('bound to a different licensor row' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization where id = v_auth;

  -- ==================================================================
  -- 5. A different session (backend pid) is refused.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid() + 1, txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta)
  returning id into v_auth;
  begin
    update core.licensor set status = 'inactive' where id = v_fr;
    raise exception 'the guard accepted an authorization created by another session';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization where id = v_auth;

  -- ==================================================================
  -- 6. A different transaction is refused.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current() + 1, 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta)
  returning id into v_auth;
  begin
    update core.licensor set status = 'inactive' where id = v_fr;
    raise exception 'the guard accepted an authorization created in another transaction';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization where id = v_auth;

  -- ==================================================================
  -- 6b. Every named metadata-shape refusal, one falsified condition at a
  --     time. Each case supplies an authorization whose expected delta is
  --     wrong in exactly one way, and an UPDATE that applies that same
  --     delta -- so the metadata EQUALITY check passes and the specific
  --     condition under test is the one that fires. Without 20260819151527
  --     every one of these writes succeeds.
  -- ==================================================================
  for v_case in
    select *
    from (values
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', v_ruler, 'ruled_on', '2026-08-02',
         'ruling', 'never a real licensor; created by mistake',
         'migration', '20260818174350')),
       'names a different migration than the authorization'),
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', 'someone who did not rule', 'ruled_on', '2026-08-02',
         'ruling', 'never a real licensor; created by mistake',
         'migration', '20260802171000')),
       'names a different ruler than the recorded owner ruling'),
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', v_ruler, 'ruled_on', '2026-08-02',
         'ruling', 'never a real licensor; created by mistake',
         'migration', '20260802171000'), 'extra', 'smuggled'),
       'must carry exactly the owner_ruling key'),
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', v_ruler, 'ruled_on', '2026-08-02',
         'ruling', 'some other ruling entirely',
         'migration', '20260802171000')),
       'must state the exact historical ruling text'),
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', v_ruler, 'ruled_on', '2026-08-03',
         'ruling', 'never a real licensor; created by mistake',
         'migration', '20260802171000')),
       'must state the 2026-08-02 ruling date'),
      (jsonb_build_object('owner_ruling', jsonb_build_object(
         'ruled_by', v_ruler, 'ruled_on', '2026-08-02',
         'ruling', 'never a real licensor; created by mistake',
         'migration', '20260802171000', 'bogus', 1)),
       'has the wrong key set'),
      (jsonb_build_object('owner_ruling', 5),
       'owner_ruling must be an object'),
      ('"not an object at all"'::jsonb,
       'carries no expected metadata delta')
    ) as t(delta, msg)
  loop
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
       ruling_migration, target_row_id, target_row_code, target_row_name,
       expected_current_status, expected_new_status, expected_metadata_delta)
    values
      (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('d',64),
       'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
       '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_case.delta);
    begin
      update core.licensor
         set status = 'inactive',
             metadata = case
                          when jsonb_typeof(v_case.delta) = 'object'
                            then coalesce(metadata,'{}'::jsonb) || v_case.delta
                          else coalesce(metadata,'{}'::jsonb)
                        end
       where id = v_fr;
      raise exception 'the guard accepted a malformed owner-ruling delta: %', v_case.delta;
    exception when others then
      if position(v_case.msg in sqlerrm) = 0 then raise; end if;
      v_checks := v_checks + 1;
    end;
    delete from plm.licensing_write_authorization
     where write_kind = 'owner_ruling_fr_inactivation' and consumed_at is null;
  end loop;

  -- ==================================================================
  -- 7. A different column set is refused (name changed alongside status).
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('b',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta)
  returning id into v_auth;
  begin
    update core.licensor set status = 'inactive', name = 'FRIENDS TV RENAMED' where id = v_fr;
    raise exception 'the guard accepted a name change alongside the authorized status change';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 8. A different target value is refused at write time.
  -- ==================================================================
  begin
    update core.licensor
       set status = 'archived',
           metadata = coalesce(metadata,'{}'::jsonb) || v_delta
     where id = v_fr;
    raise exception 'the guard accepted a status other than inactive';
  exception when others then
    if position('permits only the target status inactive' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 9. A metadata change outside the historical statement is refused.
  -- ==================================================================
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('smuggled', true)
     where id = v_fr;
    raise exception 'the guard accepted an unauthorized metadata change';
  exception when others then
    if position('resulting metadata is not exactly' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 10. A delta naming a different migration than the authorization is refused.
  -- ==================================================================
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('owner_ruling', jsonb_build_object(
             'ruled_by', v_ruler, 'ruled_on', '2026-08-02',
             'ruling', 'never a real licensor; created by mistake',
             'migration', '20260818174350'))
     where id = v_fr;
    raise exception 'the guard accepted a metadata delta naming another migration';
  exception when others then
    if position('resulting metadata is not exactly' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 11. Stockpiling a second unconsumed FR authorization is refused.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('c',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta);
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || v_delta
     where id = v_fr;
    raise exception 'the guard accepted a write with a spare FR authorization outstanding';
  exception when others then
    if position('exactly one may be outstanding' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization
   where write_kind = 'owner_ruling_fr_inactivation' and id <> v_auth;

  -- ==================================================================
  -- 12. Ordering: without the recorded ruling, the write is refused.
  --     This is what makes a standalone status flip impossible.
  -- ==================================================================
  delete from core.taxonomy_owner_ruling where entity_id = v_fr;
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || v_delta
     where id = v_fr;
    raise exception 'the guard applied the ruling before the ruling was recorded';
  exception when others then
    if position('owner ruling for this licensor is not recorded' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  insert into core.taxonomy_owner_ruling
    (entity_table, entity_id, entity_code, entity_name, ruling, ruled_by, ruled_at, ruling_evidence, action_taken)
  values
    ('licensor', v_fr, 'FR', 'FRIENDS TV', 'never a real licensor', v_ruler, v_ruled_at,
     'contract test fixture', 'contract test fixture');

  -- ==================================================================
  -- 13. A delta naming a different ruler than the recorded ruling is refused.
  -- ==================================================================
  begin
    update core.licensor
       set status = 'inactive',
           metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('owner_ruling', jsonb_build_object(
             'ruled_by', 'someone else', 'ruled_on', '2026-08-02',
             'ruling', 'never a real licensor; created by mistake',
             'migration', '20260802171000'))
     where id = v_fr;
    raise exception 'the guard accepted a delta naming a different ruler';
  exception when others then
    if position('resulting metadata is not exactly' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 13b. THE FUNCTION DOES NOT LEAN ON THE CONSTRAINT.
  --      The binding CHECK is `not valid`, so it must not be the only thing
  --      standing between a malformed authorization and a production write.
  --      Here the constraint is DROPPED (inside this rolled-back
  --      transaction) and every binding is falsified again at the
  --      authorization level. The guard FUNCTION must refuse each one on its
  --      own. Without 20260819151527 every one of these writes succeeds.
  -- ==================================================================
  delete from plm.licensing_write_authorization where id = v_auth;
  execute 'alter table plm.licensing_write_authorization drop constraint licensing_write_authorization_owner_ruling_binding';

  -- (a) the authorization may not license an INSERT
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('e',64),
     'fr-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta);
  begin
    insert into core.licensor (name, code, status) values ('FRIENDS TV', 'FR2', 'active');
    raise exception 'an owner-ruling authorization created a new licensor row';
  exception when others then
    if position('permits only an UPDATE of core.licensor' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization
   where write_kind = 'owner_ruling_fr_inactivation' and consumed_at is null;

  -- (b) the authorization may not license any column but status
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('e',64),
     'fr-contract-test', array['name','status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta);
  begin
    update core.licensor set status = 'inactive', name = 'FRIENDS TV RENAMED' where id = v_fr;
    raise exception 'an owner-ruling authorization licensed a column other than status';
  exception when others then
    if position('permits only the status column' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization
   where write_kind = 'owner_ruling_fr_inactivation' and consumed_at is null;

  -- (c) an unknown ruling migration, (d) a wrong code, (e) a wrong name,
  --     (f) a wrong pre-write status -- each falsified on its own.
  for v_case in
    select *
    from (values
      ('19990101000000', 'FR',  'FRIENDS TV',       'active',
       'names no known ruling migration'),
      ('20260802171000', 'FR2', 'FRIENDS TV',       'active',
       'permits only licensor code FR'),
      ('20260802171000', 'FR',  'FRIENDS TV WRONG', 'active',
       'permits only licensor name FRIENDS TV'),
      ('20260802171000', 'FR',  'FRIENDS TV',       'inactive',
       'expects the row to be active before the write')
    ) as t(ruling_migration, code, nm, current_status, msg)
  loop
    insert into plm.licensing_write_authorization
      (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
       ruling_migration, target_row_id, target_row_code, target_row_name,
       expected_current_status, expected_new_status, expected_metadata_delta)
    values
      (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('e',64),
       'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
       v_case.ruling_migration, v_fr, v_case.code, v_case.nm, v_case.current_status, 'inactive', v_delta);
    begin
      update core.licensor
         set status = 'inactive',
             metadata = coalesce(metadata,'{}'::jsonb) || v_delta
       where id = v_fr;
      raise exception 'the guard accepted an authorization bound to the wrong thing: % % % %',
        v_case.ruling_migration, v_case.code, v_case.nm, v_case.current_status;
    exception when others then
      if position(v_case.msg in sqlerrm) = 0 then raise; end if;
      v_checks := v_checks + 1;
    end;
    delete from plm.licensing_write_authorization
     where write_kind = 'owner_ruling_fr_inactivation' and consumed_at is null;
  end loop;

  -- Put the constraint back exactly as the migration defines it, so the
  -- remaining sections run against the real configuration.
  execute 'alter table plm.licensing_write_authorization add constraint licensing_write_authorization_owner_ruling_binding check ('
       || 'case when write_kind = ''owner_ruling_fr_inactivation'' then '
       || 'target_table = ''core.licensor''::regclass and protected_columns = array[''status'']::text[] '
       || 'and ruling_migration in (''20260802171000'', ''20260818174350'') and target_row_id is not null '
       || 'and target_row_code = ''FR'' and target_row_name = ''FRIENDS TV'' '
       || 'and expected_current_status = ''active'' and expected_new_status = ''inactive'' '
       || 'and expected_metadata_delta is not null else ruling_migration is null and target_row_id is null '
       || 'and target_row_code is null and target_row_name is null and expected_current_status is null '
       || 'and expected_new_status is null and expected_metadata_delta is null end) not valid';

  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at,
     ruling_migration, target_row_id, target_row_code, target_row_name,
     expected_current_status, expected_new_status, expected_metadata_delta)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_inactivation', gen_random_uuid(), repeat('f',64),
     'fr-contract-test', array['status'], clock_timestamp() + interval '5 minutes',
     '20260802171000', v_fr, 'FR', 'FRIENDS TV', 'active', 'inactive', v_delta)
  returning id into v_auth;

  -- ==================================================================
  -- 14. ROLLBACK BEHAVIOUR: every refusal above left nothing behind.
  --     The row is untouched, the authorization is unconsumed, and no
  --     audit row was written for it.
  -- ==================================================================
  select status::text, coalesce(metadata,'{}'::jsonb) into strict v_status_before, v_metadata_before
  from core.licensor where id = v_fr;
  if v_status_before <> 'active' or v_metadata_before ? 'owner_ruling' or v_metadata_before ? 'smuggled' then
    raise exception 'a refused FR write left a partial change behind: status %, metadata %', v_status_before, v_metadata_before;
  end if;
  if exists (select 1 from plm.licensing_write_authorization where id = v_auth and consumed_at is not null) then
    raise exception 'a refused FR write consumed its authorization';
  end if;
  if exists (select 1 from plm.licensing_write_guard_audit where authorization_id = v_auth) then
    raise exception 'a refused FR write wrote guard audit evidence';
  end if;
  v_checks := v_checks + 1;

  -- ==================================================================
  -- 15. THE AUTHORIZED WRITE: the exact historical statement succeeds,
  --     consumes its authorization, and leaves audit evidence.
  -- ==================================================================
  select count(*) into v_audit_before from plm.licensing_write_guard_audit;
  update core.licensor
     set status = 'inactive',
         metadata = coalesce(metadata,'{}'::jsonb) || v_delta
   where id = v_fr;

  if (select status::text from core.licensor where id = v_fr) <> 'inactive' then
    raise exception 'the authorized FR owner ruling did not apply';
  end if;
  if not exists (
    select 1 from plm.licensing_write_authorization
    where id = v_auth and consumed_at is not null
  ) then
    raise exception 'the authorized FR owner ruling did not consume its authorization';
  end if;
  if not exists (
    select 1 from plm.licensing_write_guard_audit
    where authorization_id = v_auth
      and target_table = 'core.licensor'::regclass
      and operation = 'UPDATE'
      and write_kind = 'owner_ruling_fr_inactivation'
      and protected_columns = array['status']::text[]
      and target_row_id = v_fr
      and ruling_migration = '20260802171000'
      and old_status = 'active'
      and new_status = 'inactive'
  ) then
    raise exception 'the authorized FR owner ruling left no exact immutable audit evidence';
  end if;
  if (select count(*) from plm.licensing_write_guard_audit) <> v_audit_before + 1 then
    raise exception 'the authorized FR owner ruling wrote the wrong number of audit rows';
  end if;
  v_checks := v_checks + 1;

  -- ==================================================================
  -- 16. ONE USE: replaying the same statement in the same transaction is
  --     refused, because the authorization is consumed.
  -- ==================================================================
  begin
    update core.licensor
       set status = 'active'
     where id = v_fr;
    raise exception 'the consumed FR authorization was reusable';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 17. CLEANUP PROOF / STRICT GUARD RESTORED: no FR authorization is
  --     left outstanding, and an ordinary unauthorized licensing write is
  --     refused exactly as it was before.
  -- ==================================================================
  if exists (
    select 1 from plm.licensing_write_authorization
    where write_kind = 'owner_ruling_fr_inactivation' and consumed_at is null
  ) then
    raise exception 'an unconsumed FR owner-ruling authorization was left outstanding';
  end if;
  begin
    insert into core.licensor (name, code, status) values ('post-ruling', 'FRPOST', 'active');
    raise exception 'the strict licensing guard was not restored after the FR owner ruling';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  if v_checks <> v_expected_checks then
    raise exception 'FR owner-ruling contract ran % of % proofs -- a block was skipped', v_checks, v_expected_checks;
  end if;
end $$;

rollback;
