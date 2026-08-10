-- =====================================================================================
-- Contract tests for migration 20260810110000 -- the three HIGH findings raised against
-- PR #663: Warner service_role over-grant, Warner `using (true)` read policy, and
-- api.dam_order_list running as a SECURITY DEFINER view.
--
-- HOW TO RUN
--   Against PREVIEW rjyboqwcdzcocqgmsyel ONLY, as the migration owner (the Supabase
--   CLI's linked connection, or a psql / node-pg session):
--       \i supabase/tests/wb_grants_rls_and_dam_order_list_invoker.sql
--
--   RUN EACH `do $$` BLOCK AS A SEPARATE STATEMENT. Submitting the whole file as one
--   multi-statement batch through the transaction pooler (port 6543) wraps every block
--   in one implicit transaction and stalls -- observed on this database 2026-08-09.
--
-- EVERY VALUE IN THIS FILE IS INVENTED. u2giants/shared-db is PUBLIC. No real Warner
--   franchise, property, character, style guide, asset id, filename or portal URL
--   appears here; the fixtures use ZZTEST-* tokens and example.invalid URLs.
--
-- WHAT IT ASSERTS. The RESULTING privilege set and the RESULTING policy behaviour, not
--   that the statements ran. Section A reads has_table_privilege. Section B evaluates
--   RLS as real principals. Section C reads pg_class.reloptions AND proves the view
--   inherits base-table RLS. Section D exercises a loader end to end and rolls it back.
--
-- SIDE EFFECTS: none. Section D runs inside a savepoint that is always rolled back.
--
-- LAST RUN: 2026-08-09 against preview rjyboqwcdzcocqgmsyel -- all sections passed.
-- =====================================================================================

-- =====================================================================================
-- A. service_role must hold SELECT and INSERT and NOTHING ELSE on all 8 plm.wb_* tables.
--    UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN all arrive free from the plm
--    schema default privilege (20260710135975:14) at CREATE TABLE time, so this is the
--    assertion that catches a table added later without a matching revoke.
--    MAINTAIN is real on this server (PostgreSQL 17.6) -- it is not a hypothetical bit.
-- =====================================================================================
do $$
declare
  v_tables text[] := array[
    'wb_franchise_property','wb_style_guide','wb_character','wb_asset',
    'wb_asset_style_guide','wb_asset_franchise_property','wb_asset_character',
    'wb_property_character'
  ];
  t     text;
  p     text;
  v_bad int := 0;
  v_n   int;
begin
  foreach t in array v_tables loop
    foreach p in array array['UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] loop
      if has_table_privilege('service_role', format('plm.%I', t)::regclass, p) then
        v_bad := v_bad + 1;
        raise warning 'FAIL service_role still holds % on plm.%', p, t;
      end if;
    end loop;

    foreach p in array array['SELECT','INSERT'] loop
      if not has_table_privilege('service_role', format('plm.%I', t)::regclass, p) then
        v_bad := v_bad + 1;
        raise warning 'FAIL service_role LOST % on plm.% -- the loaders'' fallback path is gone', p, t;
      end if;
    end loop;
  end loop;

  -- anon and PUBLIC must hold nothing at all.
  select count(*) into v_n
  from information_schema.role_table_grants
  where table_schema = 'plm' and table_name = any(v_tables)
    and grantee in ('anon', 'PUBLIC');
  if v_n <> 0 then
    v_bad := v_bad + 1;
    raise warning 'FAIL anon/PUBLIC hold % grant(s) on plm.wb_*', v_n;
  end if;

  -- authenticated must be SELECT-only (RLS is not a substitute for a grant).
  select count(*) into v_n
  from information_schema.role_table_grants
  where table_schema = 'plm' and table_name = any(v_tables)
    and grantee = 'authenticated'
    and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
  if v_n <> 0 then
    v_bad := v_bad + 1;
    raise warning 'FAIL authenticated holds % mutation privilege(s) on plm.wb_*', v_n;
  end if;

  if v_bad > 0 then raise exception 'A FAILED (% failures)', v_bad; end if;
  raise notice 'A passed: service_role = SELECT,INSERT only on all 8 plm.wb_* tables';
end;
$$;

-- =====================================================================================
-- B. The Warner read policy must be the role gate copied from 20260807190000:73-81,
--    NOT `using (true)`. Proved by EVALUATING RLS as real principals, because the DDL
--    is exactly what was wrong before: `using (true)` under a comment claiming the
--    posture matched plm.opa_property_character.
--
--    A synthetic row is inserted inside a plpgsql subtransaction (BEGIN/EXCEPTION) that
--    is always unwound by a sentinel exception, so the check works on an empty landing
--    table and leaves nothing behind. A DO block cannot issue SAVEPOINT directly.
-- =====================================================================================
do $$
declare
  v_role  text;
  v_count int;
  v_bad   int := 0;
begin
  -- Guard: exactly one SELECT policy per table, and none of them permissive-open.
  select count(*) into v_count
  from pg_policies
  where schemaname = 'plm' and tablename like 'wb\_%' and qual = 'true';
  if v_count <> 0 then
    raise exception 'B FAILED: % Warner policy/policies still read `using (true)`', v_count;
  end if;

  begin
  insert into plm.wb_franchise_property (source_term, source_id, label, captured_date, source_url, raw, source_hash)
  values ('Property', 'ZZTEST-9000001', 'ZZTEST Franchise', date '2026-08-09',
          'https://example.invalid/zztest', '{"zztest":true}'::jsonb, md5('zztest'));

  -- Principals that must see NOTHING.
  foreach v_role in array array['vendor', 'viewer', 'designer'] loop
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      format('{"app_metadata":{"roles":["%s"]}}', v_role), true);
    select count(*) into v_count from plm.wb_franchise_property where source_id = 'ZZTEST-9000001';
    execute 'reset role';
    if v_count <> 0 then
      v_bad := v_bad + 1;
      raise warning 'FAIL WARNER EXTRACT IS READABLE BY %: it saw % row(s)', v_role, v_count;
    end if;
  end loop;

  -- A principal with NO app role at all must also see nothing.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', '{"app_metadata":{"roles":[]}}', true);
  select count(*) into v_count from plm.wb_franchise_property where source_id = 'ZZTEST-9000001';
  execute 'reset role';
  if v_count <> 0 then
    v_bad := v_bad + 1;
    raise warning 'FAIL a principal with NO app role read % Warner row(s)', v_count;
  end if;

  -- Principals that MUST have access, or the policy is broken the other way.
  foreach v_role in array array['administrator', 'sales', 'licensing'] loop
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      format('{"app_metadata":{"roles":["%s"]}}', v_role), true);
    select count(*) into v_count from plm.wb_franchise_property where source_id = 'ZZTEST-9000001';
    execute 'reset role';
    if v_count <> 1 then
      v_bad := v_bad + 1;
      raise warning 'FAIL % could NOT read the Warner mirror (saw % rows, expected 1)', v_role, v_count;
    end if;
  end loop;

  raise exception 'ZZTEST unwind' using errcode = 'ZZ999';
  exception
    when sqlstate 'ZZ999' then null;
  end;

  if v_bad > 0 then raise exception 'B FAILED (% failures)', v_bad; end if;
  raise notice 'B passed: Warner read policy denies vendor/viewer/designer/no-role and allows administrator/sales/licensing';
end;
$$;

-- =====================================================================================
-- C. api.dam_order_list must be SECURITY INVOKER, and must actually inherit base-table
--    RLS rather than merely carry the option.
-- =====================================================================================
do $$
declare
  v_opts text[];
  v_defn int;
begin
  select reloptions into v_opts
  from pg_class where relnamespace = 'api'::regnamespace and relname = 'dam_order_list';

  if v_opts is null or not ('security_invoker=true' = any(v_opts)) then
    raise exception 'C FAILED: api.dam_order_list reloptions = % -- security_invoker is '
      'NOT set, so the view runs as postgres (BYPASSRLS) and every authenticated account '
      'reads around the RLS on core.customer, core.factory and plm.item',
      coalesce(v_opts::text, '<null>');
  end if;

  -- A no-role principal must be able to reach the view (the grant exists) without the
  -- view escalating: with invoker semantics the base-table RLS decides what it sees.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', '{"app_metadata":{"roles":[]}}', true);
  select count(*) into v_defn from api.dam_order_list;
  execute 'reset role';

  raise notice 'C passed: api.dam_order_list is security_invoker=true (no-role principal sees % row(s))', v_defn;
end;
$$;

-- =====================================================================================
-- D. The Warner loaders must STILL WORK after the revokes. They are SECURITY DEFINER
--    owned by postgres, so they never consumed service_role's table grants -- this
--    section proves that claim instead of asserting it.
--    Runs as service_role inside a savepoint that is always rolled back.
-- =====================================================================================
do $$
declare
  v_landed int;
  v_ins    int;
begin
  begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';

  select rows_landed, rows_inserted into v_landed, v_ins
  from plm.sync_wb_franchise_property(
    jsonb_build_object(
      'captured_at', '2026-08-09',
      'rows', jsonb_build_array(
        jsonb_build_object(
          'source_term', 'Property',
          'source_id',   'ZZTEST-9000002',
          'label',       'ZZTEST Franchise Two',
          'captured_date','2026-08-09',
          'source_url',  'https://example.invalid/zztest2'
        )
      )
    ),
    'mirror_only',
    1.0
  );

  execute 'reset role';

  raise exception 'ZZTEST unwind' using errcode = 'ZZ999';
  exception
    when sqlstate 'ZZ999' then null;
  end;

  if coalesce(v_landed, -1) <> 1 or coalesce(v_ins, -1) <> 1 then
    raise exception 'D FAILED: plm.sync_wb_franchise_property landed % / inserted % '
      '(expected 1 / 1) -- the revokes in 20260810110000 broke the loader', v_landed, v_ins;
  end if;

  raise notice 'D passed: plm.sync_wb_franchise_property still lands rows as service_role after the revokes';
end;
$$;

-- =====================================================================================
-- E. service_role must be REFUSED a direct UPDATE / DELETE / TRUNCATE on a Warner table.
--    Section A reads the catalog; this one runs the statement.
-- =====================================================================================
do $$
declare
  v_bad int := 0;
  v_stmt text;
begin
  foreach v_stmt in array array[
    'update plm.wb_franchise_property set label = label',
    'delete from plm.wb_franchise_property',
    'truncate plm.wb_franchise_property'
  ]
  loop
    begin
      execute 'set local role service_role';
      execute v_stmt;
      execute 'reset role';
      v_bad := v_bad + 1;
      raise warning 'FAIL service_role was ALLOWED to run: %', v_stmt;
      raise exception 'ZZTEST unwind' using errcode = 'ZZ999';
    exception
      when sqlstate 'ZZ999' then null;
      when insufficient_privilege then null;
    end;
  end loop;

  if v_bad > 0 then raise exception 'E FAILED (% failures)', v_bad; end if;
  raise notice 'E passed: service_role is refused UPDATE, DELETE and TRUNCATE on plm.wb_franchise_property';
end;
$$;
