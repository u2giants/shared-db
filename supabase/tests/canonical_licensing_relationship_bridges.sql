-- Issue #2334 contract: the canonical licensing relationship foundation.
--
-- This file asserts BEHAVIOUR, not "the migration applied". Every claim #2334 makes is
-- exercised against real rows and rolled back:
--   * the live core.property_character_associations endpoint contract is untouched;
--   * the five missing canonical bridges and all eight support-edge tables exist;
--   * inferred and co-occurrence evidence can NEVER become a direct canonical edge;
--   * is_direct_source_relationship cannot be written, so evidence cannot lie about itself;
--   * deleting CURRENT support fails closed -- directly, and by cascade from a deleted
--     endpoint, which is how the three pre-existing ON DELETE CASCADE bridges are covered;
--   * superseded support does NOT block deletion.
begin;

do $contracts$
declare
  v_licensor    uuid;
  v_property    uuid;
  v_property2   uuid;
  v_character   uuid;
  v_style_guide uuid;
  v_franchise   uuid;
  v_asset       uuid;
  v_edge        uuid;
  v_raised      boolean;
  v_count       integer;
  t             text;
begin
  -- =========================================================================
  -- 1. Existence: the enum, the two guards, and all thirteen new tables.
  -- =========================================================================
  if not exists (select 1 from pg_type where typname = 'relationship_evidence_kind'
                 and typnamespace = 'core'::regnamespace) then
    raise exception 'core.relationship_evidence_kind is absent';
  end if;

  if array(select enumlabel::text from pg_enum
           where enumtypid = 'core.relationship_evidence_kind'::regtype
           order by enumsortorder)
     <> array['direct_source_assertion','inferred','co_occurrence'] then
    raise exception 'the three-way evidence vocabulary changed';
  end if;

  if to_regprocedure('core.refuse_delete_of_current_support_edge()') is null
     or to_regprocedure('core.require_direct_support_for_canonical_edge()') is null then
    raise exception 'a #2334 guard function is absent';
  end if;

  foreach t in array array[
    'core.property_style_guide', 'core.property_franchise',
    'dam.asset_property', 'dam.asset_style_guide', 'dam.asset_franchise',
    'core.property_character_source_edge', 'core.property_style_guide_source_edge',
    'core.property_franchise_source_edge', 'core.style_guide_character_source_edge',
    'dam.asset_property_source_edge', 'dam.asset_character_source_edge',
    'dam.asset_style_guide_source_edge', 'dam.asset_franchise_source_edge'
  ] loop
    if to_regclass(t) is null then
      raise exception '#2334 table % is absent', t;
    end if;
    -- Structure only: #2334 authorizes no relationship rows and no licensed evidence.
    execute format('select count(*) from %s', t) into v_count;
    if v_count <> 0 then
      raise exception '% was seeded with % row(s); #2334 authorizes none', t, v_count;
    end if;
  end loop;

  -- Every support edge carries both the supersession guard and the generated flag.
  foreach t in array array[
    'core.property_character_source_edge', 'core.property_style_guide_source_edge',
    'core.property_franchise_source_edge', 'core.style_guide_character_source_edge',
    'dam.asset_property_source_edge', 'dam.asset_character_source_edge',
    'dam.asset_style_guide_source_edge', 'dam.asset_franchise_source_edge'
  ] loop
    if not exists (
      select 1 from pg_trigger
      where tgrelid = t::regclass and not tgisinternal
        and tgname = 'refuse_delete_of_current_support'
    ) then
      raise exception '% has no fail-closed delete guard', t;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema = split_part(t, '.', 1) and table_name = split_part(t, '.', 2)
        and column_name = 'is_direct_source_relationship' and is_generated = 'ALWAYS'
    ) then
      raise exception '%.is_direct_source_relationship is not a generated column', t;
    end if;
  end loop;

  -- Every NEW canonical bridge refuses an unsupported edge and restricts endpoint delete.
  foreach t in array array[
    'core.property_style_guide', 'core.property_franchise',
    'dam.asset_property', 'dam.asset_style_guide', 'dam.asset_franchise'
  ] loop
    if not exists (
      select 1 from pg_trigger
      where tgrelid = t::regclass and not tgisinternal and tgname = 'require_direct_support'
    ) then
      raise exception '% does not require direct support', t;
    end if;
    if exists (
      select 1 from pg_constraint
      where conrelid = t::regclass and contype = 'f' and confdeltype <> 'r'
    ) then
      raise exception '% has an endpoint foreign key that is not ON DELETE RESTRICT', t;
    end if;
  end loop;

  -- =========================================================================
  -- 2. The live Property/Character endpoint contract is byte-for-byte preserved.
  -- =========================================================================
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'core' and table_name = 'property_character_associations'
      and column_name not in ('property_id','character_id','created_at','updated_at')
  ) then
    raise exception '#2334 added a column to the live property_character_associations contract';
  end if;

  if 2 <> (select count(*) from pg_constraint
           where conrelid = 'core.property_character_associations'::regclass
             and contype = 'f' and confdeltype = 'r') then
    raise exception 'property_character_associations lost its ON DELETE RESTRICT endpoints';
  end if;

  if (select count(*) from core.property_character_associations) <> 0 then
    raise exception 'property_character_associations is no longer empty';
  end if;

  if has_table_privilege('authenticated', 'core.property_character_associations', 'insert')
     or has_table_privilege('service_role', 'core.property_character_associations', 'insert') then
    raise exception 'property_character_associations gained an ungoverned write privilege';
  end if;

  -- No role may write a canonical licensing edge, on the new bridges either.
  foreach t in array array[
    'core.property_style_guide', 'core.property_franchise',
    'dam.asset_property', 'dam.asset_style_guide', 'dam.asset_franchise'
  ] loop
    if has_table_privilege('authenticated', t, 'insert')
       or has_table_privilege('service_role', t, 'insert') then
      raise exception '% grants an ungoverned canonical write', t;
    end if;
  end loop;

  -- =========================================================================
  -- 3. Fixtures. Invented rows, rolled back with the transaction.
  -- =========================================================================
  insert into core.licensor (name, code) values ('ZZ Fixture Licensor 2334', 'ZZ2334')
    returning id into v_licensor;
  insert into core.property (licensor_id, name, code)
    values (v_licensor, 'ZZ Fixture Property 2334', 'ZZP2334') returning id into v_property;
  insert into core.property (licensor_id, name, code)
    values (v_licensor, 'ZZ Fixture Property 2334 B', 'ZZP2334B') returning id into v_property2;
  insert into core.character (licensor_id, name)
    values (v_licensor, 'ZZ Fixture Character 2334') returning id into v_character;
  insert into core.style_guide (licensor_id, property_id, name)
    values (v_licensor, v_property, 'ZZ Fixture Style Guide 2334') returning id into v_style_guide;
  insert into core.franchise (licensor_id, name, source_system, source_id)
    values (v_licensor, 'ZZ Fixture Franchise 2334', 'manual', 'zz-2334')
    returning id into v_franchise;
  insert into dam.asset (title, source_system, source_id)
    values ('ZZ Fixture Asset 2334', 'zz_fixture_2334', 'zz-asset-2334') returning id into v_asset;

  -- =========================================================================
  -- 4. THE CENTRAL CLAIM: inferred and co-occurrence evidence never become canon.
  -- =========================================================================

  -- 4a. No support at all -> refused.
  v_raised := false;
  begin
    insert into core.property_style_guide (property_id, style_guide_id)
      values (v_property, v_style_guide);
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'a canonical edge was accepted with NO supporting evidence';
  end if;

  -- 4b. INFERRED support -> still refused.
  insert into core.property_style_guide_source_edge
    (property_id, style_guide_id, licensor_id, source_system, evidence_kind, confidence)
    values (v_property, v_style_guide, v_licensor, 'zz_fixture_2334', 'inferred', 0.9900);
  v_raised := false;
  begin
    insert into core.property_style_guide (property_id, style_guide_id)
      values (v_property, v_style_guide);
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'INFERRED evidence was promoted into a direct canonical edge';
  end if;

  -- 4c. CO-OCCURRENCE support, at any volume -> still refused.
  insert into core.property_style_guide_source_edge
    (property_id, style_guide_id, licensor_id, source_system, evidence_kind,
     observation_count, confidence)
    values (v_property, v_style_guide, v_licensor, 'zz_fixture_2334', 'co_occurrence',
            100000, 1.0000);
  v_raised := false;
  begin
    insert into core.property_style_guide (property_id, style_guide_id)
      values (v_property, v_style_guide);
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'CO-OCCURRENCE evidence was promoted into a direct canonical edge';
  end if;

  -- 4d. A DIRECT source assertion -> accepted.
  insert into core.property_style_guide_source_edge
    (property_id, style_guide_id, licensor_id, source_system, source_id, evidence_kind)
    values (v_property, v_style_guide, v_licensor, 'zz_fixture_2334', 'sg-1',
            'direct_source_assertion')
    returning id into v_edge;
  insert into core.property_style_guide (property_id, style_guide_id)
    values (v_property, v_style_guide);

  -- 4e. Direct support for a DIFFERENT pair does not sustain this one.
  v_raised := false;
  begin
    insert into core.property_style_guide (property_id, style_guide_id)
      values (v_property2, v_style_guide);
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'a canonical edge borrowed another pair''s direct support';
  end if;

  -- 4f. Evidence cannot lie about itself: the flag is generated, never supplied.
  v_raised := false;
  begin
    execute format(
      'insert into core.property_franchise_source_edge (property_id, franchise_id, licensor_id,'
      ' source_system, evidence_kind, is_direct_source_relationship)'
      ' values (%L, %L, %L, ''zz_fixture_2334'', ''co_occurrence'', true)',
      v_property, v_franchise, v_licensor);
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'co-occurrence evidence was allowed to relabel itself as direct';
  end if;

  if (select is_direct_source_relationship
      from core.property_style_guide_source_edge where id = v_edge) is not true then
    raise exception 'a direct source assertion did not generate is_direct_source_relationship';
  end if;

  -- 4g. A direct assertion is not a probability.
  v_raised := false;
  begin
    insert into core.property_franchise_source_edge
      (property_id, franchise_id, licensor_id, source_system, evidence_kind, confidence)
      values (v_property, v_franchise, v_licensor, 'zz_fixture_2334',
              'direct_source_assertion', 0.5000);
  exception when check_violation then v_raised := true;
  end;
  if not v_raised then
    raise exception 'a direct source assertion was allowed to carry a confidence score';
  end if;

  -- 4h. is_current and superseded_at may never disagree.
  v_raised := false;
  begin
    insert into core.property_franchise_source_edge
      (property_id, franchise_id, licensor_id, source_system, evidence_kind, superseded_at)
      values (v_property, v_franchise, v_licensor, 'zz_fixture_2334', 'inferred', now());
  exception when check_violation then v_raised := true;
  end;
  if not v_raised then
    raise exception 'a support edge was both current and superseded';
  end if;

  -- =========================================================================
  -- 5. Fail-closed deletion.
  -- =========================================================================

  -- 5a. Current support cannot be deleted directly.
  v_raised := false;
  begin
    delete from core.property_style_guide_source_edge where id = v_edge;
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'CURRENT support was deleted, silently discarding licensing evidence';
  end if;

  -- 5b. An endpoint cannot be deleted while a canonical edge stands (RESTRICT).
  v_raised := false;
  begin
    delete from core.style_guide where id = v_style_guide;
  exception when foreign_key_violation then v_raised := true;
  end;
  if not v_raised then
    raise exception 'an endpoint was deleted out from under a canonical relationship';
  end if;

  -- 5c. THE CASCADE CASE. dam.asset_character already existed before #2334 and its
  --     endpoints are ON DELETE CASCADE; #2334 must not alter that live table. Deleting
  --     the asset must nevertheless fail closed, because the cascade reaches current
  --     support and the guard aborts the whole transaction.
  insert into dam.asset_character (asset_id, character_id) values (v_asset, v_character);
  insert into dam.asset_character_source_edge
    (asset_id, character_id, licensor_id, source_system, source_id, evidence_kind)
    values (v_asset, v_character, v_licensor, 'zz_fixture_2334', 'ac-1',
            'direct_source_assertion');
  v_raised := false;
  begin
    delete from dam.asset where id = v_asset;
  exception when sqlstate 'P0001' then v_raised := true;
  end;
  if not v_raised then
    raise exception 'deleting an endpoint CASCADED through a pre-existing bridge and erased '
      'current licensing support instead of failing closed';
  end if;

  -- And the evidence really is still there afterwards.
  if not exists (
    select 1 from dam.asset_character_source_edge
    where asset_id = v_asset and character_id = v_character and is_current
  ) then
    raise exception 'current support did not survive the refused endpoint delete';
  end if;

  -- 5d. Superseded support does NOT block: only CURRENT support does.
  update core.property_style_guide_source_edge
     set is_current = false, superseded_at = now(), superseded_reason = 'fixture supersession'
   where id = v_edge;
  delete from core.property_style_guide_source_edge where id = v_edge;
  if exists (select 1 from core.property_style_guide_source_edge where id = v_edge) then
    raise exception 'superseded support could not be deleted';
  end if;

  raise notice 'issue #2334 canonical licensing relationship contracts: all assertions passed';
end
$contracts$;

rollback;
