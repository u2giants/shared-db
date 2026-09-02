-- Issue #2094 — contract tests for the six ColdLion MASTER landing tables.
--
-- Migration: 20260902054548_coldlion_master_landing_season_salesperson.sql
--
-- Everything below is invented and rolled back. No fixture depends on a
-- pre-existing row, because CI replays every migration into an EMPTY database
-- and runs this file against that. Every literal is a labelled synthetic value
-- (ZZTEST / ZZ*), never a real company, division, customer, vendor or code.
-- The one real-world literal referenced is the `1P` / `CW001` key collision,
-- which is already published in docs/coldlion-raw-landing-schema-design.md §3.1
-- as the reason the four-part key exists.

begin;

-- =====================================================================================
-- A. All six master tables exist and carry EXACTLY their designed natural key.
--    A collapsed key is the defect this test exists to catch.
-- =====================================================================================
do $$
declare
  v_table  text;
  v_keydef text;
  v_expected constant jsonb := jsonb_build_object(
    'customer',           'PRIMARY KEY (company_code, customer_code)',
    'vendor',             'PRIMARY KEY (company_code, vendor_code)',
    'merch_group_header', 'PRIMARY KEY (company_code, division_code, mg_type_code)',
    'merch_group_detail', 'PRIMARY KEY (company_code, division_code, mg_type_code, mg_code)',
    'season',             'PRIMARY KEY (company_code, division_code, season_code)',
    'salesperson',        'PRIMARY KEY (company_code, salesperson_code)'
  );
begin
  foreach v_table in array array[
    'customer','vendor','merch_group_header','merch_group_detail','season','salesperson'
  ] loop
    if to_regclass('coldlion.' || v_table) is null then
      raise exception 'A FAILED: coldlion.% does not exist', v_table;
    end if;

    select pg_get_constraintdef(oid) into v_keydef
    from pg_constraint
    where conrelid = ('coldlion.' || v_table)::regclass and contype = 'p';

    if v_keydef is distinct from (v_expected ->> v_table) then
      raise exception 'A FAILED: coldlion.% natural key is %, expected %',
        v_table, coalesce(v_keydef, '<none>'), (v_expected ->> v_table);
    end if;
  end loop;

  raise notice 'A PASSED: six master tables, each with its designed natural key.';
end;
$$;

-- =====================================================================================
-- B. The four-part merch-group key BEHAVES. Same mg_code, different mg_type_code,
--    same division = two distinct rows. A three-part key would collapse these and
--    silently lose one. This is the published CW001 `1P` collision.
-- =====================================================================================
do $$
declare
  v_run uuid;
  v_now constant timestamptz := now();
  v_hash_a constant text := repeat('a', 64);
  v_hash_b constant text := repeat('b', 64);
begin
  insert into coldlion.sync_run (endpoint, company_code, requested_by)
  values ('/merchGroupDetails', 'ZZTEST', 'ZZTEST') returning id into v_run;

  insert into coldlion.merch_group_header
    (company_code, division_code, mg_type_code, run_id, fetched_at,
     source_hash, first_seen_at, last_seen_at)
  values
    ('ZZTEST', 'ZZ001', 'Z5', v_run, v_now, v_hash_a, v_now, v_now),
    ('ZZTEST', 'ZZ001', 'Z6', v_run, v_now, v_hash_b, v_now, v_now);

  insert into coldlion.merch_group_detail
    (company_code, division_code, mg_type_code, mg_code, run_id, fetched_at,
     source_hash, first_seen_at, last_seen_at)
  values
    ('ZZTEST', 'ZZ001', 'Z5', 'ZP', v_run, v_now, v_hash_a, v_now, v_now),
    ('ZZTEST', 'ZZ001', 'Z6', 'ZP', v_run, v_now, v_hash_b, v_now, v_now);

  if (select count(*) from coldlion.merch_group_detail
       where company_code = 'ZZTEST' and division_code = 'ZZ001' and mg_code = 'ZP') <> 2 then
    raise exception 'B FAILED: one mg_code under two mg_type_codes did not survive as two rows; the key has collapsed';
  end if;

  -- And the full four-part key is still unique.
  begin
    insert into coldlion.merch_group_detail
      (company_code, division_code, mg_type_code, mg_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZZ001', 'Z5', 'ZP', v_run, v_now, v_hash_a, v_now, v_now);
    raise exception 'B FAILED: the same four-part key was accepted twice';
  exception when unique_violation then null;
  end;

  raise notice 'B PASSED: mg_code collides across types and the four-part key keeps the rows apart.';
end;
$$;

-- =====================================================================================
-- C. season and salesperson: natural key uniqueness, and the landing invariants.
-- =====================================================================================
do $$
declare
  v_run uuid;
  v_now constant timestamptz := now();
  v_hash constant text := repeat('c', 64);
begin
  insert into coldlion.sync_run (endpoint, company_code, requested_by)
  values ('/seasons', 'ZZTEST', 'ZZTEST') returning id into v_run;

  insert into coldlion.season
    (company_code, division_code, season_code, run_id, fetched_at,
     source_hash, first_seen_at, last_seen_at)
  values ('ZZTEST', 'ZZ001', 'ZS1', v_run, v_now, v_hash, v_now, v_now);

  -- The same season code in a DIFFERENT division is a different row: season is
  -- division-scoped, and a two-part key would have merged these.
  insert into coldlion.season
    (company_code, division_code, season_code, run_id, fetched_at,
     source_hash, first_seen_at, last_seen_at)
  values ('ZZTEST', 'ZZ002', 'ZS1', v_run, v_now, v_hash, v_now, v_now);

  if (select count(*) from coldlion.season
       where company_code = 'ZZTEST' and season_code = 'ZS1') <> 2 then
    raise exception 'C FAILED: season is not division-scoped';
  end if;

  begin
    insert into coldlion.season
      (company_code, division_code, season_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZZ001', 'ZS1', v_run, v_now, v_hash, v_now, v_now);
    raise exception 'C FAILED: a duplicate season natural key was accepted';
  exception when unique_violation then null;
  end;

  -- EP001 is excluded from the landing layer.
  begin
    insert into coldlion.season
      (company_code, division_code, season_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'EP001', 'ZS9', v_run, v_now, v_hash, v_now, v_now);
    raise exception 'C FAILED: an EP001 season row was accepted';
  exception when check_violation then null;
  end;

  insert into coldlion.salesperson
    (company_code, salesperson_code, last_name, run_id, fetched_at,
     source_hash, first_seen_at, last_seen_at)
  values ('ZZTEST', 'ZR1', 'ZZTEST-LASTNAME', v_run, v_now, v_hash, v_now, v_now);

  begin
    insert into coldlion.salesperson
      (company_code, salesperson_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZR1', v_run, v_now, v_hash, v_now, v_now);
    raise exception 'C FAILED: a duplicate salesperson natural key was accepted';
  exception when unique_violation then null;
  end;

  raise notice 'C PASSED: season and salesperson enforce their natural keys.';
end;
$$;

-- =====================================================================================
-- D. Landing invariants on the two new tables: one hash algorithm, sightings
--    ordered, and every row traceable to the run that saw it.
-- =====================================================================================
do $$
declare
  v_run uuid;
  v_now constant timestamptz := now();
  v_hash constant text := repeat('d', 64);
begin
  insert into coldlion.sync_run (endpoint, company_code, requested_by)
  values ('/salespersons', 'ZZTEST', 'ZZTEST') returning id into v_run;

  -- One hash algorithm across the schema: an md5 is not a SHA-256.
  begin
    insert into coldlion.salesperson
      (company_code, salesperson_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZR2', v_run, v_now, md5('ZZTEST'), v_now, v_now);
    raise exception 'D FAILED: a non-SHA-256 source_hash was accepted on salesperson';
  exception when check_violation then null;
  end;

  begin
    insert into coldlion.season
      (company_code, division_code, season_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZZ003', 'ZS2', v_run, v_now, md5('ZZTEST'), v_now, v_now);
    raise exception 'D FAILED: a non-SHA-256 source_hash was accepted on season';
  exception when check_violation then null;
  end;

  -- last_seen_at can never precede first_seen_at.
  begin
    insert into coldlion.season
      (company_code, division_code, season_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZZ003', 'ZS3', v_run, v_now, v_hash, v_now, v_now - interval '1 day');
    raise exception 'D FAILED: last_seen_at was allowed to precede first_seen_at on season';
  exception when check_violation then null;
  end;

  begin
    insert into coldlion.salesperson
      (company_code, salesperson_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZR3', v_run, v_now, v_hash, v_now, v_now - interval '1 day');
    raise exception 'D FAILED: last_seen_at was allowed to precede first_seen_at on salesperson';
  exception when check_violation then null;
  end;

  -- Every landed row names the run that produced it.
  begin
    insert into coldlion.salesperson
      (company_code, salesperson_code, run_id, fetched_at,
       source_hash, first_seen_at, last_seen_at)
    values ('ZZTEST', 'ZR4', '00000000-0000-0000-0000-000000000000'::uuid,
            v_now, v_hash, v_now, v_now);
    raise exception 'D FAILED: a salesperson row was landed against a run that does not exist';
  exception when foreign_key_violation then null;
  end;

  raise notice 'D PASSED: one hash algorithm, ordered sightings, run-traceable rows.';
end;
$$;

-- =====================================================================================
-- E. The common landing columns are present on all six master tables, and no
--    per-row `raw` archive leaked back in (owner decision D5).
-- =====================================================================================
do $$
declare
  v_missing text;
begin
  select string_agg(format('%s.%s', t.name, c.needed), ', ')
    into v_missing
  from unnest(array['customer','vendor','merch_group_header','merch_group_detail',
                    'season','salesperson']) as t(name)
  cross join unnest(array['run_id','fetched_at','source_hash',
                          'first_seen_at','last_seen_at']) as c(needed)
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'coldlion' and table_name = t.name and column_name = c.needed
  );

  if v_missing is not null then
    raise exception 'E FAILED: missing common landing column(s): %', v_missing;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'coldlion'
      and table_name in ('customer','vendor','merch_group_header','merch_group_detail',
                         'season','salesperson')
      and column_name = 'raw'
  ) then
    raise exception 'E FAILED: D5 violated — a master landing table carries a raw column';
  end if;

  raise notice 'E PASSED: common landing columns present on all six, no raw archive.';
end;
$$;

-- =====================================================================================
-- F. No interpretation. No resolution/matching columns and no invented curated
--    flag on the six master tables. ColdLion's own `active` field is permitted
--    where ColdLion returns it (owner decision D4); `is_active` / `active_flag`
--    are ours and are forbidden here.
-- =====================================================================================
do $$
declare
  v_offenders text;
begin
  select string_agg(format('%s.%s', table_name, column_name), ', ')
    into v_offenders
  from information_schema.columns
  where table_schema = 'coldlion'
    and table_name in ('customer','vendor','merch_group_header','merch_group_detail',
                       'season','salesperson')
    and (column_name in ('resolution_status','resolved_by','resolved_at','match_status',
                         'licensor_id','property_id','core_id','is_active','active_flag',
                         'parent_licensor_code')
         or column_name like 'resolved%'
         or column_name like 'match_%');

  if v_offenders is not null then
    raise exception 'F FAILED: the landing layer carries curation or invented structure: %', v_offenders;
  end if;

  raise notice 'F PASSED: no resolution, matching or invented curated columns.';
end;
$$;

-- =====================================================================================
-- G. No foreign key leaves the coldlion schema, and none reaches core.*.
-- =====================================================================================
do $$
declare
  v_offenders text;
begin
  select string_agg(format('%s -> %s', con.conrelid::regclass, con.confrelid::regclass), ', ')
    into v_offenders
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_class fc on fc.oid = con.confrelid
  join pg_namespace fn on fn.oid = fc.relnamespace
  where con.contype = 'f' and n.nspname = 'coldlion' and fn.nspname <> 'coldlion';

  if v_offenders is not null then
    raise exception 'G FAILED: a coldlion foreign key points outside the schema: %', v_offenders;
  end if;

  raise notice 'G PASSED: no foreign key leaves coldlion.';
end;
$$;

-- =====================================================================================
-- H. Security posture. This is a raw landing layer: RLS on, NO policy (closed,
--    not row-filtered), no grant to PUBLIC, anon or authenticated, and the
--    loader role can write.
-- =====================================================================================
do $$
declare
  v_table text;
  v_role  text;
  v_priv  text;
begin
  if has_schema_privilege('anon', 'coldlion', 'USAGE')
     or has_schema_privilege('authenticated', 'coldlion', 'USAGE') then
    raise exception 'H FAILED: an application role holds USAGE on schema coldlion';
  end if;

  foreach v_table in array array[
    'customer','vendor','merch_group_header','merch_group_detail','season','salesperson'
  ] loop
    if not (select relrowsecurity from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'coldlion' and c.relname = v_table) then
      raise exception 'H FAILED: RLS is not enabled on coldlion.%', v_table;
    end if;

    if exists (select 1 from pg_policies
               where schemaname = 'coldlion' and tablename = v_table) then
      raise exception 'H FAILED: coldlion.% carries an RLS policy; this layer is closed, not filtered', v_table;
    end if;

    foreach v_role in array array['anon','authenticated'] loop
      foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE'] loop
        if has_table_privilege(v_role, format('coldlion.%I', v_table), v_priv) then
          raise exception 'H FAILED: % holds % on coldlion.%', v_role, v_priv, v_table;
        end if;
      end loop;
    end loop;

    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      where n.nspname = 'coldlion' and c.relname = v_table and a.grantee = 0
    ) then
      raise exception 'H FAILED: coldlion.% carries a grant to PUBLIC', v_table;
    end if;

    foreach v_priv in array array['SELECT','INSERT','UPDATE'] loop
      if not has_table_privilege('service_role', format('coldlion.%I', v_table), v_priv) then
        raise exception 'H FAILED: service_role lacks % on coldlion.%', v_priv, v_table;
      end if;
    end loop;
  end loop;

  raise notice 'H PASSED: RLS on, no policies, no application grants, loader can write.';
end;
$$;

-- =====================================================================================
-- I. The two new tables are documented as landing tables closed to applications.
-- =====================================================================================
do $$
declare
  v_table   text;
  v_comment text;
begin
  foreach v_table in array array['season','salesperson'] loop
    select obj_description(('coldlion.' || v_table)::regclass, 'pg_class') into v_comment;
    if v_comment is null or v_comment not ilike '%no grants to application roles%' then
      raise exception 'I FAILED: coldlion.% does not document the landing-layer contract: %',
        v_table, coalesce(v_comment, '<none>');
    end if;

    select col_description(('coldlion.' || v_table)::regclass,
             (select ordinal_position from information_schema.columns
               where table_schema = 'coldlion' and table_name = v_table
                 and column_name = 'source_hash')::int)
      into v_comment;
    if v_comment is null or v_comment not ilike '%before projection%' then
      raise exception 'I FAILED: coldlion.%.source_hash does not record that it covers the COMPLETE fetched record before projection', v_table;
    end if;
  end loop;

  raise notice 'I PASSED: the new landing tables carry their contract in the catalog.';
end;
$$;

rollback;
