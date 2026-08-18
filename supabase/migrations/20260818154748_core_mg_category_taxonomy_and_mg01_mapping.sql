-- =====================================================================================
-- Issue #1163 — normalized `mgCategory` taxonomy and its MG01 product-type mapping.
--
-- ADDITIVE ONLY. Creates exactly two new tables in `core`:
--     core.mg_category
--     core.mg_category_merch_group
-- Nothing else is created, altered, dropped or repurposed. In particular the existing
-- free-text `mgCategory` columns on core."merchGroup" and core."merchGroupMaster" are
-- LEFT EXACTLY AS THEY ARE. They stay as an upstream mirror field; this migration does
-- not read them as truth, does not write them, and does not deprecate them.
--
-- THE BUSINESS RULE (docs/merch-group-taxonomy-architecture.md §4.2.1)
-- --------------------------------------------------------------------
--   * `mgCategory` is a HIDDEN grouping ABOVE MG01. It is not an MG level, not a row in
--     the MG01 -> MG02 -> MG03 `parent_id` chain, and not a product type.
--   * One category has MANY MG01 product types.
--   * Each MG01 product type belongs to EXACTLY ONE category.
--   * An item's category is INHERITED from its selected MG01 product type.
--   * MG02 and MG03 refine the product type; they never choose or override the category.
--
-- WHY THE LINK IS TO `mg_id` AND NOT TO THE MG01 LETTER CODE
-- ----------------------------------------------------------
-- AGENTS.md and §3.2c of the taxonomy doc warn that MG codes are unique only per
-- division+type. That was PROVEN live against production qsllyeztdwjgirsysgai on
-- 2026-08-18 (read-only), not assumed:
--
--   select mg_code, count(*), count(distinct "divisionCode_id_fk")
--   from core."merchGroup" where "mgTypeCode" = '01' group by 1 having count(*) > 1;
--     -> 'A' 7 rows across 4 divisions, 'B' 7/4, 'S' 7/4, 'C','D','E','F','G','J','K',
--        'M','P','R','U','V','W' 6 rows each across 4 divisions ... 26 colliding codes.
--
--   select mg_code, count(*), count(distinct "mgTypeCode")
--   from core."merchGroup" where mg_code in ('A','B','F','M','W') group by 1;
--     -> each of those letters exists 22-25 times across 5 DIFFERENT mgTypeCodes.
--
-- Worse, the collision is semantic, not cosmetic: inside mgTypeCode '01' alone, mg_id 26
-- is code 'A' = "LEATHER/COWHIDE" (a retired MATERIAL list) while mg_id 2462 is code 'A'
-- = "Stretched/Box" (the live PRODUCT TYPE). A category table keyed on the bare letter
-- 'A' would silently claim both. So `core.mg_category_merch_group` links to
-- core."merchGroup"(mg_id) — the real row identity, which already carries company and
-- division scope — via a real foreign key.
--
--   select conname, pg_get_constraintdef(oid) ... -> merchGroup_pkey PRIMARY KEY (mg_id)
--
-- HOW THE SEED RESOLVES ROWS
-- --------------------------
-- The authoritative 7-category / 19-product-type mapping comes from
-- MerchGroup_Rework.xlsx sheet `Final Version`, columns A-C, restated in §4.2.1. The seed
-- matches on the (mg_code, mg_desc) PAIR within mgTypeCode '01', case-insensitively and
-- trimmed. Matching on the pair is what keeps the retired material rows out: 'A' alone
-- would hit "LEATHER/COWHIDE", but ('A','Stretched/Box') cannot.
--
-- Every division that carries a matching row gets its own link row, so the mapping is
-- correct per company/division rather than approximated once globally.
--
-- ONLY `is_active` MERCHANDISE-GROUP ROWS ARE MATCHED
-- ---------------------------------------------------
-- Verified live on 2026-08-18 against production qsllyeztdwjgirsysgai (read-only): every
-- pre-rebuild MG01 row is `is_active = false`, and the whole live product-type set was
-- created in one later batch with `is_active = true`. Today an unfiltered join happens to
-- be safe, because the surviving retired type-01 'A' row reads LEATHER/COWHIDE and cannot
-- match the pair ('A','Stretched/Box'). It is not safe FOREVER: a future rebuild that
-- retires a product type by name and re-inserts the SAME name would leave two rows with
-- the same (mg_code, mg_desc) pair, and an unfiltered seed would silently link BOTH — two
-- link rows for one live product type, with nothing raising. So the seed, the "is there
-- any source data" gate and the verification block ALL filter on `is_active is true`, and
-- they all use the SAME filter so the gate can never disagree with the join.
--
-- `is_active` is nullable on core."merchGroup" (its default is false), so `is true` is
-- deliberate: an unknown activity flag is NOT treated as live. If a genuinely live product
-- type is ever left with a null flag, the per-division assertion below names it and the
-- migration refuses to apply — loud, not silent.
--
-- THE EXPECTED SHAPE IS DERIVED, NOT HARD-CODED
-- ---------------------------------------------
-- Measured live on 2026-08-18: divisions CW001, EH001 and SP001 each carry all 19
-- authoritative product types as active MG01 rows, i.e. 57 link rows today. 57 is an
-- OBSERVATION and appears nowhere in the code. What the assertion actually requires is the
-- SHAPE: for EVERY division that carries any active MG01 row, EVERY one of the 19
-- authoritative product types must resolve IN THAT DIVISION and carry its authoritative
-- category. The expected link count is then derived as 19 x (number of such divisions).
--
-- WHY PER-DIVISION AND NOT "RESOLVED SOMEWHERE" (this is the bug that was here before)
-- -----------------------------------------------------------------------------------
-- The previous check LEFT JOINed the 19 authoritative rows to core."merchGroup" and
-- failed only when a row came back NULL. A LEFT JOIN emits NO ROW for a division that did
-- not match — it does not emit a NULL row. So if 'K' matched in CW001 and SP001 but EH001
-- stored it as 'Other Table Top', the join still returned two non-null rows for 'K',
-- nothing was NULL, the migration printed OK and COMMITTED 56 links instead of 57. One
-- division silently had a hole and every downstream category filter silently dropped its
-- items. Cross-joining the authoritative list against the division list first is what
-- makes a one-division drift impossible to hide.
--
-- CAN A DIVISION LEGITIMATELY CARRY ONLY PART OF THE MG01 SET?
-- -----------------------------------------------------------
-- Decision: NO, and that is asserted rather than assumed. The 19 product types are the
-- company-wide product vocabulary, not a per-division menu; production carries all 19 in
-- all three divisions that have any active MG01 rows at all. A division that carries a
-- PARTIAL set is therefore treated as a data defect and raises with the exact missing
-- (division, code, description) triples. A future division that deliberately sells only a
-- subset must be settled on the issue and expressed in a follow-up governed migration; it
-- must NOT be accommodated by loosening this check, because "some divisions are allowed to
-- be short" is exactly the hole that let the 56-of-57 seed through.
--
-- CODE 'Q' — "TBD storage" — IS DELIBERATELY NOT MAPPED
-- -----------------------------------------------------
-- Production also carries an MG01 row 'Q' "TBD storage" whose free-text `mgCategory`
-- reads 'Storage'. It is NOT in the workbook's 19 and it is inactive in two of the three
-- divisions. Inventing a mapping for it here would be this migration deciding a business
-- question it was not asked. It is left unmapped and visible: the read contract simply
-- returns no category for it, which is honest, and a later governed change can add it.
--
-- WHAT APPLIES ON A DATABASE WITH NO MERCHANDISE-GROUP ROWS
-- ---------------------------------------------------------
-- EVERYTHING STRUCTURAL: both tables, every constraint and index, RLS, the policies and
-- the grants, plus the seven authoritative categories (they are division-independent
-- reference data and do not depend on any source row). Only the 19 category-to-MG01
-- LINK rows need source data, so on a database with no MG01 rows the link seed is a
-- natural no-op and its assertion is SKIPPED WITH A LOUD NOTICE rather than raising.
-- On a database that DOES carry active MG01 rows the assertion is strict PER DIVISION:
-- anything short of all 19 resolving in EVERY division that carries active MG01 rows
-- raises and rolls back, naming the exact missing (division, code, description) triples.
-- See the long comment in section 5.

-- IDEMPOTENCE
-- -----------
-- Re-runnable. Tables are `create table if not exists`; the category seed upserts on the
-- natural key `code`; the link seed is `on conflict do nothing`. A re-run can therefore
-- never silently RE-POINT a product type that a human deliberately moved. Instead, the
-- final verification block RAISES if any existing link disagrees with the authoritative
-- mapping, so a drift is loud rather than quietly overwritten.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. core.mg_category — the seven categories.
-- -------------------------------------------------------------------------------------

create table if not exists core.mg_category (
  id uuid primary key default gen_random_uuid(),

  -- Stable machine key. This, not the display name, is what application code and later
  -- migrations should reference; the display name is allowed to be re-worded.
  code text not null,

  -- What a human sees if the grouping is ever surfaced. The workbook labels this column
  -- "Prod Category- (no one sees this)", so today it is internal.
  name text not null,

  -- Presentation order for pickers and reports. Not a hierarchy.
  sort_order integer not null default 0,

  is_active boolean not null default true,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint mg_category_code_not_blank check (length(btrim(code)) > 0),
  constraint mg_category_name_not_blank check (length(btrim(name)) > 0)
);

create unique index if not exists mg_category_code_key
  on core.mg_category (code);

create unique index if not exists mg_category_name_key
  on core.mg_category (lower(btrim(name)));

comment on table core.mg_category is
  'Issue #1163. The normalized `mgCategory` list: a hidden product grouping ABOVE MG01, '
  'used to constrain downstream logic such as valid sizes. It is NOT an MG hierarchy '
  'level and NOT a product type. Authoritative rule: '
  'docs/merch-group-taxonomy-architecture.md §4.2.1. The free-text `mgCategory` columns '
  'on core."merchGroup" / core."merchGroupMaster" are an upstream mirror, not the master.';

comment on column core.mg_category.code is
  'Stable machine key (WALL, TABLETOP, CLOCK, STORAGE, WORKSPACE, FLOOR, GARDEN). '
  'Reference this, never the display name.';

comment on column core.mg_category.sort_order is
  'Display ordering only. Carries no hierarchy or business meaning.';

-- -------------------------------------------------------------------------------------
-- 2. core.mg_category_merch_group — category -> real MG01 merchandise-group rows.
-- -------------------------------------------------------------------------------------

create table if not exists core.mg_category_merch_group (
  id uuid primary key default gen_random_uuid(),

  mg_category_id uuid not null
    references core.mg_category (id) on delete restrict,

  -- The REAL merchandise-group row identity. Company and division scope ride along on
  -- that row, so this link is division-correct by construction. Never a bare mg_code:
  -- MG codes collide across divisions AND across mgTypeCodes (see header).
  merch_group_mg_id integer not null
    references core."merchGroup" (mg_id) on delete cascade,

  -- Provenance, so a future reader can tell a seeded row from a hand-added one.
  source text not null default 'merchgroup_rework_workbook',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- ACCEPTANCE CHECK 3, enforced by the database rather than by convention:
  -- one merchandise-group ROW can belong to AT MOST ONE category. A second insert for
  -- the same mg_id fails outright.
  --
  -- THE NAME SAYS "MG ROW", NOT "PRODUCT TYPE", ON PURPOSE. A product type such as
  -- ('A','Stretched/Box') exists as a SEPARATE ROW in each division, so this constraint
  -- does NOT stop CW001's 'A' being WALL while EH001's 'A' is CLOCK. Naming it
  -- "one_category_per_product_type" promised a rule it cannot deliver. Postgres cannot
  -- express the cross-division rule as a CHECK (a CHECK may not query another table) and
  -- expressing it would need a trigger or a unique index on core."merchGroup", both of
  -- which are objects outside this change's claim. So the cross-division rule is enforced
  -- by the SEED (one authoritative category per (mg_code, mg_desc) pair, applied to every
  -- division), by the per-division verification in section 5, and by section C of
  -- supabase/tests/mg_category_taxonomy_contracts.sql — and the constraint is named and
  -- commented for exactly what it does enforce, nothing more.
  constraint mg_category_merch_group_one_category_per_mg_row
    unique (merch_group_mg_id)
);

create index if not exists mg_category_merch_group_category_idx
  on core.mg_category_merch_group (mg_category_id);

comment on table core.mg_category_merch_group is
  'Issue #1163. Category -> MG01 product type. One category has many MG01 rows; each MG01 '
  'ROW has at most one category (enforced by the unique constraint on merch_group_mg_id; '
  'the cross-division rule that the SAME product type carries the same category in every '
  'division is enforced by the seed and by the contract tests, not by that constraint). '
  'Links to core."merchGroup"(mg_id), NOT to the MG01 letter code: codes are unique only '
  'per division+type and collide semantically (mg_id 26 = ''A'' LEATHER/COWHIDE vs '
  'mg_id 2462 = ''A'' Stretched/Box, both mgTypeCode ''01'').';

comment on column core.mg_category_merch_group.merch_group_mg_id is
  'core."merchGroup".mg_id. Company/division scope is inherited from that row.';

comment on constraint mg_category_merch_group_one_category_per_mg_row
  on core.mg_category_merch_group is
  'Issue #1163 acceptance check 3: ONE merchandise-group ROW cannot belong to two '
  'categories. It does NOT constrain the same product type across divisions, and it does '
  'NOT constrain the linked row to mgTypeCode ''01'' — a CHECK cannot query another table, '
  'and both of those would need an object outside this change''s claim. Section 5 of the '
  'migration and the contract tests cover them.';

-- -------------------------------------------------------------------------------------
-- 3. Structural seed — the seven categories.
-- -------------------------------------------------------------------------------------

insert into core.mg_category (code, name, sort_order)
values
  ('WALL',      'Wall',      10),
  ('TABLETOP',  'Tabletop',  20),
  ('CLOCK',     'Clock',     30),
  ('STORAGE',   'Storage',   40),
  ('WORKSPACE', 'Workspace', 50),
  ('FLOOR',     'Floor',     60),
  ('GARDEN',    'Garden',    70)
on conflict (code) do update
  set name       = excluded.name,
      sort_order = excluded.sort_order,
      updated_at = now();

-- -------------------------------------------------------------------------------------
-- 4. Structural seed — the 19 category-to-MG01 mappings, resolved per division.
-- -------------------------------------------------------------------------------------

with authoritative (mg_code, mg_desc, category_code) as (
  values
    -- Wall
    ('A', 'Stretched/Box',   'WALL'),
    ('B', 'Framed',          'WALL'),
    ('C', 'Plaque',          'WALL'),
    ('D', 'Functional',      'WALL'),
    ('E', 'Other Wall',      'WALL'),
    -- Tabletop
    ('F', 'Block',           'TABLETOP'),
    ('G', 'Box',             'TABLETOP'),
    ('H', 'Photo Frames',    'TABLETOP'),
    ('J', 'Object',          'TABLETOP'),
    ('K', 'Other tabletop',  'TABLETOP'),
    -- Clock
    ('M', 'Clocks',          'CLOCK'),
    -- Storage
    ('N', 'Soft storage',    'STORAGE'),
    ('P', 'Hard storage',    'STORAGE'),
    ('R', 'Other storage',   'STORAGE'),
    -- Workspace
    ('S', 'Stationery org',  'WORKSPACE'),
    ('T', 'Desk acc',        'WORKSPACE'),
    ('U', 'Other workspace', 'WORKSPACE'),
    -- Floor
    ('V', 'Floor coverings', 'FLOOR'),
    -- Garden
    ('W', 'Garden',          'GARDEN')
),
resolved as (
  select c.id as mg_category_id, mg.mg_id
  from authoritative a
  join core.mg_category c
    on c.code = a.category_code
  join core."merchGroup" mg
    on mg."mgTypeCode" = '01'
   and mg.is_active is true          -- see "ONLY is_active ROWS ARE MATCHED" in the header
   and upper(btrim(mg.mg_code)) = upper(a.mg_code)
   and lower(btrim(mg.mg_desc)) = lower(a.mg_desc)
)
insert into core.mg_category_merch_group (mg_category_id, merch_group_mg_id)
select mg_category_id, mg_id from resolved
on conflict (merch_group_mg_id) do nothing;

-- -------------------------------------------------------------------------------------
-- 5. Verification — refuse to finish quietly if the seed did not do what it claims.
-- -------------------------------------------------------------------------------------

do $$
declare
  v_categories      integer;
  v_pairs           integer;
  v_source_rows     integer;
  v_divisions       integer;
  v_expected_links  integer;
  v_actual_links    integer;
  v_missing         text;
  v_drift           text;
  v_renamed         text;
begin
  -- STRUCTURE MUST APPLY EVERYWHERE; ONLY THE ROW ASSERTION IS CONDITIONAL.
  -- ------------------------------------------------------------------------------
  -- WHY THIS CONDITION EXISTS - DO NOT "SIMPLIFY" IT AWAY.
  -- This migration is replayed from EMPTY on an ephemeral database in CI
  -- (.github/workflows/database-contract-tests.yml). That database carries the SCHEMA
  -- of core."merchGroup" but not a single row of it. The first version of this block
  -- raised unconditionally when the 19 authoritative product types did not resolve, so
  -- on the empty database the exception rolled the WHOLE migration back and the two
  -- tables were never created at all. A structural migration is not allowed to depend
  -- on production ROW CONTENT in order to apply its STRUCTURE.
  --
  -- The fix is NOT to drop the guard. It is to distinguish the two situations:
  --   * NO ACTIVE MG01 merchandise-group rows exist at all -> there is nothing to map.
  --     Skip the mapping assertion with a LOUD notice. Nothing is half-seeded, because
  --     nothing could be seeded.
  --   * ACTIVE MG01 rows DO exist -> then for EVERY division that carries any of them,
  --     all 19 authoritative product types must resolve IN THAT DIVISION and carry their
  --     authoritative category. Anything less raises and rolls back, naming the exact
  --     missing (division, code, description) triples.
  --
  -- THE SHAPE IS DERIVED, NEVER HARD-CODED. `v_expected_links` = 19 x the number of
  -- divisions that carry active MG01 rows. Today that evaluates to 57 on production, but
  -- 57 is nowhere in this file: if a fourth division is onboarded the expectation moves
  -- with it, and if one division loses a product type the migration stops.
  --
  -- WHY NOT "did each of the 19 resolve somewhere?" - because a LEFT JOIN from the 19
  -- authoritative rows emits NO ROW for a division that failed to match, not a NULL row.
  -- Under the old check, 'K' matching in two divisions and failing in the third produced
  -- two non-null rows, no NULLs, an "OK" notice and a COMMITTED 56-of-57 seed. Building
  -- the expectation as (19 authoritative types x every division with active MG01 rows)
  -- and then looking for holes in THAT grid is what makes a one-division drift loud.
  --
  -- The drift check below is unconditional in both cases: it only looks at links that
  -- already exist, so it costs nothing on an empty database and never weakens.
  -- ------------------------------------------------------------------------------

  select count(*) into v_categories from core.mg_category;
  if v_categories < 7 then
    raise exception
      'Issue #1163: expected the 7 mgCategory rows, found % - seed did not apply.',
      v_categories;
  end if;

  -- The categories themselves are authoritative, division-independent reference data.
  -- They seed unconditionally on every database, so this assertion stays unconditional.

  -- The gate counts ACTIVE MG01 rows, i.e. exactly the population the seed join matches
  -- against. Counting a different population in the gate than in the join is how a gate
  -- silently stops guarding, so the two are kept identical on purpose.
  select count(*) into v_source_rows
  from core."merchGroup"
  where "mgTypeCode" = '01' and is_active is true;

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
  ),
  active_mg01 as (
    select
      mg.mg_id,
      mg."divisionCode_id_fk" as division_id,
      coalesce(
        nullif(btrim(mg."divisionCode_fk"), ''),
        'division_id ' || coalesce(mg."divisionCode_id_fk"::text, '(null)')
      ) as division_label,
      upper(btrim(mg.mg_code)) as code_key,
      lower(btrim(mg.mg_desc)) as desc_key
    from core."merchGroup" mg
    where mg."mgTypeCode" = '01' and mg.is_active is true
  ),
  divisions as (
    select distinct division_id, division_label from active_mg01
  ),
  -- THE EXPECTED GRID: every authoritative product type x every division that carries
  -- any active MG01 row. A division that matched only part of the list leaves holes here
  -- that no amount of matching in OTHER divisions can fill.
  expected as (
    select d.division_id, d.division_label, a.mg_code, a.mg_desc, a.category_code
    from divisions d
    cross join authoritative a
  ),
  graded as (
    select
      e.division_label, e.mg_code, e.mg_desc, e.category_code,
      m.mg_id,
      c.code as actual_category
    from expected e
    left join active_mg01 m
      on m.division_id is not distinct from e.division_id
     and m.code_key = upper(e.mg_code)
     and m.desc_key = lower(e.mg_desc)
    left join core.mg_category_merch_group l on l.merch_group_mg_id = m.mg_id
    left join core.mg_category c on c.id = l.mg_category_id
  ),
  holes as (
    select
      division_label || ' / ' || mg_code || ' ' || mg_desc
        || case
             when mg_id is null then ' (no active MG01 row matched)'
             else ' (row ' || mg_id || ' exists but is not linked)'
           end as hole_text
    from graded
    where mg_id is null or actual_category is null
  )
  select
    (select count(*) from divisions),
    (select count(*) from expected),
    count(*) filter (where g.actual_category = g.category_code),
    (select string_agg(distinct hole_text, '; ') from holes),
    string_agg(distinct g.division_label || ' / ' || g.mg_code || ' ' || g.mg_desc
        || ' -> ' || g.actual_category, '; ')
      filter (where g.actual_category is not null
                and g.actual_category <> g.category_code)
  into v_divisions, v_expected_links, v_actual_links, v_missing, v_drift
  from graded g;

  -- UNCONDITIONAL. An existing link that disagrees with the authoritative mapping is a
  -- drift on ANY database and is never overwritten quietly.
  if v_drift is not null then
    raise exception
      'Issue #1163: existing category links disagree with the authoritative mapping: %. '
      'Refusing to overwrite a deliberate change - resolve this on the issue.', v_drift;
  end if;

  -- AMBIGUOUS SOURCE ROWS. The grid is (19 types x divisions), so if a division somehow
  -- carries TWO active MG01 rows with the same (code, description) pair, the graded set
  -- has more matched rows than the grid has cells and BOTH rows got a link. That is the
  -- exact failure the `is_active` filter was added to prevent, so it is asserted rather
  -- than trusted.
  if v_actual_links > v_expected_links then
    raise exception
      'Issue #1163: % category links resolved but only % (19 product types x % divisions) '
      'are possible. A division carries more than one ACTIVE mgTypeCode ''01'' row for the '
      'same code/description pair, so the seed attached both. Resolve the duplicate source '
      'rows on the issue.',
      v_actual_links, v_expected_links, v_divisions;
  end if;

  if v_source_rows = 0 then
    -- Loud, never silent. The structure is in place and the mapping seed is a no-op
    -- because there is no source data on this database to map.
    raise notice
      'Issue #1163: core."merchGroup" holds NO ACTIVE mgTypeCode ''01'' rows on this '
      'database, so the category-to-MG01 mappings were NOT seeded and their assertion is '
      'SKIPPED. The tables, constraints, indexes, RLS and grants applied in full, and '
      'the 7 categories were seeded. On a database that does carry active MG01 rows this '
      'same block raises instead of skipping.';
  elsif v_missing is not null then
    -- Rows ARE present, so a hole in the grid is a real failure. Hard stop.
    --
    -- TELLING A MOVED LINK APART FROM A RENAMED SOURCE DESCRIPTION. If someone upstream
    -- corrects a description (say all three 'Desk acc' rows become 'Desk accessory'), the
    -- existing links survive but the join above no longer finds them, so those rows show
    -- up as missing. That looks identical to a genuinely unseeded row unless we say so.
    -- The tell is an ALREADY-LINKED active MG01 row whose (code, description) pair is not
    -- in the authoritative list, so we look for exactly that and name it in the error.
    -- A description rename is NOT something this migration may absorb: its authoritative
    -- list is the workbook, and changing it is a governed decision. The fix is a
    -- follow-up migration under its own issue, never an edit to this applied file.
    select string_agg(distinct mg.mg_code || ' ' || mg.mg_desc, '; ')
      into v_renamed
    from core.mg_category_merch_group l
    join core."merchGroup" mg on mg.mg_id = l.merch_group_mg_id
    where mg."mgTypeCode" = '01'
      and mg.is_active is true
      and (upper(btrim(mg.mg_code)), lower(btrim(mg.mg_desc))) not in (
        ('A','stretched/box'),('B','framed'),('C','plaque'),('D','functional'),
        ('E','other wall'),('F','block'),('G','box'),('H','photo frames'),
        ('J','object'),('K','other tabletop'),('M','clocks'),('N','soft storage'),
        ('P','hard storage'),('R','other storage'),('S','stationery org'),
        ('T','desk acc'),('U','other workspace'),('V','floor coverings'),('W','garden')
      );

    raise exception
      'Issue #1163: % active mgTypeCode ''01'' rows across % divisions were expected to '
      'carry all 19 authoritative product types (% links), but only % resolved. '
      'Missing: %.%',
      v_source_rows, v_divisions, v_expected_links, v_actual_links, v_missing,
      case
        when v_renamed is not null then
          ' NOTE: these merchandise-group rows are ALREADY LINKED but their descriptions '
          'are not in the authoritative list: ' || v_renamed || '. That is the signature '
          'of an upstream DESCRIPTION RENAME, not of a missing link. This migration must '
          'not be edited to follow the rename - it is already applied elsewhere. Open a '
          'follow-up shared-db issue to update the authoritative list in a NEW migration.'
        else
          ' If instead a human deliberately moved or removed a link, that is exactly what '
          'this guard exists to block: resolve it on the issue rather than re-applying.'
      end;
  end if;

  select count(*) into v_pairs from core.mg_category_merch_group;
  raise notice
    'Issue #1163 OK: % categories, % category-to-MG01 link rows total (% expected across '
    '% divisions x 19 product types, from % active MG01 source rows).',
    v_categories, v_pairs, v_expected_links, v_divisions, v_source_rows;
end;
$$;

-- -------------------------------------------------------------------------------------
-- 6. RLS and grants — same shape as core.product_size (issue #597).
--
-- WHAT ACTUALLY SHIPS HERE, stated precisely rather than aspirationally:
--   * `anon`  : nothing at all (every privilege revoked).
--   * `authenticated` : SELECT only. There is no INSERT/UPDATE/DELETE grant, so Postgres
--     refuses a write from a browser session BEFORE RLS is ever consulted. The
--     `admin_write` policy exists so that a future decision to grant writes to
--     administrators is already scoped, but today no browser role can reach it.
--   * `service_role` : full grants, and it has BYPASSRLS, so server-side jobs and
--     governed migrations write these rows.
-- That is the same shape as core.product_size (issue #597) and it is deliberate: these
-- are structural reference rows, maintained by migration, not by the application.
-- -------------------------------------------------------------------------------------

alter table core.mg_category             enable row level security;
alter table core.mg_category_merch_group enable row level security;

drop policy if exists shared_read on core.mg_category;
create policy shared_read on core.mg_category
  for select to authenticated
  using (
    (select app.has_any_role(array[
      'administrator', 'sales', 'licensing', 'designer', 'viewer', 'vendor'
    ]::app.app_role[]))
  );

drop policy if exists admin_write on core.mg_category;
create policy admin_write on core.mg_category
  for all to authenticated
  using ((select app.has_any_role(array['administrator']::app.app_role[])))
  with check ((select app.has_any_role(array['administrator']::app.app_role[])));

drop policy if exists shared_read on core.mg_category_merch_group;
create policy shared_read on core.mg_category_merch_group
  for select to authenticated
  using (
    (select app.has_any_role(array[
      'administrator', 'sales', 'licensing', 'designer', 'viewer', 'vendor'
    ]::app.app_role[]))
  );

drop policy if exists admin_write on core.mg_category_merch_group;
create policy admin_write on core.mg_category_merch_group
  for all to authenticated
  using ((select app.has_any_role(array['administrator']::app.app_role[])))
  with check ((select app.has_any_role(array['administrator']::app.app_role[])));

revoke all on table core.mg_category             from public, anon;
revoke all on table core.mg_category_merch_group from public, anon;

grant select on table core.mg_category             to authenticated;
grant select on table core.mg_category_merch_group to authenticated;

grant all on table core.mg_category             to service_role;
grant all on table core.mg_category_merch_group to service_role;

-- -------------------------------------------------------------------------------------
-- 7. THE READ CONTRACT (issue #1163 acceptance check 5)
--
-- Deliberately shipped as a DOCUMENTED QUERY rather than a view: this change is claimed
-- for exactly two objects, `core.mg_category` and `core.mg_category_merch_group`, and a
-- view would be a third object outside that claim. The query below is the supported
-- contract; a view over it can be added later under its own claim if an app wants one.
--
--   select
--     cat.code            as category_code,
--     cat.name            as category_name,
--     cat.sort_order      as category_sort_order,
--     mg.mg_code          as mg01_code,
--     mg.mg_desc          as mg01_product_type,
--     mg.mg_id            as merch_group_mg_id,
--     mg."companyCode_id_fk"  as company_id,
--     mg."divisionCode_id_fk" as division_id,
--     mg.is_active        as mg01_is_active
--   from core.mg_category_merch_group link
--   join core.mg_category cat on cat.id = link.mg_category_id
--   join core."merchGroup" mg  on mg.mg_id = link.merch_group_mg_id
--   where cat.is_active
--   order by cat.sort_order, mg."divisionCode_id_fk", mg.mg_code;
--
-- To resolve ONE item's category, start from the MG01 row the item selected and follow
-- link -> category. Never resolve by mg_code alone (see header). MG02/MG03 selections
-- must walk up `parent_id` to their MG01 ancestor first; they never carry a category of
-- their own.
-- -------------------------------------------------------------------------------------
