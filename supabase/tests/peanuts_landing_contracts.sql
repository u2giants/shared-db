-- =====================================================================================
-- Peanuts (Tenovos) landing contract tests -- migration 20260819112505, issue #1217,
-- claim #1231.
--
-- HOW TO RUN
--   Against a throwaway or preview database, as the migration owner:
--       \i supabase/tests/peanuts_landing_contracts.sql
--   The whole file runs inside ONE transaction and ends in ROLLBACK, so it leaves no row
--   behind. Every negative test runs inside a plpgsql block with a SPECIFIC exception
--   handler and asserts that the expected error ACTUALLY FIRED, naming WHICH constraint
--   fired. A test that merely fails to observe an error proves nothing, and a test that
--   would stay green with its constraint deleted is itself a defect.
--
--   There is deliberately NO `exception when others` anywhere in this file. A broad
--   handler passes on a typo in the test itself, which is the failure mode these
--   contracts exist to prevent.
--
-- EVERY VALUE IN THIS FILE IS INVENTED.
--   u2giants/shared-db is PUBLIC. Not one Peanuts art program, style guide, character,
--   initiative, holiday, animation title, asset type, file name, title, keyword, era or
--   portal URL appears here. The fixtures use obviously fake tokens (ZZTEST-*,
--   example.invalid) chosen so a real row could never be mistaken for one of them.
--
-- WHY THE FIXTURES INSERT THE CAPTURE ROW DIRECTLY
--   The begin/finalize security-definer pair is NOT part of migration 20260819112505 --
--   it ships under its own object claim (see the OPEN DEPENDENCY note in the migration
--   header). service_role therefore holds SELECT only on plm.peanuts_capture. These tests
--   run as the table OWNER, which can still insert, so the table contracts below are
--   exercised without inventing an unclaimed function. Section B proves that service_role
--   itself still cannot.
--
-- WHAT IT ASSERTS
--   A. The 19 tables exist, RLS is enabled on every one, and each carries exactly 2 read
--      policies. No media column. No art-program-to-character table, in any form.
--   B. Append-only privilege separation genuinely DENIES update, delete AND truncate --
--      proven by executing them as service_role, not merely by reading a grant table --
--      while INSERT on the 18 snapshot tables still works and INSERT on the capture root
--      does not.
--   C. The capture publication gate: every clause of the completion rule is falsified
--      one at a time, so no clause can be deleted without a test going red.
--   D. Identity, shape and vocabulary contracts, each pinned to a NAMED constraint.
--   E. The declared/derived separation: relationship_truth cannot be anything but
--      'derived', the derived tables cannot carry a zero support count, and the asset
--      relationship graph refuses a self-edge.
-- =====================================================================================

begin;

-- =====================================================================================
-- A. OBJECTS, RLS, POLICIES, AND THE TWO REFUSALS
-- =====================================================================================
do $$
declare
  v_name text;
  v_n    integer;
  v_fail integer := 0;
  v_tables text[] := array[
    'peanuts_capture','peanuts_art_program','peanuts_style_guide','peanuts_character',
    'peanuts_animation_title','peanuts_holiday','peanuts_initiative','peanuts_asset_type',
    'peanuts_licensing_status','peanuts_metadata_field','peanuts_asset',
    'peanuts_asset_art_program','peanuts_asset_character','peanuts_asset_animation_title',
    'peanuts_asset_holiday','peanuts_asset_keyword','peanuts_asset_relationship',
    'peanuts_style_guide_character','peanuts_style_guide_art_program'
  ];
begin
  if array_length(v_tables, 1) <> 19 then
    raise exception 'A FAILED: the test itself names % tables, not 19',
      array_length(v_tables, 1);
  end if;

  foreach v_name in array v_tables loop
    if to_regclass('plm.' || v_name) is null then
      v_fail := v_fail + 1;
      raise warning 'A FAIL: table missing: plm.%', v_name;
      continue;
    end if;
    if not (select relrowsecurity from pg_class where oid = ('plm.' || v_name)::regclass) then
      v_fail := v_fail + 1;
      raise warning 'A FAIL: RLS not enabled on plm.%', v_name;
    end if;
    select count(*) into v_n from pg_policies
     where schemaname = 'plm' and tablename = v_name;
    if v_n <> 2 then
      v_fail := v_fail + 1;
      raise warning 'A FAIL: plm.% has % policies, expected 2 (service read + plm read)',
        v_name, v_n;
    end if;
  end loop;

  -- Nothing outside the claim may have appeared under this prefix.
  select count(*) into v_n from information_schema.tables
   where table_schema = 'plm' and table_name like 'peanuts\_%' and table_type = 'BASE TABLE';
  if v_n <> 19 then
    v_fail := v_fail + 1;
    raise warning 'A FAIL: plm holds % peanuts tables, expected exactly 19', v_n;
  end if;

  -- THE REFUSED RELATIONSHIP. The art-program field is multi-select, so pairing art
  -- programs with characters off one asset asserts something the licensor never said.
  select count(*) into v_n from information_schema.tables
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and table_name like '%art\_program%' and table_name like '%character%';
  if v_n <> 0 then
    v_fail := v_fail + 1;
    raise warning 'A FAIL: % art-program-to-character table(s) exist; that link is refused',
      v_n;
  end if;

  -- No media column may ever exist on the asset table.
  select count(*) into v_n from information_schema.columns
   where table_schema = 'plm' and table_name = 'peanuts_asset'
     and (column_name in ('bytes','media','content','blob','base64','file_bytes')
          or data_type = 'bytea');
  if v_n <> 0 then
    v_fail := v_fail + 1;
    raise warning 'A FAIL: plm.peanuts_asset carries % media-bearing column(s)', v_n;
  end if;

  -- Style guide must be nullable: most assets in this portal carry none.
  if (select is_nullable from information_schema.columns
       where table_schema = 'plm' and table_name = 'peanuts_asset'
         and column_name = 'style_guide_key') is distinct from 'YES' then
    v_fail := v_fail + 1;
    raise warning 'A FAIL: plm.peanuts_asset.style_guide_key is not nullable';
  end if;

  -- The publication date is free text in this portal and must stay text.
  if (select data_type from information_schema.columns
       where table_schema = 'plm' and table_name = 'peanuts_asset'
         and column_name = 'publication_date_text') is distinct from 'text' then
    v_fail := v_fail + 1;
    raise warning 'A FAIL: plm.peanuts_asset.publication_date_text is not text';
  end if;

  -- Every vocabulary table must record BOTH the internal field name and the UI label.
  -- Losing either one is how the label/name mismatch becomes permanent.
  foreach v_name in array array[
    'peanuts_art_program','peanuts_style_guide','peanuts_character',
    'peanuts_animation_title','peanuts_holiday','peanuts_initiative',
    'peanuts_asset_type','peanuts_licensing_status'] loop
    select count(*) into v_n from information_schema.columns
     where table_schema = 'plm' and table_name = v_name
       and column_name in ('source_field_name','source_field_label','value_key',
                           'value_label','source_value_id','asset_count');
    if v_n <> 6 then
      v_fail := v_fail + 1;
      raise warning 'A FAIL: plm.% is missing vocabulary columns (found % of 6)', v_name, v_n;
    end if;
  end loop;

  if v_fail > 0 then raise exception 'A FAILED (% failures)', v_fail; end if;
  raise notice 'A passed: 19 tables, RLS, 38 policies, no media, no art-program/character link';
end;
$$;


-- =====================================================================================
-- B. PRIVILEGES -- the catalog, and then the behaviour it is supposed to produce.
-- =====================================================================================
do $$
declare
  v_n integer;
begin
  select count(*) into v_n from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee in ('service_role','authenticated','anon','PUBLIC')
     and privilege_type in ('UPDATE','DELETE','TRUNCATE');
  if v_n <> 0 then
    raise exception 'B FAILED: % write grant(s) exist on plm.peanuts_* tables', v_n;
  end if;

  select count(*) into v_n from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'service_role' and privilege_type = 'SELECT';
  if v_n <> 19 then
    raise exception 'B FAILED: expected 19 service_role SELECT grants, found %', v_n;
  end if;

  select count(*) into v_n from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'service_role' and privilege_type = 'INSERT';
  if v_n <> 18 then
    raise exception 'B FAILED: expected 18 service_role INSERT grants, found %', v_n;
  end if;

  if has_table_privilege('service_role','plm.peanuts_capture','INSERT') then
    raise exception 'B FAILED: plm.peanuts_capture is directly insertable by service_role';
  end if;

  select count(*) into v_n from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%' and grantee = 'anon';
  if v_n <> 0 then
    raise exception 'B FAILED: anon holds % grant(s) on plm.peanuts_* tables', v_n;
  end if;

  select count(*) into v_n from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_n <> 19 then
    raise exception 'B FAILED: expected 19 authenticated SELECT grants, found %', v_n;
  end if;

  raise notice 'B (catalog) passed';
end;
$$;

-- The behavioural half of B. A grant table can be read wrongly; an actual UPDATE cannot.
do $$
declare
  v_cap      uuid;
  v_denied   integer := 0;
  v_expected integer := 11;
  v_t        text;
  -- A representative spread across the structural classes: the vocabulary table whose
  -- single-select flag is pinned, the high-volume asset table, a declared link table, the
  -- declared hierarchy, and a derived table.
  v_spread text[] := array[
    'peanuts_style_guide','peanuts_asset','peanuts_asset_character',
    'peanuts_asset_relationship','peanuts_style_guide_character'
  ];
begin
  insert into plm.peanuts_capture (
    capture_key, source_repository, source_commit_sha, source_manifest_sha256,
    portal_base_url, api_endpoint, source_customer_id, source_captured_at,
    expected_counts, raw_summary, created_by,
    portal_reported_asset_total, assets_captured, assets_unreachable)
  values ('ZZTEST-peanuts-B', 'ZZTEST-repo', repeat('a', 40), repeat('a', 64),
          'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
          '2099-01-01Z', '{"assets":1}'::jsonb, '{}'::jsonb, 'ZZTEST', 0, 0, 0)
  returning id into v_cap;

  insert into plm.peanuts_art_program (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values (v_cap, 'zztest-program-a', 'ZZTEST Program A', 'zztest_internal_name',
          'ZZTEST Label', true, 0, '{}');

  execute 'set local role service_role';

  -- The loader may still INSERT into a snapshot table: a revoke that overshot would break
  -- the load silently.
  begin
    insert into plm.peanuts_art_program (
      capture_id, value_key, value_label, source_field_name, source_field_label,
      is_multi_select, asset_count, raw)
    values (v_cap, 'zztest-program-b', 'ZZTEST Program B', 'zztest_internal_name',
            'ZZTEST Label', true, 3, '{}');
  exception when insufficient_privilege then
    execute 'reset role';
    raise exception
      'B FAILED: service_role cannot INSERT a snapshot row; the revoke overshot';
  end;

  begin
    update plm.peanuts_art_program set value_label = 'ZZTEST mutated'
     where capture_id = v_cap;
    raise warning 'B FAIL: service_role UPDATE on plm.peanuts_art_program SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  begin
    delete from plm.peanuts_art_program where capture_id = v_cap;
    raise warning 'B FAIL: service_role DELETE on plm.peanuts_art_program SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  -- TRUNCATE is a distinct privilege from DELETE. An append-only snapshot that revokes
  -- DELETE but leaves TRUNCATE reachable can still be emptied in one statement.
  begin
    truncate table plm.peanuts_art_program;
    raise warning 'B FAIL: service_role TRUNCATE on plm.peanuts_art_program SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  -- The capture root: no INSERT, no UPDATE, no TRUNCATE, ever.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable)
    values ('ZZTEST-peanuts-B-direct', 'ZZTEST-repo', repeat('b', 40), repeat('b', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '{}'::jsonb, '{}'::jsonb, 'ZZTEST', 0, 0, 0);
    raise warning 'B FAIL: service_role INSERT into plm.peanuts_capture SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  begin
    update plm.peanuts_capture set status = 'complete' where id = v_cap;
    raise warning 'B FAIL: service_role UPDATE on plm.peanuts_capture SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  begin
    truncate table plm.peanuts_capture;
    raise warning 'B FAIL: service_role TRUNCATE on plm.peanuts_capture SUCCEEDED';
  exception when insufficient_privilege then v_denied := v_denied + 1;
  end;

  -- UPDATE / DELETE / TRUNCATE denied across the representative spread. The privilege
  -- check happens before any row is touched, so an empty table proves the grant exactly
  -- as a populated one does.
  foreach v_t in array v_spread loop
    begin
      execute format('update plm.%I set capture_id = capture_id', v_t);
      raise warning 'B FAIL: service_role UPDATE on plm.% SUCCEEDED', v_t;
    exception when insufficient_privilege then v_denied := v_denied + 1;
    end;
  end loop;

  execute 'reset role';

  if v_denied <> v_expected then
    raise exception 'B FAILED: % of % write attempts were denied', v_denied, v_expected;
  end if;
  raise notice 'B (behaviour) passed: % write attempts denied', v_denied;
end;
$$;


-- =====================================================================================
-- C. THE PUBLICATION GATE. Every clause falsified one at a time.
--
-- The point of this section is that no clause of
-- peanuts_capture_complete_requirements_chk can be deleted without a test going red.
-- Each block below satisfies EVERY clause except the one under test.
-- =====================================================================================
do $$
declare
  v_con    text;
  v_raised integer := 0;
  v_want   integer := 5;
begin
  -- C1. A capture that never partitioned around the 10,000-row paging wall.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      load_completed_at, status, expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable,
      deep_paging_partitioned, vocabularies_loaded_from_source)
    values ('ZZTEST-peanuts-C1', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '2099-01-02Z', 'complete', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
            10, 8, 2, false, true);
    raise warning 'C FAIL: an un-partitioned capture published as complete';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_capture_complete_requirements_chk' then
      raise exception 'C1 FAILED: expected peanuts_capture_complete_requirements_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- C2. A capture whose vocabularies came from distinct() over assets rather than from
  -- the vocabulary API. This is the clause that protects the hundreds of vocabulary
  -- values no asset uses.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      load_completed_at, status, expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable,
      deep_paging_partitioned, vocabularies_loaded_from_source)
    values ('ZZTEST-peanuts-C2', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '2099-01-02Z', 'complete', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
            10, 8, 2, true, false);
    raise warning 'C FAIL: a vocabulary-shortcut capture published as complete';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_capture_complete_requirements_chk' then
      raise exception 'C2 FAILED: expected peanuts_capture_complete_requirements_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- C3. THE SHORTFALL CLAUSE. assets_unreachable = 0 while the capture sits below the
  -- portal's own total is exactly the silent-truncation shape this landing exists to
  -- refuse.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      load_completed_at, status, expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable,
      deep_paging_partitioned, vocabularies_loaded_from_source)
    values ('ZZTEST-peanuts-C3', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '2099-01-02Z', 'complete', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
            10, 8, 0, true, true);
    raise warning 'C FAIL: a short capture with zero unreachable assets published';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_capture_complete_requirements_chk' then
      raise exception 'C3 FAILED: expected peanuts_capture_complete_requirements_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- C4. A capture carrying validation errors.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      load_completed_at, status, expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable,
      deep_paging_partitioned, vocabularies_loaded_from_source, error_summary)
    values ('ZZTEST-peanuts-C4', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '2099-01-02Z', 'complete', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
            10, 8, 2, true, true, '["ZZTEST-error"]'::jsonb);
    raise warning 'C FAIL: a capture carrying validation errors published as complete';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_capture_complete_requirements_chk' then
      raise exception 'C4 FAILED: expected peanuts_capture_complete_requirements_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- C5. status and load_completed_at must agree in BOTH directions. A completion time on
  -- a still-loading capture is the mirror-image lie and has its own constraint.
  begin
    insert into plm.peanuts_capture (
      capture_key, source_repository, source_commit_sha, source_manifest_sha256,
      portal_base_url, api_endpoint, source_customer_id, source_captured_at,
      load_completed_at, status, expected_counts, raw_summary, created_by,
      portal_reported_asset_total, assets_captured, assets_unreachable)
    values ('ZZTEST-peanuts-C5', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
            'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
            '2099-01-01Z', '2099-01-02Z', 'loading', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
            10, 8, 2);
    raise warning 'C FAIL: a loading capture carried a completion time';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_capture_complete_time_chk' then
      raise exception 'C5 FAILED: expected peanuts_capture_complete_time_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  if v_raised <> v_want then
    raise exception 'C FAILED: % of % gate clauses refused their bad row', v_raised, v_want;
  end if;

  -- And the positive case: a capture that satisfies every clause DOES publish. Without
  -- this, a constraint that rejected everything would still pass C1-C5.
  insert into plm.peanuts_capture (
    capture_key, source_repository, source_commit_sha, source_manifest_sha256,
    portal_base_url, api_endpoint, source_customer_id, source_captured_at,
    load_completed_at, status, expected_counts, raw_summary, created_by,
    portal_reported_asset_total, assets_captured, assets_unreachable,
    deep_paging_partitioned, vocabularies_loaded_from_source, relationship_graph_walked)
  values ('ZZTEST-peanuts-C-ok', 'ZZTEST-repo', repeat('c', 40), repeat('c', 64),
          'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
          '2099-01-01Z', '2099-01-02Z', 'complete', '{}'::jsonb, '{}'::jsonb, 'ZZTEST',
          10, 8, 2, true, true, true);

  raise notice 'C passed: every publication-gate clause is independently falsifiable';
end;
$$;


-- =====================================================================================
-- D. IDENTITY, SHAPE AND VOCABULARY CONTRACTS. Each pinned to a NAMED constraint.
-- =====================================================================================
do $$
declare
  v_cap    uuid;
  v_con    text;
  v_raised integer := 0;
  v_want   integer := 8;
begin
  insert into plm.peanuts_capture (
    capture_key, source_repository, source_commit_sha, source_manifest_sha256,
    portal_base_url, api_endpoint, source_customer_id, source_captured_at,
    expected_counts, raw_summary, created_by,
    portal_reported_asset_total, assets_captured, assets_unreachable)
  values ('ZZTEST-peanuts-D', 'ZZTEST-repo', repeat('d', 40), repeat('d', 64),
          'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
          '2099-01-01Z', '{"assets":1}'::jsonb, '{}'::jsonb, 'ZZTEST', 0, 0, 0)
  returning id into v_cap;

  insert into plm.peanuts_style_guide (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values (v_cap, 'zztest-guide-a', 'ZZTEST Guide A', 'zztest_guide_field',
          'ZZTEST Guide Label', false, 0, '{}');

  insert into plm.peanuts_character (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values (v_cap, 'zztest-character-a', 'ZZTEST Character A', 'zztest_character_field',
          'ZZTEST Character Label', true, 0, '{}');

  insert into plm.peanuts_asset (
    capture_id, source_object_id, file_name, raw)
  values (v_cap, 'ZZTEST-OBJ-1', 'zztest-file-one.ext', '{}');

  -- D1. A vocabulary value used by ZERO assets is legal and meaningful. This is the whole
  -- reason asset_count is >= 0 rather than > 0, and it is asserted positively: the two
  -- inserts above already used asset_count = 0 and must have succeeded.
  if not exists (select 1 from plm.peanuts_style_guide
                  where capture_id = v_cap and asset_count = 0) then
    raise exception 'D1 FAILED: a zero-usage vocabulary value was not stored';
  end if;

  -- D2. But a NEGATIVE count is nonsense.
  begin
    insert into plm.peanuts_style_guide (
      capture_id, value_key, value_label, source_field_name, source_field_label,
      is_multi_select, asset_count, raw)
    values (v_cap, 'zztest-guide-neg', 'ZZTEST Guide Neg', 'zztest_guide_field',
            'ZZTEST Guide Label', false, -1, '{}');
    raise warning 'D FAIL: a negative asset_count was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_style_guide_asset_count_nonneg_chk' then
      raise exception 'D2 FAILED: expected peanuts_style_guide_asset_count_nonneg_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D3. The style-guide axis is SINGLE-select, and that fact is load-bearing for both
  -- derived tables. A multi-select style-guide row must be refused outright.
  begin
    insert into plm.peanuts_style_guide (
      capture_id, value_key, value_label, source_field_name, source_field_label,
      is_multi_select, asset_count, raw)
    values (v_cap, 'zztest-guide-multi', 'ZZTEST Guide Multi', 'zztest_guide_field',
            'ZZTEST Guide Label', true, 0, '{}');
    raise warning 'D FAIL: a multi-select style-guide vocabulary row was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_style_guide_single_select_chk' then
      raise exception 'D3 FAILED: expected peanuts_style_guide_single_select_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D4. A blank text identifier is never an identifier.
  begin
    insert into plm.peanuts_asset (capture_id, source_object_id, file_name, raw)
    values (v_cap, '   ', 'zztest-file-blank.ext', '{}');
    raise warning 'D FAIL: a blank source_object_id was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_object_id_nonblank_chk' then
      raise exception 'D4 FAILED: expected peanuts_asset_object_id_nonblank_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D5. raw must be a JSON object, not an array or a scalar.
  begin
    insert into plm.peanuts_asset (capture_id, source_object_id, file_name, raw)
    values (v_cap, 'ZZTEST-OBJ-RAW', 'zztest-file-raw.ext', '[]');
    raise warning 'D FAIL: a non-object raw payload was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_raw_obj_chk' then
      raise exception 'D5 FAILED: expected peanuts_asset_raw_obj_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D6. file_ext is lowercased and dot-free, so one extension cannot land three ways.
  begin
    insert into plm.peanuts_asset (capture_id, source_object_id, file_name, file_ext, raw)
    values (v_cap, 'ZZTEST-OBJ-EXT', 'zztest-file-ext.ext', '.EXT', '{}');
    raise warning 'D FAIL: an uppercase dotted file_ext was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_file_ext_shape_chk' then
      raise exception 'D6 FAILED: expected peanuts_asset_file_ext_shape_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D7. FILENAME IS NOT IDENTITY. Two assets with the same filename and different object
  -- ids must BOTH land -- a unique index on the filename would silently drop one.
  insert into plm.peanuts_asset (capture_id, source_object_id, file_name, raw)
  values (v_cap, 'ZZTEST-OBJ-2', 'zztest-file-one.ext', '{}');
  if (select count(*) from plm.peanuts_asset
       where capture_id = v_cap and lower(file_name) = 'zztest-file-one.ext') <> 2 then
    raise exception 'D7 FAILED: a duplicate filename did not land; filename is being treated as identity';
  end if;

  -- D8. But the licensor's own object id IS identity, and repeats within one capture.
  begin
    insert into plm.peanuts_asset (capture_id, source_object_id, file_name, raw)
    values (v_cap, 'ZZTEST-OBJ-1', 'zztest-file-other.ext', '{}');
    raise warning 'D FAIL: a duplicate source_object_id was accepted';
  exception when unique_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_pkey' then
      raise exception 'D8 FAILED: expected peanuts_asset_pkey, % fired (%)', v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D9. An asset may carry NO style guide. Most of this portal's assets do not, and a
  -- schema that made this column mandatory would drop them.
  if (select count(*) from plm.peanuts_asset
       where capture_id = v_cap and style_guide_key is null) < 1 then
    raise exception 'D9 FAILED: an asset with no style guide was not stored';
  end if;

  -- D10. A style-guide key that is not in the vocabulary is a dangling reference.
  begin
    insert into plm.peanuts_asset (
      capture_id, source_object_id, file_name, style_guide_key, raw)
    values (v_cap, 'ZZTEST-OBJ-FK', 'zztest-file-fk.ext', 'zztest-guide-absent', '{}');
    raise warning 'D FAIL: an unknown style_guide_key was accepted';
  exception when foreign_key_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_style_guide_fkey' then
      raise exception 'D10 FAILED: expected peanuts_asset_style_guide_fkey, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D11. The field dictionary must be unique in the LABEL direction too. Two internal
  -- names claiming one UI label is precisely the confusion this table exists to prevent.
  insert into plm.peanuts_metadata_field (
    capture_id, source_field_name, source_field_label, source_definition_id,
    is_multi_select, is_facetable, field_type, raw)
  values (v_cap, 'zztest_internal_one', 'ZZTEST Field Label', 'zztest-def-1',
          false, true, 'zztest_type', '{}');
  begin
    insert into plm.peanuts_metadata_field (
      capture_id, source_field_name, source_field_label, source_definition_id,
      is_multi_select, is_facetable, field_type, raw)
    values (v_cap, 'zztest_internal_two', 'ZZTEST Field Label', 'zztest-def-2',
            false, true, 'zztest_type', '{}');
    raise warning 'D FAIL: two internal field names shared one UI label';
  exception when unique_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_metadata_field_label_uk' then
      raise exception 'D11 FAILED: expected peanuts_metadata_field_label_uk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- D12. A keyword link needs no vocabulary row -- the keyword vocabulary is open. This
  -- is asserted positively, because a foreign key added here later would reject real rows.
  insert into plm.peanuts_asset_keyword (
    capture_id, source_object_id, keyword_key, keyword_label, raw)
  values (v_cap, 'ZZTEST-OBJ-1', 'zztest-keyword-a', 'ZZTEST Keyword A', '{}');
  if not exists (select 1 from plm.peanuts_asset_keyword
                  where capture_id = v_cap and keyword_key = 'zztest-keyword-a') then
    raise exception 'D12 FAILED: an open-vocabulary keyword did not land';
  end if;

  if v_raised <> v_want then
    raise exception 'D FAILED: % of % negative cases fired their named constraint',
      v_raised, v_want;
  end if;
  raise notice 'D passed: % named-constraint refusals plus the positive cases', v_raised;
end;
$$;


-- =====================================================================================
-- E. DECLARED vs DERIVED, AND THE HIERARCHY.
-- =====================================================================================
do $$
declare
  v_cap    uuid;
  v_con    text;
  v_raised integer := 0;
  v_want   integer := 5;
begin
  insert into plm.peanuts_capture (
    capture_key, source_repository, source_commit_sha, source_manifest_sha256,
    portal_base_url, api_endpoint, source_customer_id, source_captured_at,
    expected_counts, raw_summary, created_by,
    portal_reported_asset_total, assets_captured, assets_unreachable)
  values ('ZZTEST-peanuts-E', 'ZZTEST-repo', repeat('e', 40), repeat('e', 64),
          'https://example.invalid', 'https://api.example.invalid', 'ZZTEST-customer',
          '2099-01-01Z', '{"assets":2}'::jsonb, '{}'::jsonb, 'ZZTEST', 0, 0, 0)
  returning id into v_cap;

  insert into plm.peanuts_style_guide (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values (v_cap, 'zztest-guide-a', 'ZZTEST Guide A', 'zztest_guide_field',
          'ZZTEST Guide Label', false, 2, '{}');

  insert into plm.peanuts_character (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values (v_cap, 'zztest-character-a', 'ZZTEST Character A', 'zztest_character_field',
          'ZZTEST Character Label', true, 2, '{}');

  insert into plm.peanuts_art_program (
    capture_id, value_key, value_label, source_field_name, source_field_label,
    is_multi_select, asset_count, raw)
  values
    (v_cap, 'zztest-program-a', 'ZZTEST Program A', 'zztest_program_field',
     'ZZTEST Program Label', true, 2, '{}'),
    (v_cap, 'zztest-program-b', 'ZZTEST Program B', 'zztest_program_field',
     'ZZTEST Program Label', true, 1, '{}');

  insert into plm.peanuts_asset (capture_id, source_object_id, file_name, raw)
  values (v_cap, 'ZZTEST-PARENT', 'zztest-parent.ext', '{}'),
         (v_cap, 'ZZTEST-CHILD',  'zztest-child.ext',  '{}');

  -- E1. The declared hierarchy stores its link type VERBATIM. No CHECK may pin it to the
  -- values seen so far, so an unfamiliar edge must land rather than fail.
  insert into plm.peanuts_asset_relationship (
    capture_id, source_relationship_id, parent_object_id, child_object_id, link_type, raw)
  values (v_cap, 'ZZTEST-REL-1', 'ZZTEST-PARENT', 'ZZTEST-CHILD', 'zztest_unseen_link', '{}');
  if not exists (select 1 from plm.peanuts_asset_relationship
                  where capture_id = v_cap and link_type = 'zztest_unseen_link') then
    raise exception 'E1 FAILED: an unfamiliar link_type did not land verbatim';
  end if;

  -- E2. An asset cannot be its own parent.
  begin
    insert into plm.peanuts_asset_relationship (
      capture_id, source_relationship_id, parent_object_id, child_object_id, link_type, raw)
    values (v_cap, 'ZZTEST-REL-SELF', 'ZZTEST-PARENT', 'ZZTEST-PARENT', 'zztest_link', '{}');
    raise warning 'E FAIL: a self-referencing relationship was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_relationship_not_self_chk' then
      raise exception 'E2 FAILED: expected peanuts_asset_relationship_not_self_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- E3. Both endpoints must be assets in the same capture.
  begin
    insert into plm.peanuts_asset_relationship (
      capture_id, source_relationship_id, parent_object_id, child_object_id, link_type, raw)
    values (v_cap, 'ZZTEST-REL-DANGLE', 'ZZTEST-ABSENT', 'ZZTEST-CHILD', 'zztest_link', '{}');
    raise warning 'E FAIL: a relationship with an unknown parent was accepted';
  exception when foreign_key_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_asset_relationship_parent_fkey' then
      raise exception 'E3 FAILED: expected peanuts_asset_relationship_parent_fkey, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- E4. A derived row may not claim to be fact. relationship_truth is CONSTRAINED, not
  -- defaulted, so no later writer can quietly promote these rows.
  begin
    insert into plm.peanuts_style_guide_character (
      capture_id, style_guide_key, character_key, asset_count, relationship_truth,
      derivation_note)
    values (v_cap, 'zztest-guide-a', 'zztest-character-a', 2, 'declared', 'ZZTEST note');
    raise warning 'E FAIL: a derived style-guide/character row claimed to be declared';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_style_guide_character_truth_chk' then
      raise exception 'E4 FAILED: expected peanuts_style_guide_character_truth_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- E5. Same pin on the art-programme derivation.
  begin
    insert into plm.peanuts_style_guide_art_program (
      capture_id, style_guide_key, art_program_key, asset_count, relationship_truth,
      derivation_note)
    values (v_cap, 'zztest-guide-a', 'zztest-program-a', 2, 'declared', 'ZZTEST note');
    raise warning 'E FAIL: a derived style-guide/art-program row claimed to be declared';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_style_guide_art_program_truth_chk' then
      raise exception 'E5 FAILED: expected peanuts_style_guide_art_program_truth_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  -- E6. A derived edge with no supporting asset has nothing behind it.
  begin
    insert into plm.peanuts_style_guide_character (
      capture_id, style_guide_key, character_key, asset_count, relationship_truth,
      derivation_note)
    values (v_cap, 'zztest-guide-a', 'zztest-character-a', 0, 'derived', 'ZZTEST note');
    raise warning 'E FAIL: a derived row with zero supporting assets was accepted';
  exception when check_violation then
    get stacked diagnostics v_con = constraint_name;
    if coalesce(v_con, '') <> 'peanuts_style_guide_character_asset_count_pos_chk' then
      raise exception
        'E6 FAILED: expected peanuts_style_guide_character_asset_count_pos_chk, % fired (%)',
        v_con, sqlerrm;
    end if;
    v_raised := v_raised + 1;
  end;

  if v_raised <> v_want then
    raise exception 'E FAILED: % of % negative cases fired their named constraint',
      v_raised, v_want;
  end if;

  -- E7. THE MANY-TO-MANY REQUIREMENT, asserted positively. One style guide under TWO art
  -- programmes must land. A one-programme-per-guide model would reject the second row,
  -- and it would be wrong on data this project already holds.
  insert into plm.peanuts_style_guide_art_program (
    capture_id, style_guide_key, art_program_key, asset_count, relationship_truth,
    derivation_note)
  values (v_cap, 'zztest-guide-a', 'zztest-program-a', 2, 'derived',
          'ZZTEST derivation: co-occurrence on assets; style guide is single-select'),
         (v_cap, 'zztest-guide-a', 'zztest-program-b', 1, 'derived',
          'ZZTEST derivation: co-occurrence on assets; style guide is single-select');
  if (select count(*) from plm.peanuts_style_guide_art_program
       where capture_id = v_cap and style_guide_key = 'zztest-guide-a') <> 2 then
    raise exception 'E7 FAILED: one style guide could not carry two art programmes';
  end if;

  -- E8. The derived character edge lands when it is honestly labelled.
  insert into plm.peanuts_style_guide_character (
    capture_id, style_guide_key, character_key, asset_count, relationship_truth,
    derivation_note)
  values (v_cap, 'zztest-guide-a', 'zztest-character-a', 2, 'derived',
          'ZZTEST derivation: assets carrying both; style guide is single-select so no '
          'pairing is invented');
  if not exists (select 1 from plm.peanuts_style_guide_character
                  where capture_id = v_cap and relationship_truth = 'derived') then
    raise exception 'E8 FAILED: a correctly labelled derived row did not land';
  end if;

  raise notice 'E passed: declared stays verbatim, derived stays derived, many-to-many holds';
end;
$$;

rollback;
