-- #1339: the FR ERASURE contract.
--
-- What this file proves, and why each proof exists:
--   * A DELETE of a canonical Licensor is now COVERED by the licensing write
--     guard. Before migration 20260820183334 the guard was
--     `before insert or update` only, so an unauthorized delete of the most
--     important row in the licensing model succeeded silently. Every refusal
--     below simply does not happen without that migration.
--   * The new `owner_ruling_fr_removal` authorization is narrow: FR only, DELETE
--     only, whole-identity only, ordered behind BOTH recorded owner rulings, and
--     one-use.
--   * No OTHER write kind can authorize a delete, and the removal kind cannot
--     authorize anything else.
--   * The delete leaves immutable audit evidence naming the row that died.
--
-- No `exception when others` swallows anything: every handler re-raises unless
-- the message is the exact refusal being proven, so a typo in this file is red,
-- not green. Every proof increments a counter and the counter is asserted at the
-- end, so a block that silently never runs is red too.

begin;

-- The owner-ruling table. On preview it already exists. On the from-empty CI
-- database it does NOT: 20260818174350 aborts on its `select ... into strict`
-- for the FR/FK rows, so its `create table` rolls back with it. Creating it here
-- (inside this transaction, rolled back at the end) is test scaffolding, not a
-- schema change. Same reasoning as
-- fr_owner_ruling_transaction_bound_authorization_contracts.sql.
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
  v_expected_checks constant integer := 15;
  v_ruled_at constant timestamptz := timestamptz '2026-08-02 12:00:00+00';
  v_erased_at constant timestamptz := timestamptz '2026-08-20 12:00:00+00';
  v_ruler constant text := 'contract-test ruler';
  v_fr uuid;
  v_other uuid;
  v_plan uuid;
  v_audit_before bigint;
begin
  -- ------------------------------------------------------------------
  -- CLEAR THE BLANKET CI AUTHORIZATIONS FIRST, THEN PROVE THE BASELINE.
  --
  -- supabase/ci-bootstrap/020_test_fixture_seed.sql defines
  -- public.ci_authorize_licensing_contract_test(), and the contract-test runner
  -- calls it at the top of EVERY test session (issue #1262). It pre-issues 100
  -- unconsumed 'canonical_merge' authorizations for every column subset of
  -- core.licensor and core.property, in this very backend and transaction.
  --
  -- For this file that fixture is poison twice over. Most proofs below assert
  -- that an UNAUTHORIZED write is refused, and a blanket row silently
  -- authorizes exactly those writes -- so the whole file would pass while
  -- proving nothing at all. It also holds a `canonical_merge` row matching
  -- array['name','code','status'], which is precisely the authorization shape a
  -- DELETE now looks for, so "a non-removal write kind cannot delete" would be
  -- untestable.
  --
  -- So the outstanding fixture rows are removed inside this transaction (rolled
  -- back at the end like everything else here), and the empty baseline is then
  -- PROVEN rather than assumed. Consumed rows are left alone: they carry
  -- immutable audit evidence.
  -- ------------------------------------------------------------------
  delete from plm.licensing_write_authorization where consumed_at is null;
  if exists (select 1 from plm.licensing_write_authorization where consumed_at is null) then
    raise exception 'the blanket CI licensing authorizations could not be cleared';
  end if;
  begin
    insert into core.licensor (name, code, status) values ('erasure baseline probe', 'FRERB', 'active');
    raise exception 'the licensing guard was already open before this contract began';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 0. SHAPE: the guard trigger covers DELETE at all.
  --    pg_trigger.tgtype bits: 4 = INSERT, 8 = DELETE, 16 = UPDATE.
  -- ==================================================================
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'core.licensor'::regclass
      and t.tgname = 'licensor_licensing_write_guard'
      and not t.tgisinternal
      and t.tgtype & 8 > 0 and t.tgtype & 4 > 0 and t.tgtype & 16 > 0
  ) then
    raise exception 'the core.licensor licensing write guard does not cover insert, update AND delete';
  end if;
  v_checks := v_checks + 1;

  -- ------------------------------------------------------------------
  -- Fixture: FR "FRIENDS TV" and an unrelated licensor, both created through
  -- the ordinary guard, plus both recorded rulings for FR.
  -- ------------------------------------------------------------------
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'licensing_review_create', gen_random_uuid(), repeat('a',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  insert into core.licensor (name, code, status) values ('FRIENDS TV', 'FR', 'inactive') returning id into v_fr;

  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'licensing_review_create', gen_random_uuid(), repeat('a',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  insert into core.licensor (name, code, status) values ('NOT FRIENDS TV', 'FRX', 'active') returning id into v_other;

  -- The unrelated licensor gets BOTH rulings too, so "a different licensor is
  -- refused" can never pass merely because its ruling records are missing.
  insert into core.taxonomy_owner_ruling
    (entity_table, entity_id, entity_code, entity_name, ruling, ruled_by, ruled_at, ruling_evidence, action_taken)
  values
    ('licensor', v_other, 'FRX', 'NOT FRIENDS TV', 'unrelated', v_ruler, v_ruled_at, 'fixture', 'fixture'),
    ('licensor', v_other, 'FRX', 'NOT FRIENDS TV', 'unrelated', v_ruler, v_erased_at, 'fixture', 'fixture');

  -- ==================================================================
  -- 1. AN UNAUTHORIZED DELETE OF THE FR ROW IS REFUSED.
  --    This is the hole the migration exists to close. With no authorization
  --    outstanding at all, the delete must not happen.
  -- ==================================================================
  begin
    delete from core.licensor where id = v_fr;
    raise exception 'an unauthorized DELETE of the FR licensor succeeded';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  if not exists (select 1 from core.licensor where id = v_fr) then
    raise exception 'the refused DELETE removed the row anyway';
  end if;
  v_checks := v_checks + 1;

  -- ==================================================================
  -- 2. AN UNAUTHORIZED DELETE OF ANY OTHER LICENSOR IS REFUSED TOO.
  --    The coverage is on the table, not on one special row.
  -- ==================================================================
  begin
    delete from core.licensor where id = v_other;
    raise exception 'an unauthorized DELETE of an unrelated licensor succeeded';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 3. A DIFFERENT WRITE KIND CANNOT AUTHORIZE A DELETE, even with exactly the
  --    protected columns a delete looks for. This is the fixture-shaped attack.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'canonical_merge', gen_random_uuid(), repeat('c',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  begin
    delete from core.licensor where id = v_fr;
    raise exception 'a canonical_merge authorization deleted a licensor';
  exception when others then
    if position('may not authorize a DELETE' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization where consumed_at is null;

  -- ==================================================================
  -- 4. THE REMOVAL KIND CANNOT AUTHORIZE ANYTHING BUT A DELETE.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_removal', gen_random_uuid(), repeat('d',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  begin
    insert into core.licensor (name, code, status) values ('SMUGGLED', 'FRSMG', 'active');
    raise exception 'an owner_ruling_fr_removal authorization created a licensor';
  exception when others then
    if position('permits only a DELETE of core.licensor' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;
  delete from plm.licensing_write_authorization where consumed_at is null;

  -- ==================================================================
  -- 5. A DIFFERENT LICENSOR IS REFUSED, even with a valid removal
  --    authorization and its own two recorded rulings.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_removal', gen_random_uuid(), repeat('e',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  begin
    delete from core.licensor where id = v_other;
    raise exception 'the guard erased a licensor that is not FR';
  exception when others then
    if position('permits only licensor code FR' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 6. ORDERING: the delete is refused until BOTH rulings are recorded.
  --    The same authorization from proof 5 is still outstanding and unconsumed.
  -- ==================================================================
  begin
    delete from core.licensor where id = v_fr;
    raise exception 'FR was erased with no owner ruling recorded at all';
  exception when others then
    if position('the original 2026-08-02 owner ruling for this licensor is not recorded' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  insert into core.taxonomy_owner_ruling
    (entity_table, entity_id, entity_code, entity_name, ruling, ruled_by, ruled_at, ruling_evidence, action_taken)
  values
    ('licensor', v_fr, 'FR', 'FRIENDS TV', 'never a real licensor', v_ruler, v_ruled_at, 'fixture', 'fixture');

  begin
    delete from core.licensor where id = v_fr;
    raise exception 'FR was erased with only the 2026-08-02 ruling recorded';
  exception when others then
    if position('the 2026-08-20 erasure ruling for this licensor is not recorded' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  insert into core.taxonomy_owner_ruling
    (entity_table, entity_id, entity_code, entity_name, ruling, ruled_by, ruled_at, ruling_evidence, action_taken)
  values
    ('licensor', v_fr, 'FR', 'FRIENDS TV', 'erase entirely', v_ruler, v_erased_at, 'fixture',
     'core.licensor row ERASED by migration 20260820183334');

  -- ==================================================================
  -- 7. ONE USE MEANS ONE: a second outstanding removal authorization is
  --    refused, so a transaction cannot stockpile spares.
  -- ==================================================================
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_removal', gen_random_uuid(), repeat('f',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');
  begin
    delete from core.licensor where id = v_fr;
    raise exception 'the guard erased FR while two removal authorizations were outstanding';
  exception when others then
    if position('another unconsumed FR removal authorization exists' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  -- ==================================================================
  -- 8. THE AUTHORIZED ERASURE ITSELF, and the evidence it must leave.
  -- ==================================================================
  delete from plm.licensing_write_authorization where consumed_at is null;
  select coalesce(max(id), 0) into v_audit_before from plm.licensing_write_guard_audit;
  v_plan := gen_random_uuid();
  insert into plm.licensing_write_authorization
    (backend_pid, transaction_id, target_table, write_kind, plan_id, plan_hash, actor, protected_columns, expires_at)
  values
    (pg_backend_pid(), txid_current(), 'core.licensor', 'owner_ruling_fr_removal', v_plan, repeat('9',64),
     'fr-erasure-contract-test', array['name','code','status'], clock_timestamp() + interval '5 minutes');

  delete from core.licensor where id = v_fr;
  if exists (select 1 from core.licensor where id = v_fr) then
    raise exception 'the authorized erasure did not remove the row';
  end if;
  v_checks := v_checks + 1;

  if not exists (
    select 1 from plm.licensing_write_guard_audit
    where id > v_audit_before
      and plan_id = v_plan
      and write_kind = 'owner_ruling_fr_removal'
      and target_table = 'core.licensor'::regclass
      and operation = 'DELETE'
      and target_row_id = v_fr
      and ruling_migration = '20260820183334'
      and old_status = 'inactive'
      and new_status is null
      and protected_columns = array['name','code','status']::text[]
  ) then
    raise exception 'the erasure left no exact immutable audit evidence';
  end if;
  v_checks := v_checks + 1;

  if exists (
    select 1 from plm.licensing_write_authorization
    where plan_id = v_plan and consumed_at is null
  ) then
    raise exception 'the erasure authorization was not consumed';
  end if;
  v_checks := v_checks + 1;

  -- ==================================================================
  -- 9. THE STRICT GUARD IS RESTORED. Nothing is left outstanding and an
  --    ordinary unauthorized delete is refused exactly as before.
  -- ==================================================================
  if exists (
    select 1 from plm.licensing_write_authorization
    where write_kind = 'owner_ruling_fr_removal' and consumed_at is null
  ) then
    raise exception 'an unconsumed FR removal authorization was left outstanding';
  end if;
  begin
    delete from core.licensor where id = v_other;
    raise exception 'the strict licensing guard was not restored after the erasure';
  exception when others then
    if position('no exact transaction-bound authorization' in sqlerrm) = 0 then raise; end if;
    v_checks := v_checks + 1;
  end;

  if v_checks <> v_expected_checks then
    raise exception 'FR erasure contract ran % of % proofs -- a block was skipped', v_checks, v_expected_checks;
  end if;
end $$;

rollback;
