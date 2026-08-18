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
-- correct per company/division rather than approximated once globally. Measured live on
-- 2026-08-18: divisions 1 (POP Lic), 8 (Spruce Lic) and 9 (Spruce Non-Lic) each carry the
-- 19 authoritative product types, so this seed is expected to create 57 link rows on
-- production today. That number is an OBSERVATION, not a hard-coded expectation — the
-- assertion below checks that all 19 product types resolved somewhere, never that a
-- particular row count came back.
--
-- CODE 'Q' — "TBD storage" — IS DELIBERATELY NOT MAPPED
-- -----------------------------------------------------
-- Production also carries an MG01 row 'Q' "TBD storage" whose free-text `mgCategory`
-- reads 'Storage'. It is NOT in the workbook's 19 and it is inactive in two of the three
-- divisions. Inventing a mapping for it here would be this migration deciding a business
-- question it was not asked. It is left unmapped and visible: the read contract simply
-- returns no category for it, which is honest, and a later governed change can add it.
--
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
  -- one MG01 product-type row can belong to AT MOST ONE category. A second insert for
  -- the same merchandise-group row fails outright.
  constraint mg_category_merch_group_one_category_per_product_type
    unique (merch_group_mg_id)
);

create index if not exists mg_category_merch_group_category_idx
  on core.mg_category_merch_group (mg_category_id);

comment on table core.mg_category_merch_group is
  'Issue #1163. Category -> MG01 product type. One category has many MG01 rows; each MG01 '
  'row has exactly one category (enforced by the unique constraint on merch_group_mg_id). '
  'Links to core."merchGroup"(mg_id), NOT to the MG01 letter code: codes are unique only '
  'per division+type and collide semantically (mg_id 26 = ''A'' LEATHER/COWHIDE vs '
  'mg_id 2462 = ''A'' Stretched/Box, both mgTypeCode ''01'').';

comment on column core.mg_category_merch_group.merch_group_mg_id is
  'core."merchGroup".mg_id. Company/division scope is inherited from that row.';

comment on constraint mg_category_merch_group_one_category_per_product_type
  on core.mg_category_merch_group is
  'Issue #1163 acceptance check 3: a product type cannot silently belong to two categories.';

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
  v_categories integer;
  v_pairs      integer;
  v_missing    text;
  v_drift      text;
begin
  select count(*) into v_categories from core.mg_category;
  if v_categories < 7 then
    raise exception
      'Issue #1163: expected the 7 mgCategory rows, found % — seed did not apply.',
      v_categories;
  end if;

  -- Every one of the 19 authoritative product types must have resolved to at least one
  -- real merchandise-group row, and must be linked to the right category.
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
  linked as (
    select a.mg_code, a.mg_desc, a.category_code, mg.mg_id, c.code as actual_category
    from authoritative a
    left join core."merchGroup" mg
      on mg."mgTypeCode" = '01'
     and upper(btrim(mg.mg_code)) = upper(a.mg_code)
     and lower(btrim(mg.mg_desc)) = lower(a.mg_desc)
    left join core.mg_category_merch_group l on l.merch_group_mg_id = mg.mg_id
    left join core.mg_category c on c.id = l.mg_category_id
  )
  select
    string_agg(distinct mg_code || ' ' || mg_desc, ', ')
      filter (where mg_id is null or actual_category is null),
    string_agg(distinct mg_code || ' ' || mg_desc || ' -> ' || actual_category, ', ')
      filter (where actual_category is not null and actual_category <> category_code)
  into v_missing, v_drift
  from linked;

  if v_drift is not null then
    raise exception
      'Issue #1163: existing category links disagree with the authoritative mapping: %. '
      'Refusing to overwrite a deliberate change — resolve this on the issue.', v_drift;
  end if;

  if v_missing is not null then
    raise exception
      'Issue #1163: these authoritative MG01 product types did not resolve or were not '
      'linked: %. The merchandise-group rows may be named differently on this database.',
      v_missing;
  end if;

  select count(*) into v_pairs from core.mg_category_merch_group;
  raise notice 'Issue #1163 OK: % categories, % category-to-MG01 link rows.',
    v_categories, v_pairs;
end;
$$;

-- -------------------------------------------------------------------------------------
-- 6. RLS and grants — same shape as core.product_size (issue #597).
--
-- Reads for the normal application roles; writes for administrators only. These are
-- structural reference rows, so no browser role gets a write grant.
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
