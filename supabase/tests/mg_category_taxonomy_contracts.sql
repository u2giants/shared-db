-- =====================================================================================
-- Issue #1163 contract tests — core.mg_category / core.mg_category_merch_group.
--
-- HOW TO RUN
--   Against PREVIEW ONLY, as a role that can read core.* and write these two tables
--   (the Supabase CLI's linked connection, or a psql / node-pg session):
--       \i supabase/tests/mg_category_taxonomy_contracts.sql
--
--   Run each `do $$ ... $$;` block as its own statement. Submitting the whole file as a
--   single multi-statement batch through the transaction pooler (port 6543) wraps the
--   blocks in one implicit transaction and can stall.
--
-- WHAT IT ASSERTS
--   A. The objects exist, with the constraint that makes acceptance check 3 real.
--   B. The seven categories exist exactly once each (acceptance check 1).
--   C. All 19 authoritative category-to-MG01 mappings resolve to the right category, in
--      EVERY division that carries the product type (acceptance checks 2, 4, 6).
--   D. Negative cases (acceptance check 6): a duplicate mapping is REJECTED, a mapping to
--      a non-existent merchandise-group row is REJECTED, a mapping to a non-existent
--      category is REJECTED, and a blank category code is REJECTED.
--   E. The documented read contract returns category + MG01 code + MG01 product-type name
--      for all 19 product types (acceptance check 5).
--
--   No assertion reads supabase_migrations.schema_migrations. This repo has shipped a
--   migration that recorded a clean ledger row while its object did nothing, so "it
--   applied" is not accepted here as evidence of anything.
--
-- SIDE EFFECTS
--   Section D inserts deliberately invalid rows inside SAVEPOINT-free sub-blocks that
--   catch the exception, and the one row it does insert successfully is deleted again in
--   the same block. Nothing survives the run.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- A + B + C + E
-- -------------------------------------------------------------------------------------
do $$
declare
  v_pass integer := 0;
  v_fail integer := 0;
  v_n    integer;
  v_txt  text;
  r      record;
begin
  raise notice '=== A. OBJECT EXISTENCE ===';
  foreach v_txt in array array['core.mg_category', 'core.mg_category_merch_group'] loop
    if to_regclass(v_txt) is null then
      v_fail := v_fail + 1; raise notice 'FAIL table missing: %', v_txt;
    else
      v_pass := v_pass + 1; raise notice 'PASS table exists: % (oid %)', v_txt, to_regclass(v_txt)::oid;
    end if;
  end loop;

  -- The constraint IS acceptance check 3. If it is absent the whole design is decorative.
  select count(*) into v_n
  from pg_constraint
  where conname = 'mg_category_merch_group_one_category_per_product_type'
    and conrelid = 'core.mg_category_merch_group'::regclass
    and contype = 'u';
  if v_n = 1 then
    v_pass := v_pass + 1;
    raise notice 'PASS unique constraint on merch_group_mg_id exists (one category per product type)';
  else
    v_fail := v_fail + 1;
    raise notice 'FAIL unique constraint mg_category_merch_group_one_category_per_product_type missing';
  end if;

  -- The link must be a real foreign key onto the merchandise-group row identity.
  select count(*) into v_n
  from pg_constraint
  where conrelid = 'core.mg_category_merch_group'::regclass
    and contype = 'f'
    and confrelid = 'core."merchGroup"'::regclass;
  if v_n = 1 then
    v_pass := v_pass + 1; raise notice 'PASS foreign key to core."merchGroup"(mg_id) exists';
  else
    v_fail := v_fail + 1; raise notice 'FAIL no foreign key from mg_category_merch_group to core."merchGroup"';
  end if;

  -- RLS must be on, and anon/public must have nothing.
  foreach v_txt in array array['mg_category', 'mg_category_merch_group'] loop
    select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'core' and c.relname = v_txt and c.relrowsecurity;
    if v_n = 1 then
      v_pass := v_pass + 1; raise notice 'PASS RLS enabled on core.%', v_txt;
    else
      v_fail := v_fail + 1; raise notice 'FAIL RLS NOT enabled on core.%', v_txt;
    end if;

    if has_table_privilege('anon', 'core.' || quote_ident(v_txt), 'SELECT') then
      v_fail := v_fail + 1; raise notice 'FAIL anon can SELECT core.%', v_txt;
    else
      v_pass := v_pass + 1; raise notice 'PASS anon cannot SELECT core.%', v_txt;
    end if;
  end loop;

  raise notice '=== B. THE SEVEN CATEGORIES EXIST EXACTLY ONCE (acceptance check 1) ===';
  foreach v_txt in array array['WALL','TABLETOP','CLOCK','STORAGE','WORKSPACE','FLOOR','GARDEN'] loop
    select count(*) into v_n from core.mg_category where code = v_txt;
    if v_n = 1 then
      v_pass := v_pass + 1; raise notice 'PASS category % exists exactly once', v_txt;
    else
      v_fail := v_fail + 1; raise notice 'FAIL category % found % times', v_txt, v_n;
    end if;
  end loop;

  select count(*) into v_n from core.mg_category;
  if v_n = 7 then
    v_pass := v_pass + 1; raise notice 'PASS exactly 7 categories total';
  else
    v_fail := v_fail + 1; raise notice 'FAIL expected 7 categories, found %', v_n;
  end if;

  raise notice '=== C. ALL 19 CATEGORY-TO-MG01 MAPPINGS (acceptance checks 2, 4, 6) ===';
  for r in
    with authoritative (mg_code, mg_desc, category_code) as (
      values
        ('A','Stretched/Box','WALL'),('B','Framed','WALL'),('C','Plaque','WALL'),
        ('D','Functional','WALL'),('E','Other Wall','WALL'),
        ('F','Block','TABLETOP'),('G','Box','TABLETOP'),('H','Photo Frames','TABLETOP'),
        ('J','Object','TABLETOP'),('K','Other tabletop','TABLETOP'),
        ('M','Clocks','CLOCK'),
        ('N','Soft storage','STORAGE'),('P','Hard storage','STORAGE'),
        ('R','Other storage','STORAGE'),
        ('S','Stationery org','WORKSPACE'),('T','Desk acc','WORKSPACE'),
        ('U','Other workspace','WORKSPACE'),
        ('V','Floor coverings','FLOOR'),
        ('W','Garden','GARDEN')
    )
    select
      a.mg_code,
      a.mg_desc,
      a.category_code,
      count(mg.mg_id)                                                as mg_rows,
      count(l.id)                                                    as linked_rows,
      count(distinct mg."divisionCode_id_fk")                        as divisions,
      count(distinct c.code)                                         as distinct_categories,
      coalesce(min(c.code), '(none)')                                as actual_category
    from authoritative a
    left join core."merchGroup" mg
      on mg."mgTypeCode" = '01'
     and upper(btrim(mg.mg_code)) = upper(a.mg_code)
     and lower(btrim(mg.mg_desc)) = lower(a.mg_desc)
    left join core.mg_category_merch_group l on l.merch_group_mg_id = mg.mg_id
    left join core.mg_category c on c.id = l.mg_category_id
    group by a.mg_code, a.mg_desc, a.category_code
    order by a.mg_code
  loop
    if r.mg_rows = 0 then
      v_fail := v_fail + 1;
      raise notice 'FAIL % % — no MG01 merchandise-group row resolved at all', r.mg_code, r.mg_desc;
    elsif r.linked_rows <> r.mg_rows then
      -- acceptance check 4: EVERY division-specific row must be linked, not just one.
      v_fail := v_fail + 1;
      raise notice 'FAIL % % — % MG01 rows across % divisions but only % linked',
        r.mg_code, r.mg_desc, r.mg_rows, r.divisions, r.linked_rows;
    elsif r.distinct_categories <> 1 or r.actual_category <> r.category_code then
      v_fail := v_fail + 1;
      raise notice 'FAIL % % — expected category %, got % (% distinct)',
        r.mg_code, r.mg_desc, r.category_code, r.actual_category, r.distinct_categories;
    else
      v_pass := v_pass + 1;
      raise notice 'PASS % % -> % (% rows across % divisions)',
        r.mg_code, r.mg_desc, r.category_code, r.linked_rows, r.divisions;
    end if;
  end loop;

  -- The whole point of the unique constraint, restated as data: no product-type row may
  -- appear under two categories.
  select count(*) into v_n
  from (
    select merch_group_mg_id
    from core.mg_category_merch_group
    group by merch_group_mg_id
    having count(distinct mg_category_id) > 1
  ) d;
  if v_n = 0 then
    v_pass := v_pass + 1; raise notice 'PASS no product type belongs to two categories';
  else
    v_fail := v_fail + 1; raise notice 'FAIL % product types belong to more than one category', v_n;
  end if;

  -- Nothing may be linked to an MG row that is not MG01.
  select count(*) into v_n
  from core.mg_category_merch_group l
  join core."merchGroup" mg on mg.mg_id = l.merch_group_mg_id
  where coalesce(mg."mgTypeCode", '') <> '01';
  if v_n = 0 then
    v_pass := v_pass + 1; raise notice 'PASS every linked merchandise-group row is mgTypeCode 01';
  else
    v_fail := v_fail + 1; raise notice 'FAIL % linked rows are not mgTypeCode 01', v_n;
  end if;

  raise notice '=== E. READ CONTRACT (acceptance check 5) ===';
  select count(distinct (category_code, mg01_code, mg01_product_type)) into v_n
  from (
    select
      cat.code   as category_code,
      mg.mg_code as mg01_code,
      mg.mg_desc as mg01_product_type
    from core.mg_category_merch_group link
    join core.mg_category cat on cat.id = link.mg_category_id
    join core."merchGroup" mg  on mg.mg_id = link.merch_group_mg_id
    where cat.is_active
  ) contract;
  if v_n = 19 then
    v_pass := v_pass + 1;
    raise notice 'PASS read contract yields exactly 19 distinct category/MG01 code/product-type triples';
  else
    v_fail := v_fail + 1;
    raise notice 'FAIL read contract yielded % distinct triples, expected 19', v_n;
  end if;

  raise notice '--- % passed / % failed ---', v_pass, v_fail;
  if v_fail > 0 then
    raise exception 'Issue #1163 contract tests FAILED: % failures', v_fail;
  end if;
end;
$$;

-- -------------------------------------------------------------------------------------
-- D. NEGATIVE CASES — invalid and duplicate mappings must be REJECTED.
--    Each attempt is expected to raise; if it does NOT raise, that is the failure.
-- -------------------------------------------------------------------------------------
do $$
declare
  v_pass integer := 0;
  v_fail integer := 0;
  v_cat_wall uuid;
  v_cat_clock uuid;
  v_existing integer;
  v_spare integer;
  v_new uuid;
begin
  select id into v_cat_wall  from core.mg_category where code = 'WALL';
  select id into v_cat_clock from core.mg_category where code = 'CLOCK';

  -- An already-mapped MG01 row (code A, Stretched/Box, any division).
  select l.merch_group_mg_id into v_existing
  from core.mg_category_merch_group l
  join core."merchGroup" mg on mg.mg_id = l.merch_group_mg_id
  where mg."mgTypeCode" = '01' and upper(btrim(mg.mg_code)) = 'A'
  limit 1;

  -- D1: same product type, a SECOND category -> must be rejected.
  begin
    insert into core.mg_category_merch_group (mg_category_id, merch_group_mg_id)
    values (v_cat_clock, v_existing);
    v_fail := v_fail + 1;
    raise notice 'FAIL D1: a product type was allowed into a second category';
    delete from core.mg_category_merch_group
      where mg_category_id = v_cat_clock and merch_group_mg_id = v_existing;
  exception when unique_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D1: second category for the same product type rejected (unique_violation)';
  end;

  -- D2: exact duplicate of an existing mapping -> must be rejected.
  begin
    insert into core.mg_category_merch_group (mg_category_id, merch_group_mg_id)
    values (v_cat_wall, v_existing);
    v_fail := v_fail + 1;
    raise notice 'FAIL D2: duplicate mapping was accepted';
  exception when unique_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D2: duplicate mapping rejected (unique_violation)';
  end;

  -- D3: mapping to a merchandise-group row that does not exist -> must be rejected.
  begin
    insert into core.mg_category_merch_group (mg_category_id, merch_group_mg_id)
    values (v_cat_wall, -987654321);
    v_fail := v_fail + 1;
    raise notice 'FAIL D3: mapping to a non-existent merchandise-group row was accepted';
    delete from core.mg_category_merch_group where merch_group_mg_id = -987654321;
  exception when foreign_key_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D3: mapping to a non-existent merchandise-group row rejected';
  end;

  -- D4: mapping to a category that does not exist -> must be rejected.
  select mg_id into v_spare
  from core."merchGroup" mg
  where mg."mgTypeCode" = '01'
    and not exists (
      select 1 from core.mg_category_merch_group l where l.merch_group_mg_id = mg.mg_id
    )
  limit 1;
  begin
    insert into core.mg_category_merch_group (mg_category_id, merch_group_mg_id)
    values ('00000000-0000-0000-0000-000000000000'::uuid, v_spare);
    v_fail := v_fail + 1;
    raise notice 'FAIL D4: mapping to a non-existent category was accepted';
    delete from core.mg_category_merch_group where merch_group_mg_id = v_spare;
  exception when foreign_key_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D4: mapping to a non-existent category rejected';
  end;

  -- D5: a blank category code -> must be rejected.
  begin
    insert into core.mg_category (code, name) values ('   ', 'Blank code');
    v_fail := v_fail + 1;
    raise notice 'FAIL D5: a blank category code was accepted';
    delete from core.mg_category where name = 'Blank code';
  exception when check_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D5: blank category code rejected';
  end;

  -- D6: a duplicate category code -> must be rejected.
  begin
    insert into core.mg_category (code, name) values ('WALL', 'Wall again');
    v_fail := v_fail + 1;
    raise notice 'FAIL D6: a duplicate category code was accepted';
    delete from core.mg_category where name = 'Wall again';
  exception when unique_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D6: duplicate category code rejected';
  end;

  -- D7: a duplicate category NAME differing only by case -> must be rejected.
  begin
    insert into core.mg_category (code, name) values ('WALL_ALT', ' wall ');
    v_fail := v_fail + 1;
    raise notice 'FAIL D7: a case/whitespace-variant duplicate category name was accepted';
    delete from core.mg_category where code = 'WALL_ALT';
  exception when unique_violation then
    v_pass := v_pass + 1;
    raise notice 'PASS D7: case/whitespace-variant duplicate category name rejected';
  end;

  raise notice '--- % passed / % failed ---', v_pass, v_fail;
  if v_fail > 0 then
    raise exception 'Issue #1163 negative-case tests FAILED: % failures', v_fail;
  end if;
end;
$$;
