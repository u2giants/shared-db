-- Issue #2123: give the two Tier-2 licensor character source tables the same
-- core.character promotion contract the Tier-1 tables already carry.
--
-- derived-from: none
--
-- WHY. docs/core-character-backfill-source-decision-20260902.md sec.3 sorts the
-- licensor character source tables by one question: does the table carry a
-- core_character_id column pointing at core.character? Tier 1 does, so a
-- resolution can be recorded against the row that produced it. Tier 2 does not,
-- so plm.wb_character_normalized and plm.wildbrain_character cannot be promoted
-- at all until a structural migration adds one. This is that migration.
--
-- WHAT SHAPE. The contract is copied from plm.opa_character
-- (20260814040000_opa_property_character_normalize.sql), which is the Tier-1
-- table that carries the resolver-and-timestamp audit check. Same columns, same
-- status vocabulary, same check body, same partial index. A resolution is only
-- real if it names both a target and a resolver. Do not route around that check
-- with a direct insert into core.character.
--
-- NOTE ON THE FOREIGN KEY. 20260823133150 dropped the Tier-1 core_character_id
-- foreign keys when it dropped core.character, and 20260829004145 recreated
-- core.character without restoring them. This migration declares the foreign key
-- as the Tier-1 contract was originally authored, on its own two tables only.
-- Restoring the Tier-1 foreign keys is a separate object claim and is not
-- attempted here.
--
-- STRUCTURE ONLY. No row is inserted, updated or promoted by this file. Every
-- existing row lands on the default resolution_status 'unresolved' with a null
-- target, a null resolver and a null timestamp, which the new check accepts.

-- ---------------------------------------------------------------- Warner (wb)

alter table plm.wb_character_normalized
  add column if not exists core_character_id uuid,
  add column if not exists resolution_status text not null default 'unresolved',
  add column if not exists resolution_reason text,
  add column if not exists resolved_at       timestamptz,
  add column if not exists resolved_by       text;

alter table plm.wb_character_normalized
  drop constraint if exists plm_wb_character_normalized_core_character_fk;
alter table plm.wb_character_normalized
  add constraint plm_wb_character_normalized_core_character_fk
  foreign key (core_character_id) references core.character(id) on delete restrict;

alter table plm.wb_character_normalized
  drop constraint if exists plm_wb_character_normalized_resolution_status_ck;
alter table plm.wb_character_normalized
  add constraint plm_wb_character_normalized_resolution_status_ck
  check (resolution_status in ('unresolved','resolved','ambiguous','not_a_character'));

alter table plm.wb_character_normalized
  drop constraint if exists plm_wb_character_normalized_resolution_ck;
alter table plm.wb_character_normalized
  add constraint plm_wb_character_normalized_resolution_ck check (
    (resolution_status = 'resolved'
       and core_character_id is not null and resolved_at is not null
       and resolved_by is not null and btrim(resolved_by) <> '')
    or
    (resolution_status <> 'resolved'
       and core_character_id is null and resolved_at is null and resolved_by is null)
  );

create index if not exists plm_wb_character_normalized_unresolved_idx
  on plm.wb_character_normalized (resolution_status) where resolution_status <> 'resolved';

comment on column plm.wb_character_normalized.core_character_id is
  'Resolved core.character. Null until a resolution is recorded. Identity is licensor plus source id, never source id alone.';

-- ------------------------------------------------------------- WildBrain (DAM)

alter table plm.wildbrain_character
  add column if not exists core_character_id uuid,
  add column if not exists resolution_status text not null default 'unresolved',
  add column if not exists resolution_reason text,
  add column if not exists resolved_at       timestamptz,
  add column if not exists resolved_by       text;

alter table plm.wildbrain_character
  drop constraint if exists plm_wildbrain_character_core_character_fk;
alter table plm.wildbrain_character
  add constraint plm_wildbrain_character_core_character_fk
  foreign key (core_character_id) references core.character(id) on delete restrict;

alter table plm.wildbrain_character
  drop constraint if exists plm_wildbrain_character_resolution_status_ck;
alter table plm.wildbrain_character
  add constraint plm_wildbrain_character_resolution_status_ck
  check (resolution_status in ('unresolved','resolved','ambiguous','not_a_character'));

alter table plm.wildbrain_character
  drop constraint if exists plm_wildbrain_character_resolution_ck;
alter table plm.wildbrain_character
  add constraint plm_wildbrain_character_resolution_ck check (
    (resolution_status = 'resolved'
       and core_character_id is not null and resolved_at is not null
       and resolved_by is not null and btrim(resolved_by) <> '')
    or
    (resolution_status <> 'resolved'
       and core_character_id is null and resolved_at is null and resolved_by is null)
  );

create index if not exists plm_wildbrain_character_unresolved_idx
  on plm.wildbrain_character (resolution_status) where resolution_status <> 'resolved';

comment on column plm.wildbrain_character.core_character_id is
  'Resolved core.character. Null until a resolution is recorded. Identity is licensor plus source id, never source id alone.';

-- ----------------------------------------------------------------- Verification
-- Refuse the apply unless every part of the contract is present on both tables.

do $verify$
declare
  t        text;
  v_tables text[] := array['wb_character_normalized','wildbrain_character'];
  v_n      integer;
begin
  foreach t in array v_tables loop

    -- Five columns, correct types, correct nullability.
    select count(*) into v_n
      from information_schema.columns
     where table_schema = 'plm' and table_name = t
       and (column_name, data_type, is_nullable) in (
             ('core_character_id', 'uuid',                     'YES'),
             ('resolution_status', 'text',                     'NO'),
             ('resolution_reason', 'text',                     'YES'),
             ('resolved_at',       'timestamp with time zone', 'YES'),
             ('resolved_by',       'text',                     'YES'));
    if v_n <> 5 then
      raise exception 'plm.% is missing part of the promotion contract: % of 5 columns present', t, v_n
        using errcode = 'P0001';
    end if;

    -- resolution_status defaults to unresolved, so an existing row is never
    -- silently promoted by this migration.
    select count(*) into v_n
      from information_schema.columns
     where table_schema = 'plm' and table_name = t
       and column_name = 'resolution_status'
       and column_default like '%unresolved%';
    if v_n <> 1 then
      raise exception 'plm.%.resolution_status does not default to unresolved', t
        using errcode = 'P0001';
    end if;

    -- Foreign key to core.character, on delete restrict, validated.
    select count(*) into v_n
      from pg_constraint c
      join pg_class rel on rel.oid = c.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
      join pg_class frel on frel.oid = c.confrelid
      join pg_namespace fns on fns.oid = frel.relnamespace
     where ns.nspname = 'plm' and rel.relname = t
       and c.contype = 'f' and c.confdeltype = 'r' and c.convalidated
       and fns.nspname = 'core' and frel.relname = 'character'
       and c.conkey = array[(select attnum from pg_attribute
                              where attrelid = rel.oid and attname = 'core_character_id')]::smallint[];
    if v_n <> 1 then
      raise exception 'plm.%.core_character_id has no validated on-delete-restrict foreign key to core.character', t
        using errcode = 'P0001';
    end if;

    -- Both named check constraints present and validated.
    select count(*) into v_n
      from pg_constraint c
      join pg_class rel on rel.oid = c.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where ns.nspname = 'plm' and rel.relname = t
       and c.contype = 'c' and c.convalidated
       and c.conname in ('plm_' || t || '_resolution_ck', 'plm_' || t || '_resolution_status_ck');
    if v_n <> 2 then
      raise exception 'plm.% is missing a validated resolution check constraint: % of 2 present', t, v_n
        using errcode = 'P0001';
    end if;

    -- The audit clause itself, not merely a constraint by that name.
    select count(*) into v_n
      from pg_constraint c
      join pg_class rel on rel.oid = c.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where ns.nspname = 'plm' and rel.relname = t
       and c.conname = 'plm_' || t || '_resolution_ck'
       and pg_get_constraintdef(c.oid) like '%resolved_by%'
       and pg_get_constraintdef(c.oid) like '%resolved_at%'
       and pg_get_constraintdef(c.oid) like '%core_character_id%';
    if v_n <> 1 then
      raise exception 'plm.% resolution check does not require target, resolver and timestamp together', t
        using errcode = 'P0001';
    end if;

    -- The unresolved-work index.
    select count(*) into v_n
      from pg_indexes
     where schemaname = 'plm' and tablename = t
       and indexname = 'plm_' || t || '_unresolved_idx';
    if v_n <> 1 then
      raise exception 'plm.% is missing its unresolved-work index', t using errcode = 'P0001';
    end if;

  end loop;

end
$verify$;
