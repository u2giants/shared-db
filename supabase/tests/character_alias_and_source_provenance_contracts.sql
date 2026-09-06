-- Issue #2355 (successor to #1090) behavioural contracts.
--
-- These assertions do NOT check that a migration applied. They check that the database
-- REFUSES the specific mistakes the issue exists to prevent:
--
--   * an alias that crosses a licensor boundary,
--   * two different characters answering to one normalized name inside one licensor,
--   * provenance recorded with no source, or pointing at a row that does not exist,
--   * and above all: two licensors reusing the same small integer source id being
--     merged into one provenance row. Disney and Sega both number from small integers.
--     A bare source id is not an identity, and a royalty decision made on one is wrong.
--
-- The whole file runs inside the harness's begin/rollback wrapper, so every row it
-- creates disappears.

do $contracts$
declare
  v_suffix   text := to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || substr(md5(random()::text), 1, 6);
  v_lic_a    uuid;
  v_lic_b    uuid;
  v_char_a   uuid;
  v_char_a2  uuid;
  v_char_b   uuid;
  v_ref      uuid;
  v_legacy_ref uuid;
  v_txt      text;
  v_uuid     uuid;
  v_bool     boolean;
  v_count    integer;
  v_legacy   integer;
  v_raised   boolean;
begin
  -- =========================================================================
  -- A. The objects exist. to_regclass and the catalog, never the ledger row.
  -- =========================================================================
  if to_regclass('core.character_alias') is null then
    raise exception '#2355: core.character_alias is absent';
  end if;

  foreach v_txt in array array['source_licensor_id','first_seen_at','last_seen_at','missing_since','is_current'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'core' and table_name = 'taxonomy_source_ref' and column_name = v_txt
    ) then
      raise exception '#2355: core.taxonomy_source_ref.% is absent', v_txt;
    end if;
  end loop;

  -- is_current must be DERIVED. A writable duplicate of missing_since would drift.
  if (select is_generated from information_schema.columns
      where table_schema='core' and table_name='taxonomy_source_ref' and column_name='is_current') <> 'ALWAYS' then
    raise exception '#2355: taxonomy_source_ref.is_current must be a generated column';
  end if;
  if (select is_generated from information_schema.columns
      where table_schema='core' and table_name='character_alias' and column_name='normalized_alias') <> 'ALWAYS' then
    raise exception '#2355: character_alias.normalized_alias must be a generated column';
  end if;

  -- The pre-existing global unique key MUST survive: a dozen already-applied importer
  -- functions use it as their `on conflict` target. Removing it would break them all.
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'core.taxonomy_source_ref'::regclass
      and c.contype = 'u'
      and (
        select array_agg(a.attname::text order by a.attname)
        from unnest(c.conkey) k
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k
      ) = array['source_id','source_system','source_table']
  ) then
    raise exception
      '#2355: the pre-existing UNIQUE (source_system, source_table, source_id) was removed -- every importer on-conflict target is now broken';
  end if;

  -- The guards themselves.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'core.taxonomy_source_ref'::regclass
      and tgname = 'a_taxonomy_source_ref_identity_guard' and not tgisinternal
  ) then
    raise exception '#2355: the taxonomy_source_ref identity guard trigger is absent';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'core.character_alias'::regclass
      and tgname = 'character_alias_licensor_guard' and not tgisinternal
  ) then
    raise exception '#2355: the character_alias licensor guard trigger is absent';
  end if;

  -- The ColdLion circuit breaker must NOT have been displaced by the new guard.
  foreach v_txt in array array['coldlion_source_ref_breaker_guard','coldlion_source_ref_delete_breaker_guard'] loop
    if not exists (
      select 1 from pg_trigger
      where tgrelid = 'core.taxonomy_source_ref'::regclass and tgname = v_txt and not tgisinternal
    ) then
      raise exception '#2355: pre-existing ColdLion breaker trigger % was lost', v_txt;
    end if;
  end loop;

  -- Licensor-scoped alias uniqueness, and licensor-scoped alias source key.
  if not exists (
    select 1 from pg_indexes
    where schemaname='core' and tablename='character_alias' and indexname='character_alias_licensor_norm_key'
  ) then
    raise exception '#2355: character_alias_licensor_norm_key is absent';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname='core' and tablename='character_alias' and indexname='character_alias_licensor_source_key'
  ) then
    raise exception '#2355: character_alias_licensor_source_key is absent';
  end if;

  -- RLS on, and browser roles read-only.
  if not (select relrowsecurity from pg_class where oid = 'core.character_alias'::regclass) then
    raise exception '#2355: RLS is not enabled on core.character_alias';
  end if;
  if has_table_privilege('authenticated', 'core.character_alias', 'INSERT')
     or has_table_privilege('authenticated', 'core.character_alias', 'UPDATE')
     or has_table_privilege('authenticated', 'core.character_alias', 'DELETE') then
    raise exception '#2355: browser role `authenticated` can write core.character_alias';
  end if;
  if not has_table_privilege('authenticated', 'core.character_alias', 'SELECT') then
    raise exception '#2355: `authenticated` cannot read core.character_alias';
  end if;
  if has_table_privilege('anon', 'core.character_alias', 'SELECT') then
    raise exception '#2355: `anon` can read core.character_alias';
  end if;

  -- =========================================================================
  -- B. Fixture: TWO licensors, one character each. The whole point.
  -- =========================================================================
  select count(*) into v_legacy from core.taxonomy_source_ref;

  if to_regprocedure('public.ci_authorize_licensing_contract_test()') is not null then
    perform public.ci_authorize_licensing_contract_test();
  end if;

  insert into core.licensor (name, code, status)
  values ('ZZ #2355 Licensor A ' || v_suffix, 'Z55A-' || substr(v_suffix, 12), 'active')
  returning id into v_lic_a;
  insert into core.licensor (name, code, status)
  values ('ZZ #2355 Licensor B ' || v_suffix, 'Z55B-' || substr(v_suffix, 12), 'active')
  returning id into v_lic_b;

  insert into core.character (licensor_id, name, code, status)
  values (v_lic_a, 'ZZ Blue Runner ' || v_suffix, 'Z55CA-' || substr(v_suffix, 12), 'active')
  returning id into v_char_a;
  insert into core.character (licensor_id, name, code, status)
  values (v_lic_b, 'ZZ Blue Runner ' || v_suffix, 'Z55CB-' || substr(v_suffix, 12), 'active')
  returning id into v_char_b;

  -- A SECOND character under licensor A, so a same-licensor repoint can be told apart
  -- from a cross-licensor one.
  insert into core.character (licensor_id, name, code, status)
  values (v_lic_a, 'ZZ Blue Runner Two ' || v_suffix, 'Z55CA2-' || substr(v_suffix, 12), 'active')
  returning id into v_char_a2;

  -- =========================================================================
  -- C. core.character_alias behaviour
  -- =========================================================================

  -- C1. A normal alias lands and normalizes.
  insert into core.character_alias (character_id, licensor_id, alias, source_system, source_id)
  values (v_char_a, v_lic_a, 'Sonic The  Hedgehog!', 'wb_starlabs', '5');
  select normalized_alias into v_txt from core.character_alias
   where character_id = v_char_a and alias = 'Sonic The  Hedgehog!';
  if v_txt is null or length(btrim(v_txt)) = 0 then
    raise exception '#2355: normalized_alias was not generated';
  end if;
  if v_txt <> core.normalize_popsg_property_observation('Sonic The  Hedgehog!') then
    raise exception '#2355: character_alias uses a different normalizer than the frozen one';
  end if;

  -- C2. Within ONE licensor, a normalized name may not resolve to two characters.
  --     Different spelling, same normalization, same licensor -> refused.
  insert into core.character (licensor_id, name, code, status)
  values (v_lic_a, 'ZZ Impostor ' || v_suffix, 'Z55CI-' || substr(v_suffix, 12), 'active')
  returning id into v_uuid;
  v_raised := false;
  begin
    insert into core.character_alias (character_id, licensor_id, alias, source_system)
    values (v_uuid, v_lic_a, 'sonic the hedgehog!', 'nbcu');
  exception when unique_violation then
    v_raised := true;
  end;
  if not v_raised then
    raise exception
      '#2355: one normalized name resolved to TWO characters inside one licensor -- that is the name coincidence this table exists to refuse';
  end if;

  -- C3. The SAME name under a DIFFERENT licensor is legitimate and must be allowed.
  insert into core.character_alias (character_id, licensor_id, alias, source_system, source_id)
  values (v_char_b, v_lic_b, 'Sonic The  Hedgehog!', 'disney_opa', '5');
  if (select count(*) from core.character_alias
       where normalized_alias = core.normalize_popsg_property_observation('Sonic The  Hedgehog!')) <> 2 then
    raise exception '#2355: the same observed name under two licensors must be two distinct aliases';
  end if;

  -- C4. Same source_system + source_id ('5') under two licensors is fine. It would NOT
  --     be fine if the alias source key were global -- which is the whole lesson.
  --     (Proven implicitly by C3 succeeding with source_id '5' after C1 used '5'.)
  --     A repeat of '5' inside ONE licensor is refused.
  v_raised := false;
  begin
    insert into core.character_alias (character_id, licensor_id, alias, source_system, source_id)
    values (v_uuid, v_lic_a, 'Blue Runner Prime ' || v_suffix, 'wb_starlabs', '5');
  exception when unique_violation then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: one licensor accepted the same source_system/source_id twice';
  end if;

  -- C5. An alias may never cross a licensor boundary.
  v_raised := false;
  begin
    insert into core.character_alias (character_id, licensor_id, alias, source_system)
    values (v_char_a, v_lic_b, 'Cross Licensor ' || v_suffix, 'manual');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception
      '#2355: an alias was attached to licensor B while its character belongs to licensor A';
  end if;

  -- C6. Re-parenting an existing alias onto another licensor is refused too.
  v_raised := false;
  begin
    update core.character_alias set licensor_id = v_lic_b where character_id = v_char_a;
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: an existing alias was re-licensed by UPDATE';
  end if;

  -- C7. An alias with no source is a name with a row id. Refused.
  v_raised := false;
  begin
    insert into core.character_alias (character_id, licensor_id, alias, source_system)
    values (v_char_a, v_lic_a, 'Unsourced ' || v_suffix, '   ');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: an alias was recorded with a blank source_system';
  end if;

  -- C8. A name that normalizes to nothing can never be matched. Refused.
  v_raised := false;
  begin
    insert into core.character_alias (character_id, licensor_id, alias, source_system)
    values (v_char_a, v_lic_a, '---', 'manual');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: an alias that normalizes to nothing was accepted';
  end if;

  -- C9. The canonical character cannot be deleted out from under its aliases.
  v_raised := false;
  begin
    delete from core.character where id = v_char_a;
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: a character with live aliases was deleted';
  end if;

  -- =========================================================================
  -- D. core.taxonomy_source_ref -- provenance cannot be recorded without its source
  -- =========================================================================

  -- D1. The licensor is DERIVED, not asked for.
  insert into core.taxonomy_source_ref
    (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
  values ('core', 'character', v_char_a, 'zz_portal_2355', 'characters', '5')
  returning id, source_licensor_id, is_current into v_ref, v_uuid, v_bool;
  if v_uuid <> v_lic_a then
    raise exception '#2355: source_licensor_id was not derived from the entity (% <> %)', v_uuid, v_lic_a;
  end if;
  if not v_bool then
    raise exception '#2355: a freshly recorded source ref must be current';
  end if;
  if (select first_seen_at from core.taxonomy_source_ref where id = v_ref) is null
     or (select last_seen_at from core.taxonomy_source_ref where id = v_ref) is null then
    raise exception '#2355: first_seen_at/last_seen_at were not populated';
  end if;

  -- =====================================================================
  -- D2. THE COLLISION. Licensor B also numbers its characters from small
  --     integers and also calls this one '5'. The importer pattern used
  --     everywhere in this repository is:
  --         on conflict (source_system, source_table, source_id)
  --         do update set entity_id = excluded.entity_id
  --     Left unguarded, that upsert silently hands licensor A's provenance
  --     row to licensor B's character, and every royalty and approval
  --     decision downstream is then made against the wrong licensor.
  --     It must FAIL, loudly.
  -- =====================================================================
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
    values ('core', 'character', v_char_b, 'zz_portal_2355', 'characters', '5')
    on conflict (source_system, source_table, source_id) do update
      set entity_id = excluded.entity_id,
          entity_table = excluded.entity_table,
          source_licensor_id = null;
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception
      '#2355: two licensors reusing source id 5 collapsed into ONE provenance row -- this is the royalty misattribution the issue exists to prevent';
  end if;

  -- And the original row is untouched: it still belongs to licensor A.
  if (select source_licensor_id from core.taxonomy_source_ref where id = v_ref) <> v_lic_a then
    raise exception '#2355: the refused collision still mutated licensor A''s provenance row';
  end if;
  if (select entity_id from core.taxonomy_source_ref where id = v_ref) <> v_char_a then
    raise exception '#2355: the refused collision still repointed licensor A''s provenance row';
  end if;

  -- =====================================================================
  -- D2b. THE GRANDFATHERED COLLISION. Every row that predates this
  --      migration carries source_licensor_id NULL. The immutability rule
  --      D2 proves keys off the row's ALREADY-STAMPED licensor, so on a
  --      legacy row it has nothing to compare against, and the FIRST
  --      conflicting upsert would stamp the thief's licensor on and call
  --      it settled. Those are exactly the rows a colliding importer
  --      reaches first. The old TARGET still says who the row belonged
  --      to, so this must FAIL too.
  --      A legacy-shaped row can only be fabricated with the guard off:
  --      the guard stamps a licensor on every row it is shown.
  -- =====================================================================
  alter table core.taxonomy_source_ref disable trigger a_taxonomy_source_ref_identity_guard;
  insert into core.taxonomy_source_ref
    (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
  values ('core', 'character', v_char_a, 'zz_portal_2355', 'legacy_characters', '5')
  returning id into v_legacy_ref;
  alter table core.taxonomy_source_ref enable trigger a_taxonomy_source_ref_identity_guard;

  if (select source_licensor_id from core.taxonomy_source_ref where id = v_legacy_ref) is not null then
    raise exception
      '#2355: the pre-migration fixture row was stamped with a licensor, so it does not test the grandfathered path at all';
  end if;

  v_raised := false;
  begin
    update core.taxonomy_source_ref
       set entity_id = v_char_b
     where id = v_legacy_ref;
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception
      '#2355: a pre-migration row with a null source_licensor_id was re-attributed to another licensor on its first conflicting write';
  end if;
  if (select entity_id from core.taxonomy_source_ref where id = v_legacy_ref) <> v_char_a then
    raise exception '#2355: the refused legacy re-attribution still repointed the row';
  end if;
  if (select source_licensor_id from core.taxonomy_source_ref where id = v_legacy_ref) is not null then
    raise exception '#2355: the refused legacy re-attribution still stamped a licensor on the row';
  end if;

  -- D2c. ...but HEALING a legacy row is not stealing it. A repoint that stays inside
  --      the SAME licensor must still succeed and stamp the licensor it always had,
  --      or the rule above has quietly become a blanket ban on touching any
  --      pre-migration row -- which would strand every grandfathered row forever.
  update core.taxonomy_source_ref
     set entity_id = v_char_a2
   where id = v_legacy_ref
  returning source_licensor_id into v_uuid;
  if v_uuid is distinct from v_lic_a then
    raise exception
      '#2355: a same-licensor heal of a pre-migration row was refused or mis-stamped (% <> %) -- the anti-collision rule has become a blanket refusal',
      v_uuid, v_lic_a;
  end if;

  -- D3. Licensor B may record its OWN '5' under a distinct source_table. Recording
  --     provenance separately is always available; only the merge is refused.
  insert into core.taxonomy_source_ref
    (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
  values ('core', 'character', v_char_b, 'zz_portal_2355', 'characters_licensor_b', '5')
  returning source_licensor_id into v_uuid;
  if v_uuid <> v_lic_b then
    raise exception '#2355: licensor B''s own provenance row was not scoped to licensor B';
  end if;

  -- D4. A source_licensor_id that disagrees with the entity is refused, not trusted.
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id, source_licensor_id)
    values ('core', 'character', v_char_a, 'zz_portal_2355', 'characters', '77', v_lic_b);
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: a caller-supplied source_licensor_id contradicting the entity was trusted';
  end if;

  -- D5. Provenance with a blank source id is not provenance.
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
    values ('core', 'character', v_char_a, 'zz_portal_2355', 'characters', '   ');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: a source ref was recorded with a blank source_id';
  end if;

  -- D6. KIND-SAFE TARGET INTEGRITY: entity_id is an untyped uuid. It may not name a
  --     row that does not exist...
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
    values ('core', 'character', gen_random_uuid(), 'zz_portal_2355', 'characters', '88');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: provenance was recorded against a character that does not exist';
  end if;

  -- ...nor may entity_table name something that is not a table.
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
    values ('core', 'not_a_real_kind', v_char_a, 'zz_portal_2355', 'characters', '89');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: provenance was recorded against a kind that does not exist';
  end if;

  -- ...and a uuid belonging to a DIFFERENT kind is refused, which is what makes the
  -- licensor derivation trustworthy in the first place.
  v_raised := false;
  begin
    insert into core.taxonomy_source_ref
      (entity_schema, entity_table, entity_id, source_system, source_table, source_id)
    values ('core', 'character', v_lic_a, 'zz_portal_2355', 'characters', '90');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2355: a licensor uuid was accepted as a character entity_id';
  end if;

  -- D6b. A RE-ASSERTION advances last_seen_at. Importers upsert entity_id and name no
  --      freshness column, so if the guard did not advance it the column would be a
  --      permanent lie about when the source last said this.
  update core.taxonomy_source_ref
     set first_seen_at = now() - interval '3 days',
         last_seen_at  = now() - interval '2 days'
   where id = v_ref;
  update core.taxonomy_source_ref set entity_id = v_char_a where id = v_ref;
  if (select last_seen_at from core.taxonomy_source_ref where id = v_ref) < now() - interval '1 minute' then
    raise exception '#2355: last_seen_at was not advanced by a re-assertion';
  end if;

  -- D7. Absence is RECORDED, not deleted. missing_since flips is_current.
  update core.taxonomy_source_ref set missing_since = now() where id = v_ref;
  if (select is_current from core.taxonomy_source_ref where id = v_ref) then
    raise exception '#2355: is_current stayed true after missing_since was set';
  end if;
  if (select first_seen_at from core.taxonomy_source_ref where id = v_ref) is null then
    raise exception '#2355: first_seen_at was lost on update';
  end if;

  -- D8. first_seen_at is a fact about the past and may not be moved forward.
  update core.taxonomy_source_ref
     set first_seen_at = now() + interval '1 day'
   where id = v_ref;
  if (select first_seen_at from core.taxonomy_source_ref where id = v_ref) > now() then
    raise exception '#2355: first_seen_at was moved forward by a later write';
  end if;

  -- =========================================================================
  -- E. Existing rows are PRESERVED. This migration rewrites nothing.
  -- =========================================================================
  select count(*) into v_count from core.taxonomy_source_ref
   where source_system not like 'zz_portal_2355%';
  if v_count < v_legacy then
    raise exception '#2355: % pre-existing taxonomy_source_ref row(s) disappeared', v_legacy - v_count;
  end if;

  -- The grandfathering constraints must stay NOT VALID: validating them would require
  -- rewriting the very rows this issue must preserve.
  foreach v_txt in array array['taxonomy_source_ref_first_seen_present','taxonomy_source_ref_last_seen_present'] loop
    if not exists (
      select 1 from pg_constraint
      where conrelid = 'core.taxonomy_source_ref'::regclass and conname = v_txt and not convalidated
    ) then
      raise exception
        '#2355: % must exist and remain NOT VALID -- validating it would rewrite pre-#2355 rows', v_txt;
    end if;
  end loop;

  raise notice '#2355 contracts: all character alias and source provenance assertions held';
end
$contracts$;
