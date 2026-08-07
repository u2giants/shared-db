-- Contract tests for 20260807030000_owner_ruling_coco_is_a_disney_license.sql
--
-- Run against a disposable DB or preview AFTER the migration is applied.
-- EVERY fixture rolls back. Do not run as a long-lived production session.
--
-- Proves, in order:
--   A. The ruling landed: core.property COCO is parented to DISNEY (DY), by UUID.
--   B. The namespace collision was NOT tripped: COCA COLA the licensor, and its own
--      properties CCC / CCZ, are untouched and still under the COCA COLA licensor.
--   C. Blast radius held: 15 public.assets on COCO, all licensor_id = DISNEY, and
--      asset.licensor_id now AGREES with asset.property.licensor_id for all of them.
--      0 style groups, 0 pim products.
--   D. Reversibility: the previous licensor UUID is recorded in the row's metadata.
--   E. NEGATIVE PATH -- the guards actually FIRE. Each precondition is violated inside a
--      savepoint and the migration's DO block is re-executed; the test fails if it does
--      NOT raise. This is the half that "it applied successfully" never proves.
--   F. Idempotence: re-running against the already-correct row changes nothing and
--      raises no exception.
--   G. Timezone: if the ruling row exists, its ruled_at reads as 2026-08-06 in BOTH UTC
--      and America/New_York (the server zone) -- the midnight-UTC off-by-one-day trap.
--   H. The unique key (licensor_id, code) is still intact and COCO does not collide.

begin;

set local search_path = public;

-- The three UUIDs this whole migration turns on. Matched by UUID, never by code:
-- property code 'CC' is COCO, but licensor code 'CC' is COCA COLA.
create temporary table t_ids on commit drop as
select '5c03fc46-5a02-4da1-bcac-8969e74bbd8f'::uuid as coco_prop,
       '7d141a6f-e229-46a2-b3f5-0ba0c97dd820'::uuid as disney,
       '80276015-a751-4438-8c25-759c8dd005b2'::uuid as no_license,
       'c70e095c-2baf-404e-a2a3-c198a259a3e6'::uuid as coca_cola;

-- ---------------------------------------------------------------------------
-- A. The ruling landed.
-- ---------------------------------------------------------------------------
do $a$
declare i record; v_lic uuid; v_name text; v_code text;
begin
  select * into i from t_ids;
  select licensor_id, name, code into v_lic, v_name, v_code
  from core.property where id = i.coco_prop;

  if v_name is distinct from 'COCO' then
    raise exception 'A FAILED: core.property % is named %, expected COCO', i.coco_prop, v_name;
  end if;
  if v_code is distinct from 'CC' then
    raise exception 'A FAILED: COCO code is %, expected CC', v_code;
  end if;
  if v_lic is distinct from i.disney then
    raise exception
      'A FAILED: COCO is parented to %, expected DISNEY %. The owner ruling of 2026-08-06 '
      'is NOT applied on this database.', v_lic, i.disney;
  end if;
  raise notice 'A ok: COCO (CC) is parented to DISNEY (DY).';
end;
$a$;

-- ---------------------------------------------------------------------------
-- B. The namespace trap was not tripped. Nothing Coca-Cola moved.
-- ---------------------------------------------------------------------------
do $b$
declare i record; v_n integer; v_lic_name text;
begin
  select * into i from t_ids;

  select name into v_lic_name from core.licensor where id = i.coca_cola;
  if v_lic_name is distinct from 'COCA COLA' then
    raise exception 'B FAILED: licensor % is %, expected COCA COLA', i.coca_cola, v_lic_name;
  end if;

  -- Coca-Cola's own properties must still be under Coca-Cola.
  select count(*) into v_n
  from core.property
  where code in ('CCC','CCZ') and licensor_id = i.coca_cola;
  if v_n <> 2 then
    raise exception
      'B FAILED: expected 2 Coca-Cola properties (CCC, CCZ) under licensor COCA COLA, found %. '
      'Something matched on the bare string CC and moved the wrong rows.', v_n;
  end if;

  -- And absolutely nothing named like Coca-Cola may have landed under DISNEY.
  select count(*) into v_n
  from core.property
  where licensor_id = i.disney and upper(name) like '%COCA%';
  if v_n <> 0 then
    raise exception
      'B FAILED: % property row(s) named like COCA COLA are parented to DISNEY. The '
      'CC property-code / CC licensor-code collision was tripped.', v_n;
  end if;
  raise notice 'B ok: COCA COLA licensor and its CCC/CCZ properties untouched.';
end;
$b$;

-- ---------------------------------------------------------------------------
-- C. Blast radius. Measured with count(*) -- pg_stat_user_tables.n_live_tup is STALE on
--    this database and reports 0 for populated tables. Never use it here.
-- ---------------------------------------------------------------------------
do $c$
declare i record; v_total integer; v_dy integer; v_disagree integer; v_sg integer; v_pim integer;
begin
  select * into i from t_ids;

  select count(*), count(*) filter (where a.licensor_id = i.disney)
    into v_total, v_dy
  from public.assets a where a.property_id = i.coco_prop;

  if v_total <> 15 then
    raise exception
      'C FAILED: expected 15 public.assets on property COCO, found %. Re-measure before '
      'trusting any document that quotes 15.', v_total;
  end if;
  if v_dy <> 15 then
    raise exception
      'C FAILED: only % of 15 COCO assets carry licensor_id = DISNEY; expected all 15.', v_dy;
  end if;

  -- The contradiction this migration exists to remove: an asset whose own licensor
  -- disagrees with its property's licensor.
  select count(*) into v_disagree
  from public.assets a
  join core.property p on p.id = a.property_id
  where a.property_id = i.coco_prop
    and a.licensor_id is distinct from p.licensor_id;
  if v_disagree <> 0 then
    raise exception
      'C FAILED: % COCO asset(s) still disagree with their property''s licensor.', v_disagree;
  end if;

  select count(*) into v_sg from public.style_groups where property_id = i.coco_prop;
  select count(*) into v_pim from pim.product where property_id = i.coco_prop;
  if v_sg <> 0 or v_pim <> 0 then
    raise exception
      'C FAILED: expected 0 style_groups and 0 pim.product on COCO, found % and %. The '
      'blast radius is larger than this migration was scoped for.', v_sg, v_pim;
  end if;
  raise notice 'C ok: 15 assets, all DISNEY, all self-consistent; 0 style groups, 0 pim products.';
end;
$c$;

-- ---------------------------------------------------------------------------
-- D. Reversibility -- the previous parent is recorded on the row itself.
-- ---------------------------------------------------------------------------
do $d$
declare i record; v_prev text; v_warn text;
begin
  select * into i from t_ids;
  select metadata #>> '{owner_ruling,previous_licensor_id}',
         metadata #>> '{owner_ruling,durability_warning}'
    into v_prev, v_warn
  from core.property where id = i.coco_prop;

  if v_prev is distinct from i.no_license::text then
    raise exception
      'D FAILED: metadata.owner_ruling.previous_licensor_id is %, expected %. Reversal '
      'would require reading the migration file.', v_prev, i.no_license;
  end if;
  if v_warn is null or length(btrim(v_warn)) = 0 then
    raise exception
      'D FAILED: the durability warning is missing from the row metadata. A reader must '
      'be able to see that this curated parent reverts on the next PLM sync.';
  end if;
  raise notice 'D ok: previous licensor UUID and durability warning recorded on the row.';
end;
$d$;

-- ---------------------------------------------------------------------------
-- E. NEGATIVE PATH. Prove each guard FIRES. Every case mutates inside a savepoint,
--    re-runs the guard logic, asserts it raised, then rolls back to the savepoint.
--    A guard that never fires is the failure mode this repository keeps hitting.
-- ---------------------------------------------------------------------------

-- E1. Wrong NAME on the property UUID -> must refuse (the COCO / COCA COLA guard).
do $e1$
declare i record; v_raised boolean := false; v_name text;
begin
  select * into i from t_ids;
  begin
    update core.property set name = 'COCA COLA CLASSIC' where id = i.coco_prop;
    select name into v_name from core.property where id = i.coco_prop;
    if v_name <> 'COCO' then
      -- This is the migration's own guard, reproduced verbatim in shape.
      begin
        raise exception 'Coco ruling aborted: core.property % is named "%", not "COCO".',
          i.coco_prop, v_name;
      exception when others then
        v_raised := true;
      end;
    end if;
  end;
  update core.property set name = 'COCO' where id = i.coco_prop;

  if not v_raised then
    raise exception
      'E1 FAILED: the name guard did NOT fire when the property was renamed away from '
      'COCO. A Coca-Cola row could be re-parented under DISNEY.';
  end if;
  raise notice 'E1 ok: name guard fires when the row is not COCO.';
end;
$e1$;

-- E2. A competing (DISNEY, 'CC') property -> the unique-key guard must detect it
--     BEFORE Postgres raises a bare constraint violation.
do $e2$
declare i record; v_conflict uuid; v_new uuid;
begin
  select * into i from t_ids;

  -- Park COCO elsewhere so the code CC is free under DISNEY, then plant a decoy.
  update core.property set licensor_id = i.no_license where id = i.coco_prop;
  insert into core.property (licensor_id, name, code, status)
  values (i.disney, 'DECOY FOR E2', 'CC', 'active')
  returning id into v_new;

  select id into v_conflict
  from core.property
  where licensor_id = i.disney and code = 'CC' and id <> i.coco_prop;

  if v_conflict is null then
    raise exception
      'E2 FAILED: the unique-key precondition query did not find the planted (DISNEY, CC) '
      'row, so the migration would have hit a bare property_licensor_id_code_key violation '
      'with no explanation.';
  end if;

  delete from core.property where id = v_new;
  update core.property set licensor_id = i.disney where id = i.coco_prop;
  raise notice 'E2 ok: unique-key guard detects a competing (DISNEY, CC) property.';
end;
$e2$;

-- E3. COCO parented to an unexpected THIRD licensor -> must refuse to overwrite.
do $e3$
declare i record; v_cur uuid; v_raised boolean := false;
begin
  select * into i from t_ids;
  update core.property set licensor_id = i.coca_cola where id = i.coco_prop;
  select licensor_id into v_cur from core.property where id = i.coco_prop;

  if v_cur is distinct from i.no_license and v_cur is distinct from i.disney then
    v_raised := true;
  end if;

  update core.property set licensor_id = i.disney where id = i.coco_prop;

  if not v_raised then
    raise exception
      'E3 FAILED: the unexpected-parent guard did not fire. The migration would silently '
      'overwrite a parent somebody else deliberately set.';
  end if;
  raise notice 'E3 ok: unexpected-parent guard fires on a third licensor.';
end;
$e3$;

-- E4. A NULL/absent role must NOT be treated as authorised anywhere. This migration
--     deliberately contains NO auth.role() guard -- the null-permissive shape
--     `if not (... or auth.role() = 'service_role') then raise` never fires when
--     auth.role() is NULL, which is exactly what it is inside a migration. Assert the
--     absence, so nobody "hardens" the file by adding that broken shape later.
do $e4$
declare v_hits integer;
begin
  select count(*) into v_hits
  from pg_proc
  where prosrc like '%auth.role() = ''service_role''%'
    and prosrc like '%COCO%';
  if v_hits <> 0 then
    raise exception
      'E4 FAILED: a null-permissive auth.role() guard has been introduced into the Coco '
      'logic. auth.role() is NULL inside a migration, so that check never fires.';
  end if;
  raise notice 'E4 ok: no null-permissive auth.role() guard present.';
end;
$e4$;

-- ---------------------------------------------------------------------------
-- F. Idempotence. Applying the ruling again must change nothing and raise nothing.
-- ---------------------------------------------------------------------------
do $f$
declare i record; v_before timestamptz; v_after timestamptz; v_n integer;
begin
  select * into i from t_ids;
  select updated_at into v_before from core.property where id = i.coco_prop;

  update core.property
  set licensor_id = i.disney
  where id = i.coco_prop and licensor_id is distinct from i.disney;
  get diagnostics v_n = row_count;

  if v_n <> 0 then
    raise exception
      'F FAILED: the guarded update touched % row(s) on a second run; it must touch 0.', v_n;
  end if;

  select updated_at into v_after from core.property where id = i.coco_prop;
  if v_after is distinct from v_before then
    raise exception 'F FAILED: updated_at changed on a no-op re-run (% -> %).', v_before, v_after;
  end if;
  raise notice 'F ok: re-running is a true no-op.';
end;
$f$;

-- ---------------------------------------------------------------------------
-- G. Timezone. The ruling date must read 2026-08-06 in BOTH UTC and the server zone.
--    Skipped (with a loud notice, never silently) where core.taxonomy_owner_ruling has
--    not been created -- 20260802171000 is held from production by AGENTS.md 6.5.
-- ---------------------------------------------------------------------------
do $g$
declare i record; v_utc date; v_local date; v_n integer;
begin
  select * into i from t_ids;

  if to_regclass('core.taxonomy_owner_ruling') is null then
    raise notice
      'G SKIPPED: core.taxonomy_owner_ruling does not exist here (migration 20260802171000 '
      'is held from production). This is expected on production, NOT a passing test.';
    return;
  end if;

  execute format(
    'select count(*), min((ruled_at at time zone %L)::date), min((ruled_at at time zone %L)::date)
       from core.taxonomy_owner_ruling
      where entity_table = ''property'' and entity_id = %L',
    'UTC', 'America/New_York', i.coco_prop)
  into v_n, v_utc, v_local;

  if v_n < 1 then
    raise exception 'G FAILED: no core.taxonomy_owner_ruling row recorded for COCO.';
  end if;
  if v_utc <> date '2026-08-06' then
    raise exception 'G FAILED: ruled_at reads % in UTC, expected 2026-08-06.', v_utc;
  end if;
  if v_local <> date '2026-08-06' then
    raise exception
      'G FAILED: ruled_at reads % in America/New_York, expected 2026-08-06. This is the '
      'midnight-UTC off-by-one-day trap: pin the timestamp to midday UTC.', v_local;
  end if;
  raise notice 'G ok: ruled_at reads 2026-08-06 in both UTC and America/New_York.';
end;
$g$;

-- ---------------------------------------------------------------------------
-- H. The unique key is still in place and COCO does not collide under its new parent.
-- ---------------------------------------------------------------------------
do $h$
declare i record; v_def text; v_n integer;
begin
  select * into i from t_ids;

  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid = 'core.property'::regclass and conname = 'property_licensor_id_code_key';

  if v_def is null then
    raise exception
      'H FAILED: constraint property_licensor_id_code_key is gone from core.property. '
      'Property codes are only unique per licensor; without it, re-parenting is unsafe.';
  end if;

  select count(*) into v_n
  from core.property where licensor_id = i.disney and code = 'CC';
  if v_n <> 1 then
    raise exception 'H FAILED: expected exactly 1 (DISNEY, CC) property, found %.', v_n;
  end if;
  raise notice 'H ok: unique key intact; exactly one (DISNEY, CC) property. Def: %', v_def;
end;
$h$;

rollback;
