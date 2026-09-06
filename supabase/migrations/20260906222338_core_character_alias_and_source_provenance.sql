-- derived-from: none
--
-- core.character_alias, and collision-proof / freshness-aware core.taxonomy_source_ref.
-- Issue #2355 (structural successor to #1090). Claim issue #2410,
-- reserved version 20260906222338.
--
-- WHY THIS EXISTS
-- ---------------
-- The same character is named differently by every licensor and every portal. Without a
-- canonical alias contract, "Sonic" observed in one feed and "Sonic the Hedgehog"
-- observed in another are two unrelated strings, and a royalty or approval decision
-- ends up resting on a name coincidence.
--
-- The second half of the problem is provenance. core.taxonomy_source_ref already records
-- "system S, table T, id I said this about entity E", but it records nothing about WHOSE
-- id I is. Licensor source ids collide: Disney and Sega both number from small integers,
-- so a bare source id is not an identity. The existing unique key
-- (source_system, source_table, source_id) is GLOBAL, and every importer in this
-- repository upserts through `on conflict (source_system, source_table, source_id)
-- do update set entity_id = excluded.entity_id`. That upsert is the collision: two
-- licensors reusing one small integer would silently overwrite each other's provenance
-- row, and the surviving row would attribute one licensor's character to the other.
--
-- WHAT THIS IS NOT
-- ----------------
-- This migration is ADDITIVE. It creates one table, adds columns, constraints, indexes
-- and three triggers (two guards and one freshness bump), and seeds NO rows: #2355 authorizes no curated Master Data,
-- and no licensed evidence.
--
-- It deliberately does NOT drop, replace or narrow the existing
-- taxonomy_source_ref_source_system_source_table_source_id_key unique constraint. That
-- constraint is the `on conflict` target of at least a dozen already-applied importer
-- functions owned by other lanes; removing it would break every one of them at runtime.
-- The collision is therefore closed by REFUSING the dangerous write rather than by
-- re-keying the table: a row whose provenance already belongs to one licensor can never
-- be repointed to another licensor's entity. A silent misattribution becomes a loud
-- failure, with no importer signature changed.
--
-- It also does NOT alter core.character, core.property, core.licensor or core.franchise.
-- core.character is a read for this issue, so the licensor consistency of an alias is
-- enforced by a trigger rather than by a composite foreign key: a composite foreign key
-- would require a new unique index ON core.character, which this claim does not own.
--
-- GRANDFATHERING
-- --------------
-- Existing taxonomy_source_ref rows are preserved untouched. No UPDATE is issued against
-- the table (it already carries ColdLion circuit-breaker triggers on insert, update and
-- delete, and a backfill would be refused whenever that breaker is tripped). The
-- freshness columns are therefore added nullable, and their "must be present" rules are
-- declared NOT VALID so they bind every new and every modified row while leaving
-- pre-existing rows exactly as they are. Do not VALIDATE them.
--
-- STRICTNESS, CALIBRATED
-- ----------------------
-- Licensor derivation is ATTEMPTED for the four licensor-scoped core kinds
-- (licensor, property, character, franchise), and the derived value is what gets
-- recorded. It is deliberately NOT required to be non-null. core.property.licensor_id is
-- NULLABLE (20260621150815_app_core.sql defines it `references core.licensor(id) on
-- delete set null`, and 20260829004145_separate_property_and_character.sql builds an
-- explicit orphan-property list), and core.character.licensor_id is nullable too and
-- core.character can now be populated by curated loads. Raising on a null derived
-- licensor would therefore turn writes this table accepts today into hard failures for
-- every licensor-less property. So a licensor-less target records a null
-- source_licensor_id -- honest about having no owner -- while a target that does not
-- exist at all still raises, and a caller-supplied licensor that contradicts the derived
-- one (including contradicting "this entity has no licensor") still raises.

-- ---------------------------------------------------------------------------
-- 1. core.taxonomy_source_ref -- source identity, target integrity, freshness
-- ---------------------------------------------------------------------------

-- Collision-proof source identity. Nullable in the catalog so no existing row is
-- rewritten; every new or modified row is filled and checked by the guard trigger
-- below, which is the thing that actually enforces it.
alter table core.taxonomy_source_ref
  add column if not exists source_licensor_id uuid
    references core.licensor(id) on delete restrict;

-- Freshness and current-state. first_seen_at/last_seen_at answer "when did the source
-- first and last assert this?"; missing_since records the moment the source stopped
-- asserting it. Rows are never deleted to express absence -- disappearing evidence is
-- exactly the loss this repository refuses.
alter table core.taxonomy_source_ref
  add column if not exists first_seen_at timestamptz;
alter table core.taxonomy_source_ref
  add column if not exists last_seen_at timestamptz;
alter table core.taxonomy_source_ref
  add column if not exists missing_since timestamptz;

alter table core.taxonomy_source_ref
  alter column first_seen_at set default now();
alter table core.taxonomy_source_ref
  alter column last_seen_at set default now();

-- Current state is derived, never independently editable: a row is current exactly while
-- the source has not been observed to have dropped it.
alter table core.taxonomy_source_ref
  add column if not exists is_current boolean
    generated always as (missing_since is null) stored;

do $freshness_constraints$
begin
  -- NOT VALID on purpose: binds every new and modified row, exempts the pre-existing
  -- ones. Validating these would require rewriting rows this issue must preserve.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'core.taxonomy_source_ref'::regclass
      and conname = 'taxonomy_source_ref_first_seen_present'
  ) then
    alter table core.taxonomy_source_ref
      add constraint taxonomy_source_ref_first_seen_present
      check (first_seen_at is not null) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'core.taxonomy_source_ref'::regclass
      and conname = 'taxonomy_source_ref_last_seen_present'
  ) then
    alter table core.taxonomy_source_ref
      add constraint taxonomy_source_ref_last_seen_present
      check (last_seen_at is not null) not valid;
  end if;

  -- These two hold trivially for legacy rows (all three columns are null there), so they
  -- are added VALID and bind everything.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'core.taxonomy_source_ref'::regclass
      and conname = 'taxonomy_source_ref_seen_order'
  ) then
    alter table core.taxonomy_source_ref
      add constraint taxonomy_source_ref_seen_order
      check (first_seen_at is null or last_seen_at is null or last_seen_at >= first_seen_at);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'core.taxonomy_source_ref'::regclass
      and conname = 'taxonomy_source_ref_missing_after_first_seen'
  ) then
    alter table core.taxonomy_source_ref
      add constraint taxonomy_source_ref_missing_after_first_seen
      check (missing_since is null or first_seen_at is null or missing_since >= first_seen_at);
  end if;
end
$freshness_constraints$;

create index if not exists taxonomy_source_ref_entity_idx
  on core.taxonomy_source_ref (entity_schema, entity_table, entity_id);

create index if not exists taxonomy_source_ref_source_licensor_idx
  on core.taxonomy_source_ref (source_licensor_id);

-- Read path for "what does this source currently assert?".
create index if not exists taxonomy_source_ref_current_idx
  on core.taxonomy_source_ref (source_system, source_table)
  where missing_since is null;

-- ---------------------------------------------------------------------------
-- 2. The guard that makes source identity and target integrity real
-- ---------------------------------------------------------------------------
create or replace function core.guard_taxonomy_source_ref_identity()
returns trigger
language plpgsql
security definer
set search_path = core, pg_catalog
as $guard$
declare
  v_target_regclass regclass;
  v_target_exists   boolean;
  v_derived         uuid;
  v_old_derived     uuid;
  v_target_changed  boolean;
  v_source_changed  boolean;
  v_licensor_changed boolean;
  v_licensor_scoped constant text[] := array['licensor', 'property', 'character', 'franchise'];
begin
  -- WHAT THIS WRITE ACTUALLY TOUCHES. Every rule below is scoped to the part of the row
  -- it governs. An UPDATE that only records freshness (last_seen_at, missing_since) must
  -- stay possible on a pre-#2355 row, including one whose source key or target was never
  -- filled in properly -- otherwise the very writes this migration exists to make would
  -- be refused on exactly the legacy rows that need them.
  v_target_changed := tg_op = 'INSERT'
    or (old.entity_schema, old.entity_table, old.entity_id)
         is distinct from (new.entity_schema, new.entity_table, new.entity_id);

  v_source_changed := tg_op = 'INSERT'
    or (old.source_system, old.source_table, old.source_id)
         is distinct from (new.source_system, new.source_table, new.source_id);

  v_licensor_changed := tg_op = 'INSERT'
    or old.source_licensor_id is distinct from new.source_licensor_id;

  -- Blank strings are not identifiers. A blank source_id in particular is the classic
  -- way a whole feed collapses onto one provenance row. Checked on INSERT and on any
  -- write that actually SETS these columns -- never on a freshness-only update, which
  -- would otherwise freeze every legacy row that already carries a blank key.
  if v_target_changed then
    if new.entity_schema is null or length(btrim(new.entity_schema)) = 0 then
      raise exception 'core.taxonomy_source_ref refused: entity_schema must be a real schema name'
        using errcode = 'P0001';
    end if;
    if new.entity_table is null or length(btrim(new.entity_table)) = 0 then
      raise exception 'core.taxonomy_source_ref refused: entity_table must be a real table name'
        using errcode = 'P0001';
    end if;
  end if;

  if v_source_changed then
    if new.source_system is null or length(btrim(new.source_system)) = 0
       or new.source_table is null or length(btrim(new.source_table)) = 0
       or new.source_id is null or length(btrim(new.source_id)) = 0 then
      raise exception
        'core.taxonomy_source_ref refused: source_system, source_table and source_id must all be non-blank -- provenance without a named source is not provenance'
        using errcode = 'P0001';
    end if;
  end if;

  -- KIND-SAFE TARGET INTEGRITY. entity_id is an untyped uuid: nothing in the catalog
  -- stops it naming a row in a completely different table, or no row at all. Checked
  -- only when the target actually changes, so pre-existing rows whose target has since
  -- been retired remain editable for their freshness fields.
  if v_target_changed then
    v_target_regclass := to_regclass(
      quote_ident(btrim(new.entity_schema)) || '.' || quote_ident(btrim(new.entity_table)));
    if v_target_regclass is null then
      raise exception
        'core.taxonomy_source_ref refused: entity_schema/entity_table %.% is not a real table',
        new.entity_schema, new.entity_table
        using errcode = 'P0001';
    end if;
    if new.entity_id is null then
      raise exception 'core.taxonomy_source_ref refused: entity_id must name a row'
        using errcode = 'P0001';
    end if;
  end if;

  -- COLLISION-PROOF SOURCE IDENTITY. Derive the licensor the provenance actually belongs
  -- to, from the entity it points at. A supplied value is checked, never trusted.
  -- Scoped exactly like the target-integrity check above. Re-deriving on EVERY write
  -- would mean a target that has since been re-licensed (or orphaned) makes every later
  -- write to its provenance row fail -- including the missing_since / last_seen_at writes
  -- this change exists to make -- because the derived licensor no longer matches the
  -- licensor already stamped on the row, which the immutability rule below forbids
  -- changing. So it runs only when the write actually touches the target or the licensor.
  if (v_target_changed or v_licensor_changed)
     and btrim(new.entity_schema) = 'core' and btrim(new.entity_table) = any (v_licensor_scoped) then
    -- Static, one branch per licensor-scoped kind. No dynamic SQL: the set of kinds
    -- that carry a licensor is a settled business fact, not a runtime lookup, and a
    -- statically written branch is the only form a reviewer can verify by reading it.
    case btrim(new.entity_table)
      when 'licensor' then
        select l.id into v_derived from core.licensor l where l.id = new.entity_id;
      when 'property' then
        select p.licensor_id into v_derived from core.property p where p.id = new.entity_id;
      when 'character' then
        select c.licensor_id into v_derived from core.character c where c.id = new.entity_id;
      when 'franchise' then
        select f.licensor_id into v_derived from core.franchise f where f.id = new.entity_id;
    end case;
    v_target_exists := found;

    -- KIND-SAFE TARGET INTEGRITY. entity_id is an untyped uuid: nothing in the catalog
    -- stops it naming a row in a different table, or no row at all. Checked only when
    -- the target actually changes, so pre-existing rows whose target has since been
    -- retired stay editable for their freshness fields.
    if v_target_changed and not v_target_exists then
      raise exception
        'core.taxonomy_source_ref refused: no row % in %.% -- provenance may not point at a non-existent entity',
        new.entity_id, new.entity_schema, new.entity_table
        using errcode = 'P0001';
    end if;

    -- A NULL DERIVED LICENSOR IS A FACT, NOT A FAULT. core.property.licensor_id is
    -- nullable and orphan properties exist by design, so refusing here would convert
    -- writes this table accepts today into hard failures. The derived value -- null
    -- included -- is what gets recorded. A caller-supplied value is still never trusted:
    -- it must equal the derived one, and when the entity has no licensor at all the only
    -- honest supplied value is none.
    if new.source_licensor_id is distinct from v_derived then
      if new.source_licensor_id is null then
        new.source_licensor_id := v_derived;
      elsif v_derived is null then
        raise exception
          'core.taxonomy_source_ref refused: source_licensor_id % was supplied, but %.% row % has no licensor of its own -- provenance may not be attributed to a licensor the entity does not belong to',
          new.source_licensor_id, new.entity_schema, new.entity_table, new.entity_id
          using errcode = 'P0001';
      else
        raise exception
          'core.taxonomy_source_ref refused: source_licensor_id % disagrees with the licensor % of the entity it points at',
          new.source_licensor_id, v_derived
          using errcode = 'P0001';
      end if;
    end if;
  end if;

  -- THE ANTI-COLLISION RULE. The pre-existing unique key
  -- (source_system, source_table, source_id) is global, and every importer upserts into
  -- it with `do update set entity_id = excluded.entity_id`. Left alone, a second licensor
  -- reusing the same small integer id would quietly capture the first licensor's
  -- provenance row. Once a row's licensor is known it is immutable: the second licensor
  -- gets an error instead of the first licensor's evidence.
  if tg_op = 'UPDATE'
     and old.source_licensor_id is not null
     and new.source_licensor_id is distinct from old.source_licensor_id then
    raise exception
      'core.taxonomy_source_ref refused: (%, %, %) is already licensor %''s provenance; repointing it to licensor % would attribute one licensor''s entity to another. Source ids collide across licensors -- record a separate row.',
      new.source_system, new.source_table, new.source_id,
      old.source_licensor_id, new.source_licensor_id
      using errcode = 'P0001';
  end if;

  -- THE SAME RULE FOR THE ROWS WE GRANDFATHERED. Every pre-#2355 row carries
  -- source_licensor_id null, so the rule above -- which keys off the OLD licensor --
  -- has nothing to compare against on the FIRST conflicting upsert, and the block
  -- higher up would simply stamp the incoming licensor onto the stolen row. Those
  -- legacy rows are precisely the ones a colliding importer reaches first, so the
  -- owner is re-derived from the OLD target instead. Deliberately silent when the old
  -- target is gone or was never licensor-scoped: a row whose old entity has since been
  -- retired stays editable for its freshness fields, exactly as before.
  if tg_op = 'UPDATE'
     and old.source_licensor_id is null
     and new.source_licensor_id is not null
     and v_target_changed
     and btrim(old.entity_schema) = 'core'
     and btrim(old.entity_table) = any (v_licensor_scoped) then
    case btrim(old.entity_table)
      when 'licensor' then
        select l.id into v_old_derived from core.licensor l where l.id = old.entity_id;
      when 'property' then
        select p.licensor_id into v_old_derived from core.property p where p.id = old.entity_id;
      when 'character' then
        select c.licensor_id into v_old_derived from core.character c where c.id = old.entity_id;
      when 'franchise' then
        select f.licensor_id into v_old_derived from core.franchise f where f.id = old.entity_id;
    end case;

    if v_old_derived is not null and v_old_derived <> new.source_licensor_id then
      raise exception
        'core.taxonomy_source_ref refused: (%, %, %) is licensor %''s provenance by the entity it already points at; repointing it to licensor % would attribute one licensor''s entity to another. Source ids collide across licensors -- record a separate row.',
        new.source_system, new.source_table, new.source_id,
        v_old_derived, new.source_licensor_id
        using errcode = 'P0001';
    end if;
  end if;

  -- FRESHNESS. Filled here rather than by column defaults so that an explicit null from
  -- an importer still produces a usable row, and so first_seen_at can never be moved
  -- forward by a later sighting.
  if tg_op = 'INSERT' then
    new.first_seen_at := coalesce(new.first_seen_at, now());
    new.last_seen_at  := coalesce(new.last_seen_at, new.first_seen_at);
  else
    new.first_seen_at := coalesce(new.first_seen_at, old.first_seen_at, old.created_at);
    new.last_seen_at  := coalesce(new.last_seen_at, old.last_seen_at, new.first_seen_at);
    if old.first_seen_at is not null and new.first_seen_at > old.first_seen_at then
      -- "First seen" is a fact about the past. A later observation updates last_seen_at.
      new.first_seen_at := old.first_seen_at;
    end if;
    -- last_seen_at is NOT advanced here. Advancing it on every update would log a
    -- metadata-only correction as a fresh source sighting. The advance lives in
    -- core.bump_taxonomy_source_ref_last_seen, whose trigger fires only when the
    -- source-facing columns are actually re-supplied.
  end if;

  return new;
end
$guard$;

revoke execute on function core.guard_taxonomy_source_ref_identity() from public;

drop trigger if exists a_taxonomy_source_ref_identity_guard on core.taxonomy_source_ref;
-- Named to sort before the ColdLion breaker guards: identity and target integrity are
-- cheaper to refuse than a breaker audit write.
create trigger a_taxonomy_source_ref_identity_guard
  before insert or update on core.taxonomy_source_ref
  for each row execute function core.guard_taxonomy_source_ref_identity();

-- A RE-ASSERTION ADVANCES last_seen_at -- AND NOTHING ELSE DOES. Every importer in this
-- repository upserts with `on conflict ... do update set entity_id = excluded.entity_id`
-- and names no freshness column, so without this the column could never advance and
-- "when the source most recently still asserted this" would be a permanent lie. But
-- advancing on ANY update is the opposite error: a metadata-only correction (fixing
-- evidence notes, clearing missing_since, an unrelated column) would be recorded as a
-- fresh sighting the source never made. The trigger is therefore restricted with
-- UPDATE OF to the source-facing columns: it fires only when the write actually
-- re-supplies what the source said, whether or not the value changed. Two further
-- exclusions, both deliberate: an explicit last_seen_at from the caller is respected
-- rather than overwritten, and an update that RECORDS ABSENCE (missing_since present)
-- is not a sighting.
--
-- missing_since is in the UPDATE OF list for the RE-APPEARANCE case: clearing it is the
-- source asserting this again after an absence, which is a sighting and must advance
-- last_seen_at, or a re-appeared row would keep claiming it was last seen before it went
-- missing. Listing the column does NOT make recording an absence a sighting -- the
-- function's own `new.missing_since is null` test still refuses that direction.
create or replace function core.bump_taxonomy_source_ref_last_seen()
returns trigger
language plpgsql
security definer
set search_path = core, pg_catalog
as $bump$
begin
  if new.missing_since is null
     and new.last_seen_at is not distinct from old.last_seen_at then
    new.last_seen_at := greatest(new.last_seen_at, now());
  end if;
  return new;
end
$bump$;

revoke execute on function core.bump_taxonomy_source_ref_last_seen() from public;

drop trigger if exists b_taxonomy_source_ref_last_seen on core.taxonomy_source_ref;
-- Named to sort AFTER the identity guard (which fills last_seen_at) and before the
-- ColdLion breaker guards.
create trigger b_taxonomy_source_ref_last_seen
  before update of
      entity_schema, entity_table, entity_id,
      source_system, source_table, source_id, source_licensor_id,
      missing_since
    on core.taxonomy_source_ref
  for each row execute function core.bump_taxonomy_source_ref_last_seen();

comment on column core.taxonomy_source_ref.source_licensor_id is
  'The licensor this provenance belongs to, derived from the entity it points at and never '
  'trusted from the caller. Source ids are unique only within a licensor -- Disney and Sega '
  'both number from small integers -- so a bare source id is not an identity. Null on rows that '
  'predate issue #2355, on rows pointing at a kind which is not licensor-scoped, and on rows '
  'whose target genuinely has no licensor of its own (core.property.licensor_id and '
  'core.character.licensor_id are both nullable, and orphan properties exist by design).';
comment on column core.taxonomy_source_ref.first_seen_at is
  'When this source assertion was first recorded. Never moves forward. Null only on rows that '
  'predate issue #2355; use created_at for those.';
comment on column core.taxonomy_source_ref.last_seen_at is
  'When the source most recently still asserted this. Advanced to now() by '
  'core.bump_taxonomy_source_ref_last_seen, whose trigger fires only on an update that '
  're-supplies the source-facing columns, so an importer upserting only entity_id keeps it '
  'honest without naming it while a metadata-only correction is not logged as a sighting. Not '
  'advanced when the caller supplies a value of its own, and not advanced by an update that '
  'sets missing_since -- recording an absence is not a sighting. Null only on pre-#2355 rows.';
comment on column core.taxonomy_source_ref.missing_since is
  'When the source stopped asserting this. Absence is recorded, never deleted: a vanished '
  'source row is evidence, and deleting it would destroy the audit trail behind a royalty '
  'or approval decision.';
comment on column core.taxonomy_source_ref.is_current is
  'Generated: true while missing_since is null. Never write it directly.';

-- ---------------------------------------------------------------------------
-- 3. core.character_alias
-- ---------------------------------------------------------------------------
create table if not exists core.character_alias (
  id                uuid primary key default gen_random_uuid(),

  -- ON DELETE RESTRICT: a canonical character that aliases resolve to may not vanish
  -- underneath them. Retiring a character is a status change, never a delete.
  character_id      uuid not null references core.character(id) on delete restrict,

  -- Denormalized on purpose: it is the scope of alias uniqueness. It cannot drift --
  -- the guard trigger below requires it to equal the parent character's licensor_id.
  -- (core.franchise_alias binds the equivalent field with a composite foreign key; that
  -- is not available here because it would need a new unique index ON core.character,
  -- which issue #2355 reads but does not own.)
  licensor_id       uuid not null references core.licensor(id) on delete restrict,

  alias             text not null,

  -- Source-neutral normalization, reusing the repository's single frozen observation
  -- normalizer (contract popsg-property-observation-v1) exactly as core.franchise_alias
  -- and core.property_alias do. A second, divergent normalizer would let the same
  -- observed string resolve differently depending on which table matched it.
  normalized_alias  text generated always as
                      (core.normalize_popsg_property_observation(alias)) stored,

  -- WHO said this name. An alias with no source is a name coincidence with a row id.
  source_system     text not null,
  source_id         text,
  evidence_notes    text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text,
  updated_by        text,

  constraint character_alias_alias_not_blank
    check (length(btrim(alias)) > 0),

  -- An alias that normalizes to nothing can never match an observation, and would
  -- collide with every other such row on the unique index below. Also rejects '---'.
  constraint character_alias_normalized_not_blank
    check (length(core.normalize_popsg_property_observation(alias)) > 0),

  constraint character_alias_source_system_not_blank
    check (length(btrim(source_system)) > 0),

  constraint character_alias_source_id_not_blank
    check (source_id is null or length(btrim(source_id)) > 0)
);

-- THE SAFETY PROPERTY. Within one licensor, a normalized observed name may never resolve
-- to two different characters. Scoped to the licensor because the same character name
-- under a different licensor is legitimate and common; scoped no tighter because
-- per-character uniqueness would permit exactly the ambiguity this index refuses.
create unique index if not exists character_alias_licensor_norm_key
  on core.character_alias (licensor_id, normalized_alias);

create index if not exists character_alias_character_idx
  on core.character_alias (character_id);

create index if not exists character_alias_licensor_idx
  on core.character_alias (licensor_id);

-- Two licensors may each publish source id '5'. The alias's own source key is therefore
-- unique per licensor, never globally.
create unique index if not exists character_alias_licensor_source_key
  on core.character_alias (licensor_id, source_system, source_id)
  where source_id is not null;

drop trigger if exists set_updated_at on core.character_alias;
create trigger set_updated_at before update on core.character_alias
  for each row execute function app.set_updated_at();

create or replace function core.guard_character_alias_licensor()
returns trigger
language plpgsql
security definer
set search_path = core, pg_catalog
as $guard$
declare
  v_parent_licensor uuid;
  v_found           boolean;
begin
  select c.licensor_id, true into v_parent_licensor, v_found
  from core.character c
  where c.id = new.character_id;

  if not coalesce(v_found, false) then
    raise exception 'core.character_alias refused: no core.character row %', new.character_id
      using errcode = 'P0001';
  end if;

  if v_parent_licensor is null then
    raise exception
      'core.character_alias refused: core.character % has no licensor, so an alias for it cannot be scoped -- an unscoped alias is a name coincidence, not an identity',
      new.character_id
      using errcode = 'P0001';
  end if;

  if new.licensor_id <> v_parent_licensor then
    raise exception
      'core.character_alias refused: licensor_id % is not the licensor % of character % -- an alias may never cross a licensor boundary',
      new.licensor_id, v_parent_licensor, new.character_id
      using errcode = 'P0001';
  end if;

  return new;
end
$guard$;

revoke execute on function core.guard_character_alias_licensor() from public;

drop trigger if exists character_alias_licensor_guard on core.character_alias;
create trigger character_alias_licensor_guard
  before insert or update on core.character_alias
  for each row execute function core.guard_character_alias_licensor();

alter table core.character_alias enable row level security;

-- Read for the same role set every other core.* entity uses. There is deliberately no
-- write policy for `authenticated`: RLS and GRANTs independently keep browser roles
-- read-only, exactly as core.franchise_alias does.
drop policy if exists shared_read on core.character_alias;
create policy shared_read on core.character_alias
  for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

revoke all on core.character_alias from public, anon, authenticated;
grant select on core.character_alias to authenticated;
grant all    on core.character_alias to service_role;

comment on table core.character_alias is
  'Observed character names resolving to a canonical core.character, with the source that said '
  'so (issue #2355, successor to #1090). Uniqueness is scoped to the licensor, and a guard '
  'trigger makes a cross-licensor alias unrepresentable. Normalization reuses '
  'core.normalize_popsg_property_observation (contract popsg-property-observation-v1) rather '
  'than adding a second normalizer. Browser roles are read-only. No rows are seeded by the '
  'creating migration: #2355 authorizes structure only.';
comment on column core.character_alias.licensor_id is
  'The licensor of the parent character, carried here as the scope of alias uniqueness. Not '
  'independently editable: core.guard_character_alias_licensor requires it to equal the parent '
  'character''s licensor_id on every insert and update.';
comment on column core.character_alias.normalized_alias is
  'Generated by core.normalize_popsg_property_observation. Never write it directly, and never '
  'change that function without rebaselining every generated column that depends on it.';
comment on column core.character_alias.source_system is
  'Which system or portal used this name: wb_starlabs | nbcu | disney_opa | paramount | '
  'coldlion | designflow_plm | manual. Required -- an alias with no source cannot be weighed '
  'against a conflicting one.';
comment on column core.character_alias.source_id is
  'That source system''s own key for the character, held as text. Unique per licensor, never '
  'globally: small integer source ids are reused across licensors.';
