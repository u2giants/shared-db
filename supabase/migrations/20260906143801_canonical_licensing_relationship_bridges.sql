-- Canonical licensing relationship foundation: the direct Property/Style Guide,
-- Property/Franchise, Asset/Property, Asset/Style Guide and Asset/Franchise bridges,
-- plus a per-source support-edge table for all eight canonical relationships.
--
-- Issue #2334 (structural successor to #1090). Claim issue #2405,
-- reserved version 20260906143801.
--
-- derived-from: none
--
-- WHY THIS EXISTS
-- ---------------
-- POP Creations must be able to state, per licensor source, which properties belong to
-- which franchises and style guides, and which digital assets depict which property,
-- character, style guide or franchise. Today it cannot. A 2026-09-04 reconciliation of
-- current `main` against production proved the five direct bridges created below are
-- absent from both.
--
-- Three of the eight canonical bridges DO already exist and are NOT recreated here:
--   core.property_character_associations  (20260829004145)
--   core.style_guide_character            (20260727230000)
--   dam.asset_character                   (20260621151024)
-- What every one of the eight lacked is the thing a royalty or approval decision
-- actually turns on: WHO asserted the relationship, and whether they asserted it at all
-- or whether we inferred it. That is what the *_source_edge tables record.
--
-- AUDIT OF core.property_character_associations (required by #2334)
-- -----------------------------------------------------------------
-- It IS the canonical application-facing Property/Character bridge, and it is correctly
-- shaped. Verified on this branch:
--   * endpoints are uuid `property_id` / `character_id`, primary key (property_id,
--     character_id), and it carries NO licensor_id -- all three are asserted by
--     supabase/tests/core_property_character_separation.sql, which also asserts the
--     table is EMPTY and that neither `authenticated` nor `service_role` may INSERT;
--   * both foreign keys are already ON UPDATE CASCADE ON DELETE RESTRICT, so endpoint
--     deletion ALREADY fails closed there;
--   * it is read by exactly one live endpoint,
--     api.db_data_admin_licensor_property_tree, purely as a per-property character
--     COUNT, and supabase/tests/universe_a_empty_character_drop_contracts.sql pins that
--     function to literally reference this table and NOT to reference core.character.
-- Conclusion: no change to it is warranted or safe, and this migration makes none. Its
-- one real gap -- it records no source or evidence strength -- is closed additively by
-- core.property_character_source_edge below, which leaves the endpoint contract byte
-- for byte intact.
--
-- WHAT THIS IS NOT
-- ----------------
-- ADDITIVE ONLY. This migration creates one enum, two trigger functions and thirteen
-- tables. It ALTERS NOTHING that already exists: not the three pre-existing bridges,
-- not core.property / character / style_guide / franchise, not dam.asset, and not any
-- existing view, function, policy or grant. It seeds NO rows. #2334 authorizes no
-- relationship rows and no licensed evidence, and inventing edges here would be exactly
-- the ungoverned Master Data load AGENTS.md 6.4 forbids.
--
-- THE THREE-WAY EVIDENCE SPLIT -- THE POINT OF THE WHOLE MIGRATION
-- ----------------------------------------------------------------
-- A support edge is one source system's claim about one pair. Its evidence_kind is one
-- of three DISTINCT facts, and they never merge:
--   direct_source_assertion  the licensor's own system published this exact pair;
--   inferred                 we derived it from other fields;
--   co_occurrence            two things merely appeared together on the same asset.
-- `is_direct_source_relationship` is a GENERATED column, not a default and not a
-- caller-supplied flag, so an inferred row cannot be relabelled as direct: this is the
-- CHECK-pinned discipline of plm.pmt_property_franchise_evidence (20260810020000),
-- strengthened from "cannot be overridden by an INSERT" to "cannot be written at all".
--
-- Inferred and co-occurrence evidence can never BECOME a direct canonical edge. On each
-- of the five NEW canonical bridges, core.require_direct_support_for_canonical_edge()
-- refuses any row that is not backed by a CURRENT direct_source_assertion support edge
-- for that exact pair. A table full of co-occurrence therefore supports nothing.
--
-- FAIL-CLOSED ENDPOINT DELETION
-- -----------------------------
-- Deleting an endpoint entity must not silently discard licensing evidence.
--   * The five NEW bridges take ON UPDATE CASCADE ON DELETE RESTRICT to both endpoints,
--     matching core.property_character_associations exactly.
--   * The three PRE-EXISTING bridges take ON DELETE CASCADE to their endpoints. Those
--     are live tables read by shipped applications, so rule 3 (additive by default)
--     forbids re-pointing their foreign keys here. Instead every support edge carries
--     core.refuse_delete_of_current_support_edge(), a BEFORE DELETE trigger that raises
--     while the row is still current. Support edges cascade FROM the bridge, so a
--     cascade that would erase current support aborts the whole transaction and the
--     endpoint delete fails closed anyway -- without altering one byte of the live
--     bridges.
--   * Support that has been superseded (is_current = false) does NOT block: only
--     CURRENT support does, which is exactly what #2334 requires.


-- ---------------------------------------------------------------------------
-- 1. The evidence vocabulary
-- ---------------------------------------------------------------------------
-- An enum, not a per-table text CHECK. Thirteen hand-copied CHECK constraints would be
-- thirteen chances to drift, and the two trigger functions below need one authoritative
-- name for "direct". Adding a fourth kind later is an explicit, reviewable migration --
-- which is the correct cost for widening what may count as licensing evidence.
create type core.relationship_evidence_kind as enum (
  'direct_source_assertion',
  'inferred',
  'co_occurrence'
);

comment on type core.relationship_evidence_kind is
  'How a licensing relationship came to be believed (issue #2334). direct_source_assertion: '
  'the licensor''s own system published this exact pair. inferred: we derived it from other '
  'fields. co_occurrence: two things merely appeared together on the same asset. Only '
  'direct_source_assertion may support a canonical bridge edge; the other two are evidence '
  'and are never authority.';


-- ---------------------------------------------------------------------------
-- 2. The two guards
-- ---------------------------------------------------------------------------
-- Both are new objects with novel names, created only to serve the tables below.

-- 2a. Fail-closed deletion of current support.
create or replace function core.refuse_delete_of_current_support_edge()
returns trigger
language plpgsql
as $$
begin
  -- Deliberately blind to WHY the delete is happening. It fires the same for a direct
  -- DELETE and for a cascade arriving from a deleted bridge row or a deleted endpoint
  -- entity, which is what makes endpoint deletion fail closed on the three pre-existing
  -- bridges whose own foreign keys this migration must not alter.
  if old.is_current then
    raise exception
      'Refused: %.% still holds CURRENT % support for this relationship (support edge %). '
      'Deleting it -- or deleting an endpoint or canonical edge that cascades to it -- would '
      'silently discard licensing evidence a royalty or approval decision may rest on. '
      'Supersede the support edge first (set is_current = false and superseded_at), then '
      'delete.',
      tg_table_schema, tg_table_name, old.evidence_kind, old.id
      using errcode = 'P0001';
  end if;
  return old;
end;
$$;

comment on function core.refuse_delete_of_current_support_edge() is
  'BEFORE DELETE guard on every *_source_edge table (issue #2334). Refuses while the row is '
  'current; superseded support deletes freely. Fires on cascades too, which is how endpoint '
  'deletion fails closed for the pre-existing ON DELETE CASCADE bridges.';

-- 2b. Inferred and co-occurrence evidence can never become a direct canonical edge.
create or replace function core.require_direct_support_for_canonical_edge()
returns trigger
language plpgsql
as $$
declare
  v_support   text := tg_argv[0];   -- fully qualified support-edge table
  v_left_col  text := tg_argv[1];
  v_right_col text := tg_argv[2];
  v_left      uuid;
  v_right     uuid;
  v_supported boolean;
begin
  -- to_jsonb rather than a composite parameter: a plpgsql trigger cannot reliably project
  -- a dynamically named column out of NEW, and this keeps one function serving all five
  -- bridges instead of five near-identical copies.
  v_left  := (to_jsonb(new) ->> v_left_col)::uuid;
  v_right := (to_jsonb(new) ->> v_right_col)::uuid;

  execute format(
    'select exists (select 1 from %s s where s.%I = $1 and s.%I = $2 '
    'and s.is_current '
    'and s.evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind)',
    v_support, v_left_col, v_right_col)
  into v_supported
  using v_left, v_right;

  if not v_supported then
    raise exception
      'Refused: canonical edge %.% (% = %, % = %) has no CURRENT direct source assertion in %. '
      'Inferred and co-occurrence evidence are never promoted to a canonical relationship -- '
      'record the licensor''s own assertion in the support-edge table first.',
      tg_table_schema, tg_table_name, v_left_col, v_left, v_right_col, v_right, v_support
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function core.require_direct_support_for_canonical_edge() is
  'BEFORE INSERT OR UPDATE guard on the canonical bridges created by issue #2334. A canonical '
  'edge may exist only while a CURRENT direct_source_assertion support edge names the same '
  'pair, so inferred/co-occurrence evidence can never be promoted into canon.';

-- 2c. Supersession may not silently orphan a canonical edge (review finding H-1).
-- The BEFORE DELETE guard above refuses to DELETE current support, but the documented
-- withdrawal path is an UPDATE that sets is_current = false. Without this guard that
-- UPDATE achieves exactly what the delete guard forbids: a canonical bridge row left
-- standing with no current direct evidence under it, which is the royalty-decision
-- failure this migration exists to prevent. The bridge comments state the invariant in
-- the present continuous ("may exist only WHILE ... holds a CURRENT direct source
-- assertion"), so it has to be enforced continuously, not only at bridge-write time.
create or replace function core.refuse_unsupporting_update_of_support_edge()
returns trigger
language plpgsql
as $$
declare
  v_bridge    text := tg_argv[0];   -- fully qualified canonical bridge table
  v_left_col  text := tg_argv[1];
  v_right_col text := tg_argv[2];
  v_left      uuid;
  v_right     uuid;
  v_bridged   boolean;
  v_other     boolean;
begin
  -- Only a row that IS current direct support today can withdraw any.
  if not (old.is_current and old.evidence_kind = 'direct_source_assertion') then
    return new;
  end if;

  -- Still current direct support for the same pair afterwards: nothing was withdrawn.
  if new.is_current
     and new.evidence_kind = 'direct_source_assertion'
     and (to_jsonb(new) ->> v_left_col) is not distinct from (to_jsonb(old) ->> v_left_col)
     and (to_jsonb(new) ->> v_right_col) is not distinct from (to_jsonb(old) ->> v_right_col) then
    return new;
  end if;

  v_left  := (to_jsonb(old) ->> v_left_col)::uuid;
  v_right := (to_jsonb(old) ->> v_right_col)::uuid;

  -- No canonical edge cites this pair, so nothing can be orphaned by withdrawing it.
  execute format(
    'select exists (select 1 from %s b where b.%I = $1 and b.%I = $2)',
    v_bridge, v_left_col, v_right_col)
  into v_bridged
  using v_left, v_right;

  if not v_bridged then
    return new;
  end if;

  -- Supersession BY REPLACEMENT stays legal: another current direct assertion already
  -- covers the pair, so the canonical edge keeps standing on real evidence.
  execute format(
    'select exists (select 1 from %I.%I s where s.%I = $1 and s.%I = $2 '
    'and s.id <> $3 and s.is_current '
    'and s.evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind)',
    tg_table_schema, tg_table_name, v_left_col, v_right_col)
  into v_other
  using v_left, v_right, old.id;

  if v_other then
    return new;
  end if;

  raise exception
    'Refused: %.% row % is the LAST current direct source assertion behind the canonical edge '
    'in % (% = %, % = %). Withdrawing it would leave that canonical edge standing with no '
    'evidence at all. Record the replacing direct assertion first, or remove the canonical edge '
    'in a governed migration.',
    tg_table_schema, tg_table_name, old.id, v_bridge,
    v_left_col, v_left, v_right_col, v_right
    using errcode = 'P0001';
end;
$$;

comment on function core.refuse_unsupporting_update_of_support_edge() is
  'BEFORE UPDATE guard on every *_source_edge table (issue #2334, review finding H-1). Refuses '
  'an update that withdraws the LAST current direct source assertion behind an existing canonical '
  'bridge row -- by clearing is_current, by relabelling evidence_kind away from direct, or by '
  'repointing the pair. Supersession by replacement, and supersession of a pair no canonical edge '
  'cites, both remain free. Together with the BEFORE DELETE guard it makes the bridges'' documented '
  '"only while currently supported" invariant continuous rather than write-time only.';



-- ---------------------------------------------------------------------------
-- 3. The five missing canonical bridges
-- ---------------------------------------------------------------------------
-- Shape and posture are copied from core.property_character_associations, the canonical
-- Property/Character bridge audited in the header: uuid endpoints, ON UPDATE CASCADE ON
-- DELETE RESTRICT so endpoint deletion fails closed, a composite primary key so a pair
-- cannot be stated twice, RLS read for the standard role set, and NO write privilege for
-- any role -- canonical licensing edges are written only by a governed migration.

-- 3.1 core.property_style_guide
-- Which style guides a licensor publishes for a property. Royalty and approval decisions cite the style guide, so this edge must be licensor-asserted, never guessed.
create table core.property_style_guide (
  property_id     uuid not null references core.property(id) on update cascade on delete restrict,
  style_guide_id  uuid not null references core.style_guide(id) on update cascade on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (property_id, style_guide_id)
);

-- Reverse lookup. The primary key already indexes property_id as its leading column.
create index property_style_guide_style_guide_id_idx
  on core.property_style_guide (style_guide_id);

create trigger set_updated_at before update on core.property_style_guide
  for each row execute function app.set_updated_at();

-- Inferred and co-occurrence evidence can never become a canonical edge here.
create trigger require_direct_support
  before insert or update on core.property_style_guide
  for each row execute function core.require_direct_support_for_canonical_edge(
    'core.property_style_guide_source_edge', 'property_id', 'style_guide_id');

alter table core.property_style_guide enable row level security;

create policy shared_read on core.property_style_guide
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.property_style_guide from public, anon, authenticated;
grant select on core.property_style_guide to authenticated;
grant select on core.property_style_guide to service_role;
revoke insert, update, delete, truncate on core.property_style_guide
  from public, anon, authenticated, service_role;

comment on table core.property_style_guide is
  'Canonical direct property <-> style guide relationship (issue #2334). Which style guides a licensor publishes for a property. Royalty and approval decisions cite the style guide, so this edge must be licensor-asserted, never guessed. '
  'A row may exist only while core.property_style_guide_source_edge holds a CURRENT direct source assertion for the same pair; '
  'inferred and co-occurrence evidence never reach this table. Endpoint deletion is RESTRICT, so a '
  'property or style_guide cannot be deleted out from under a stated relationship. No role may write '
  'here -- canonical edges are written only by a governed migration. Seeded empty: #2334 authorizes '
  'no relationship rows.';

-- 3.2 core.property_franchise
-- Which franchise a property sits under. This is exactly the edge that plm.pmt_property_franchise_evidence refuses to assert, because Paramount only ever exposed it as asset co-occurrence.
create table core.property_franchise (
  property_id     uuid not null references core.property(id) on update cascade on delete restrict,
  franchise_id    uuid not null references core.franchise(id) on update cascade on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (property_id, franchise_id)
);

-- Reverse lookup. The primary key already indexes property_id as its leading column.
create index property_franchise_franchise_id_idx
  on core.property_franchise (franchise_id);

create trigger set_updated_at before update on core.property_franchise
  for each row execute function app.set_updated_at();

-- Inferred and co-occurrence evidence can never become a canonical edge here.
create trigger require_direct_support
  before insert or update on core.property_franchise
  for each row execute function core.require_direct_support_for_canonical_edge(
    'core.property_franchise_source_edge', 'property_id', 'franchise_id');

alter table core.property_franchise enable row level security;

create policy shared_read on core.property_franchise
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.property_franchise from public, anon, authenticated;
grant select on core.property_franchise to authenticated;
grant select on core.property_franchise to service_role;
revoke insert, update, delete, truncate on core.property_franchise
  from public, anon, authenticated, service_role;

comment on table core.property_franchise is
  'Canonical direct property <-> franchise relationship (issue #2334). Which franchise a property sits under. This is exactly the edge that plm.pmt_property_franchise_evidence refuses to assert, because Paramount only ever exposed it as asset co-occurrence. '
  'A row may exist only while core.property_franchise_source_edge holds a CURRENT direct source assertion for the same pair; '
  'inferred and co-occurrence evidence never reach this table. Endpoint deletion is RESTRICT, so a '
  'property or franchise cannot be deleted out from under a stated relationship. No role may write '
  'here -- canonical edges are written only by a governed migration. Seeded empty: #2334 authorizes '
  'no relationship rows.';

-- 3.3 dam.asset_property
-- Which properties a digital asset depicts. dam.asset.property_id is a single legacy scalar pointer and cannot express an asset that depicts two properties.
create table dam.asset_property (
  asset_id        uuid not null references dam.asset(id) on update cascade on delete restrict,
  property_id     uuid not null references core.property(id) on update cascade on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (asset_id, property_id)
);

-- Reverse lookup. The primary key already indexes asset_id as its leading column.
create index asset_property_property_id_idx
  on dam.asset_property (property_id);

create trigger set_updated_at before update on dam.asset_property
  for each row execute function app.set_updated_at();

-- Inferred and co-occurrence evidence can never become a canonical edge here.
create trigger require_direct_support
  before insert or update on dam.asset_property
  for each row execute function core.require_direct_support_for_canonical_edge(
    'dam.asset_property_source_edge', 'asset_id', 'property_id');

alter table dam.asset_property enable row level security;

revoke all on dam.asset_property from public, anon, authenticated;
grant select on dam.asset_property to service_role;
revoke insert, update, delete, truncate on dam.asset_property
  from public, anon, authenticated, service_role;

comment on table dam.asset_property is
  'Canonical direct asset <-> property relationship (issue #2334). Which properties a digital asset depicts. dam.asset.property_id is a single legacy scalar pointer and cannot express an asset that depicts two properties. '
  'A row may exist only while dam.asset_property_source_edge holds a CURRENT direct source assertion for the same pair; '
  'inferred and co-occurrence evidence never reach this table. Endpoint deletion is RESTRICT, so a '
  'asset or property cannot be deleted out from under a stated relationship. No role may write '
  'here -- canonical edges are written only by a governed migration. Seeded empty: #2334 authorizes '
  'no relationship rows.';

-- 3.4 dam.asset_style_guide
-- Which style guide a digital asset was drawn from. Approval submissions cite this.
create table dam.asset_style_guide (
  asset_id        uuid not null references dam.asset(id) on update cascade on delete restrict,
  style_guide_id  uuid not null references core.style_guide(id) on update cascade on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (asset_id, style_guide_id)
);

-- Reverse lookup. The primary key already indexes asset_id as its leading column.
create index asset_style_guide_style_guide_id_idx
  on dam.asset_style_guide (style_guide_id);

create trigger set_updated_at before update on dam.asset_style_guide
  for each row execute function app.set_updated_at();

-- Inferred and co-occurrence evidence can never become a canonical edge here.
create trigger require_direct_support
  before insert or update on dam.asset_style_guide
  for each row execute function core.require_direct_support_for_canonical_edge(
    'dam.asset_style_guide_source_edge', 'asset_id', 'style_guide_id');

alter table dam.asset_style_guide enable row level security;

revoke all on dam.asset_style_guide from public, anon, authenticated;
grant select on dam.asset_style_guide to service_role;
revoke insert, update, delete, truncate on dam.asset_style_guide
  from public, anon, authenticated, service_role;

comment on table dam.asset_style_guide is
  'Canonical direct asset <-> style guide relationship (issue #2334). Which style guide a digital asset was drawn from. Approval submissions cite this. '
  'A row may exist only while dam.asset_style_guide_source_edge holds a CURRENT direct source assertion for the same pair; '
  'inferred and co-occurrence evidence never reach this table. Endpoint deletion is RESTRICT, so a '
  'asset or style_guide cannot be deleted out from under a stated relationship. No role may write '
  'here -- canonical edges are written only by a governed migration. Seeded empty: #2334 authorizes '
  'no relationship rows.';

-- 3.5 dam.asset_franchise
-- Which franchise a digital asset belongs to.
create table dam.asset_franchise (
  asset_id        uuid not null references dam.asset(id) on update cascade on delete restrict,
  franchise_id    uuid not null references core.franchise(id) on update cascade on delete restrict,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (asset_id, franchise_id)
);

-- Reverse lookup. The primary key already indexes asset_id as its leading column.
create index asset_franchise_franchise_id_idx
  on dam.asset_franchise (franchise_id);

create trigger set_updated_at before update on dam.asset_franchise
  for each row execute function app.set_updated_at();

-- Inferred and co-occurrence evidence can never become a canonical edge here.
create trigger require_direct_support
  before insert or update on dam.asset_franchise
  for each row execute function core.require_direct_support_for_canonical_edge(
    'dam.asset_franchise_source_edge', 'asset_id', 'franchise_id');

alter table dam.asset_franchise enable row level security;

revoke all on dam.asset_franchise from public, anon, authenticated;
grant select on dam.asset_franchise to service_role;
revoke insert, update, delete, truncate on dam.asset_franchise
  from public, anon, authenticated, service_role;

comment on table dam.asset_franchise is
  'Canonical direct asset <-> franchise relationship (issue #2334). Which franchise a digital asset belongs to. '
  'A row may exist only while dam.asset_franchise_source_edge holds a CURRENT direct source assertion for the same pair; '
  'inferred and co-occurrence evidence never reach this table. Endpoint deletion is RESTRICT, so a '
  'asset or franchise cannot be deleted out from under a stated relationship. No role may write '
  'here -- canonical edges are written only by a governed migration. Seeded empty: #2334 authorizes '
  'no relationship rows.';

-- ---------------------------------------------------------------------------
-- 4. Per-source support edges -- one per canonical relationship
-- ---------------------------------------------------------------------------
-- One row is one source system's claim about one pair, under one licensor. These tables
-- hold the evidence; the bridges above hold the conclusion.
--
-- licensor_id is NOT NULL and is part of the identity key. Source ids collide across
-- licensors -- Disney and Sega both number from small integers -- so a bare
-- (source_system, source_id) key would attribute one licensor's relationship to another,
-- which is a royalty error, not a cosmetic one.
--
-- Endpoint foreign keys are ON DELETE CASCADE here, paired with the BEFORE DELETE guard.
-- RESTRICT would pin superseded evidence forever and make an endpoint undeletable long
-- after every claim about it was withdrawn; the guard blocks precisely while support is
-- CURRENT, and lets historical evidence be cleaned up with the entity.

-- 4.1 core.property_character_source_edge
-- Supports core.property_character_associations, which already existed on main and is deliberately left unaltered.
create table core.property_character_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  property_id       uuid not null references core.property(id) on update cascade on delete cascade,
  character_id      uuid not null references core.character(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint property_character_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint property_character_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint property_character_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint property_character_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint property_character_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint property_character_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint property_character_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index property_character_source_edge_current_claim_key
  on core.property_character_source_edge (property_id, character_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index property_character_source_edge_character_id_idx on core.property_character_source_edge (character_id);
create index property_character_source_edge_licensor_idx on core.property_character_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index property_character_source_edge_direct_current_idx
  on core.property_character_source_edge (property_id, character_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on core.property_character_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on core.property_character_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on core.property_character_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'core.property_character_associations', 'property_id', 'character_id');

alter table core.property_character_source_edge enable row level security;

create policy shared_read on core.property_character_source_edge
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.property_character_source_edge from public, anon, authenticated;
grant select on core.property_character_source_edge to authenticated;
grant all on core.property_character_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on core.property_character_source_edge from service_role;

comment on table core.property_character_source_edge is
  'Per-source support evidence for the property <-> character relationship (issue #2334). '
  'Supports core.property_character_associations, which already existed on main and is deliberately left unaltered. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column core.property_character_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column core.property_character_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column core.property_character_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column core.property_character_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.2 core.property_style_guide_source_edge
-- Supports the canonical bridge core.property_style_guide, created alongside it.
create table core.property_style_guide_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  property_id       uuid not null references core.property(id) on update cascade on delete cascade,
  style_guide_id    uuid not null references core.style_guide(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint property_style_guide_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint property_style_guide_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint property_style_guide_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint property_style_guide_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint property_style_guide_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint property_style_guide_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint property_style_guide_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index property_style_guide_source_edge_current_claim_key
  on core.property_style_guide_source_edge (property_id, style_guide_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index property_style_guide_source_edge_style_guide_id_idx on core.property_style_guide_source_edge (style_guide_id);
create index property_style_guide_source_edge_licensor_idx on core.property_style_guide_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index property_style_guide_source_edge_direct_current_idx
  on core.property_style_guide_source_edge (property_id, style_guide_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on core.property_style_guide_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on core.property_style_guide_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on core.property_style_guide_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'core.property_style_guide', 'property_id', 'style_guide_id');

alter table core.property_style_guide_source_edge enable row level security;

create policy shared_read on core.property_style_guide_source_edge
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.property_style_guide_source_edge from public, anon, authenticated;
grant select on core.property_style_guide_source_edge to authenticated;
grant all on core.property_style_guide_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on core.property_style_guide_source_edge from service_role;

comment on table core.property_style_guide_source_edge is
  'Per-source support evidence for the property <-> style guide relationship (issue #2334). '
  'Supports the canonical bridge core.property_style_guide, created alongside it. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column core.property_style_guide_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column core.property_style_guide_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column core.property_style_guide_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column core.property_style_guide_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.3 core.property_franchise_source_edge
-- Supports the canonical bridge core.property_franchise, created alongside it.
create table core.property_franchise_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  property_id       uuid not null references core.property(id) on update cascade on delete cascade,
  franchise_id      uuid not null references core.franchise(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint property_franchise_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint property_franchise_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint property_franchise_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint property_franchise_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint property_franchise_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint property_franchise_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint property_franchise_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index property_franchise_source_edge_current_claim_key
  on core.property_franchise_source_edge (property_id, franchise_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index property_franchise_source_edge_franchise_id_idx on core.property_franchise_source_edge (franchise_id);
create index property_franchise_source_edge_licensor_idx on core.property_franchise_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index property_franchise_source_edge_direct_current_idx
  on core.property_franchise_source_edge (property_id, franchise_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on core.property_franchise_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on core.property_franchise_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on core.property_franchise_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'core.property_franchise', 'property_id', 'franchise_id');

alter table core.property_franchise_source_edge enable row level security;

create policy shared_read on core.property_franchise_source_edge
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.property_franchise_source_edge from public, anon, authenticated;
grant select on core.property_franchise_source_edge to authenticated;
grant all on core.property_franchise_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on core.property_franchise_source_edge from service_role;

comment on table core.property_franchise_source_edge is
  'Per-source support evidence for the property <-> franchise relationship (issue #2334). '
  'Supports the canonical bridge core.property_franchise, created alongside it. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column core.property_franchise_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column core.property_franchise_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column core.property_franchise_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column core.property_franchise_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.4 core.style_guide_character_source_edge
-- Supports core.style_guide_character, which already existed on main and is deliberately left unaltered.
create table core.style_guide_character_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  style_guide_id    uuid not null references core.style_guide(id) on update cascade on delete cascade,
  character_id      uuid not null references core.character(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint style_guide_character_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint style_guide_character_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint style_guide_character_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint style_guide_character_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint style_guide_character_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint style_guide_character_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint style_guide_character_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index style_guide_character_source_edge_current_claim_key
  on core.style_guide_character_source_edge (style_guide_id, character_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index style_guide_character_source_edge_character_id_idx on core.style_guide_character_source_edge (character_id);
create index style_guide_character_source_edge_licensor_idx on core.style_guide_character_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index style_guide_character_source_edge_direct_current_idx
  on core.style_guide_character_source_edge (style_guide_id, character_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on core.style_guide_character_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on core.style_guide_character_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on core.style_guide_character_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'core.style_guide_character', 'style_guide_id', 'character_id');

alter table core.style_guide_character_source_edge enable row level security;

create policy shared_read on core.style_guide_character_source_edge
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.style_guide_character_source_edge from public, anon, authenticated;
grant select on core.style_guide_character_source_edge to authenticated;
grant all on core.style_guide_character_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on core.style_guide_character_source_edge from service_role;

comment on table core.style_guide_character_source_edge is
  'Per-source support evidence for the style guide <-> character relationship (issue #2334). '
  'Supports core.style_guide_character, which already existed on main and is deliberately left unaltered. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column core.style_guide_character_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column core.style_guide_character_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column core.style_guide_character_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column core.style_guide_character_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.5 dam.asset_property_source_edge
-- Supports the canonical bridge dam.asset_property, created alongside it.
create table dam.asset_property_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  asset_id          uuid not null references dam.asset(id) on update cascade on delete cascade,
  property_id       uuid not null references core.property(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint asset_property_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint asset_property_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint asset_property_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint asset_property_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint asset_property_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint asset_property_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint asset_property_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index asset_property_source_edge_current_claim_key
  on dam.asset_property_source_edge (asset_id, property_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index asset_property_source_edge_property_id_idx on dam.asset_property_source_edge (property_id);
create index asset_property_source_edge_licensor_idx on dam.asset_property_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index asset_property_source_edge_direct_current_idx
  on dam.asset_property_source_edge (asset_id, property_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on dam.asset_property_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on dam.asset_property_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on dam.asset_property_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'dam.asset_property', 'asset_id', 'property_id');

alter table dam.asset_property_source_edge enable row level security;

revoke all on dam.asset_property_source_edge from public, anon, authenticated;
grant all on dam.asset_property_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on dam.asset_property_source_edge from service_role;

comment on table dam.asset_property_source_edge is
  'Per-source support evidence for the asset <-> property relationship (issue #2334). '
  'Supports the canonical bridge dam.asset_property, created alongside it. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column dam.asset_property_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column dam.asset_property_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column dam.asset_property_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column dam.asset_property_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.6 dam.asset_character_source_edge
-- Supports dam.asset_character, which already existed on main and is deliberately left unaltered.
create table dam.asset_character_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  asset_id          uuid not null references dam.asset(id) on update cascade on delete cascade,
  character_id      uuid not null references core.character(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint asset_character_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint asset_character_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint asset_character_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint asset_character_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint asset_character_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint asset_character_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint asset_character_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index asset_character_source_edge_current_claim_key
  on dam.asset_character_source_edge (asset_id, character_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index asset_character_source_edge_character_id_idx on dam.asset_character_source_edge (character_id);
create index asset_character_source_edge_licensor_idx on dam.asset_character_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index asset_character_source_edge_direct_current_idx
  on dam.asset_character_source_edge (asset_id, character_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on dam.asset_character_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on dam.asset_character_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on dam.asset_character_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'dam.asset_character', 'asset_id', 'character_id');

alter table dam.asset_character_source_edge enable row level security;

revoke all on dam.asset_character_source_edge from public, anon, authenticated;
grant all on dam.asset_character_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on dam.asset_character_source_edge from service_role;

comment on table dam.asset_character_source_edge is
  'Per-source support evidence for the asset <-> character relationship (issue #2334). '
  'Supports dam.asset_character, which already existed on main and is deliberately left unaltered. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column dam.asset_character_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column dam.asset_character_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column dam.asset_character_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column dam.asset_character_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.7 dam.asset_style_guide_source_edge
-- Supports the canonical bridge dam.asset_style_guide, created alongside it.
create table dam.asset_style_guide_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  asset_id          uuid not null references dam.asset(id) on update cascade on delete cascade,
  style_guide_id    uuid not null references core.style_guide(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint asset_style_guide_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint asset_style_guide_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint asset_style_guide_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint asset_style_guide_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint asset_style_guide_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint asset_style_guide_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint asset_style_guide_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index asset_style_guide_source_edge_current_claim_key
  on dam.asset_style_guide_source_edge (asset_id, style_guide_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index asset_style_guide_source_edge_style_guide_id_idx on dam.asset_style_guide_source_edge (style_guide_id);
create index asset_style_guide_source_edge_licensor_idx on dam.asset_style_guide_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index asset_style_guide_source_edge_direct_current_idx
  on dam.asset_style_guide_source_edge (asset_id, style_guide_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on dam.asset_style_guide_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on dam.asset_style_guide_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on dam.asset_style_guide_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'dam.asset_style_guide', 'asset_id', 'style_guide_id');

alter table dam.asset_style_guide_source_edge enable row level security;

revoke all on dam.asset_style_guide_source_edge from public, anon, authenticated;
grant all on dam.asset_style_guide_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on dam.asset_style_guide_source_edge from service_role;

comment on table dam.asset_style_guide_source_edge is
  'Per-source support evidence for the asset <-> style guide relationship (issue #2334). '
  'Supports the canonical bridge dam.asset_style_guide, created alongside it. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column dam.asset_style_guide_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column dam.asset_style_guide_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column dam.asset_style_guide_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column dam.asset_style_guide_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';

-- 4.8 dam.asset_franchise_source_edge
-- Supports the canonical bridge dam.asset_franchise, created alongside it.
create table dam.asset_franchise_source_edge (
  id                uuid primary key default gen_random_uuid(),

  -- The pair this claim is about.
  asset_id          uuid not null references dam.asset(id) on update cascade on delete cascade,
  franchise_id      uuid not null references core.franchise(id) on update cascade on delete cascade,

  -- Whose claim it is. Part of identity, because source ids collide across licensors.
  licensor_id       uuid not null references core.licensor(id) on delete restrict,
  source_system     text not null,
  source_id         text,
  source_evidence   text,

  -- The three-way split. is_direct_source_relationship is GENERATED: it is derived from
  -- evidence_kind and cannot be supplied, defaulted over, or corrected by a loader.
  evidence_kind     core.relationship_evidence_kind not null,
  is_direct_source_relationship boolean generated always as
                      (evidence_kind = 'direct_source_assertion') stored,

  -- Weight for the two INFERRED kinds only.
  observation_count integer not null default 0,
  confidence        numeric(5,4),

  -- Supersession, not deletion. Withdrawing a claim is a status change; the historical
  -- record of what a source once asserted survives it.
  is_current        boolean not null default true,
  superseded_at     timestamptz,
  superseded_reason text,

  metadata          jsonb not null default '{}'::jsonb,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint asset_franchise_source_edge_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  -- A present source_id must be a real key, never an empty string masquerading as one.
  constraint asset_franchise_source_edge_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0),

  constraint asset_franchise_source_edge_observation_count_non_negative
    check (observation_count >= 0),

  constraint asset_franchise_source_edge_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),

  -- A direct source assertion is not a probability. Carrying a confidence score on one
  -- would invite a reader to compare it against an inferred row's score as if the two
  -- were the same kind of number.
  constraint asset_franchise_source_edge_direct_has_no_confidence
    check (evidence_kind <> 'direct_source_assertion'
           or (confidence is null and observation_count = 0)),

  -- is_current and superseded_at are two views of one fact and may never disagree.
  constraint asset_franchise_source_edge_supersession_consistent
    check (is_current = (superseded_at is null)),

  constraint asset_franchise_source_edge_superseded_reason_only_when_superseded
    check (superseded_reason is null or superseded_at is not null)
);

-- One CURRENT claim per source, per licensor, per pair, per kind. A source may hold both
-- a direct assertion and a co-occurrence observation about the same pair -- those are
-- different facts -- but it may not hold two live copies of the same one. Superseded rows
-- are outside the index and accumulate freely as history.
create unique index asset_franchise_source_edge_current_claim_key
  on dam.asset_franchise_source_edge (asset_id, franchise_id, licensor_id, source_system, evidence_kind)
  where is_current;

create index asset_franchise_source_edge_franchise_id_idx on dam.asset_franchise_source_edge (franchise_id);
create index asset_franchise_source_edge_licensor_idx on dam.asset_franchise_source_edge (licensor_id);

-- Serving the canonical-edge guard: it asks "is there current direct support for this
-- pair?" on every write to the bridge.
create index asset_franchise_source_edge_direct_current_idx
  on dam.asset_franchise_source_edge (asset_id, franchise_id)
  where is_current and evidence_kind = 'direct_source_assertion';

create trigger set_updated_at before update on dam.asset_franchise_source_edge
  for each row execute function app.set_updated_at();

create trigger refuse_delete_of_current_support
  before delete on dam.asset_franchise_source_edge
  for each row execute function core.refuse_delete_of_current_support_edge();

-- Review finding H-1: withdrawing the last current direct assertion by UPDATE is the
-- same orphaning the delete guard above refuses, so it is refused the same way.
create trigger refuse_unsupporting_update
  before update on dam.asset_franchise_source_edge
  for each row execute function core.refuse_unsupporting_update_of_support_edge(
    'dam.asset_franchise', 'asset_id', 'franchise_id');

alter table dam.asset_franchise_source_edge enable row level security;

revoke all on dam.asset_franchise_source_edge from public, anon, authenticated;
grant all on dam.asset_franchise_source_edge to service_role;
-- Review finding M-1: TRUNCATE never fires row-level DELETE triggers, so leaving it in
-- ALL would let a truncate-and-reload loader erase every current claim past the guard.
revoke truncate on dam.asset_franchise_source_edge from service_role;

comment on table dam.asset_franchise_source_edge is
  'Per-source support evidence for the asset <-> franchise relationship (issue #2334). '
  'Supports the canonical bridge dam.asset_franchise, created alongside it. One row is one source system''s claim about one pair under one licensor. '
  'evidence_kind keeps direct, inferred and co-occurrence claims as DISTINCT facts that are never '
  'merged; only a current direct_source_assertion may support a canonical edge. Withdrawing a claim '
  'is supersession, never deletion, and deleting current support -- directly or by cascade -- is '
  'refused. Seeded empty: #2334 authorizes no licensed evidence.';
comment on column dam.asset_franchise_source_edge.licensor_id is
  'The licensor whose source made this claim. NOT NULL and part of the identity key, because '
  'integer source ids collide across licensors and a bare source-id join misattributes one '
  'licensor''s relationship to another.';
comment on column dam.asset_franchise_source_edge.is_direct_source_relationship is
  'GENERATED from evidence_kind. Never write it, and never treat it as a settable flag: it exists '
  'so an inferred or co-occurrence row is structurally incapable of claiming to be direct.';
comment on column dam.asset_franchise_source_edge.confidence is
  'Weight for inferred and co-occurrence evidence only, in [0,1]. Always NULL on a direct source '
  'assertion, which is a statement of fact rather than a probability.';
comment on column dam.asset_franchise_source_edge.is_current is
  'False once the source withdrew or replaced this claim. Only CURRENT support blocks deletion of '
  'an endpoint or a canonical edge, and only CURRENT direct support sustains a canonical edge.';
