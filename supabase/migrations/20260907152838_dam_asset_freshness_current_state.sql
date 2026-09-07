-- derived-from: none
--
-- Issue #2356; claim #2521; reserved version 20260907152838.
--
-- dam.asset already has the canonical source identity
-- (source_system, source_id) and the scalar licensor_id/property_id compatibility
-- columns used by existing PopDAM callers. This additive migration leaves all of
-- those columns, their foreign keys, and the existing source-identity uniqueness
-- constraint unchanged.
--
-- Existing rows are deliberately not rewritten. The new columns are nullable so
-- their unknown historical freshness stays honest. Defaults make new rows complete,
-- while NOT VALID checks bind new and modified rows without scanning or rewriting
-- the live table. "Current" is the predicate missing_since is null, not a second
-- boolean that could drift away from the timestamp.

alter table dam.asset
  add column if not exists first_seen_at timestamptz;

alter table dam.asset
  add column if not exists last_seen_at timestamptz;

alter table dam.asset
  add column if not exists missing_since timestamptz;

alter table dam.asset
  alter column first_seen_at set default now();

alter table dam.asset
  alter column last_seen_at set default now();

do $freshness_constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'dam.asset'::regclass
      and conname = 'dam_asset_first_seen_present'
  ) then
    alter table dam.asset
      add constraint dam_asset_first_seen_present
      check (first_seen_at is not null) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'dam.asset'::regclass
      and conname = 'dam_asset_last_seen_present'
  ) then
    alter table dam.asset
      add constraint dam_asset_last_seen_present
      check (last_seen_at is not null) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'dam.asset'::regclass
      and conname = 'dam_asset_seen_order'
  ) then
    alter table dam.asset
      add constraint dam_asset_seen_order
      check (
        first_seen_at is null
        or last_seen_at is null
        or last_seen_at >= first_seen_at
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'dam.asset'::regclass
      and conname = 'dam_asset_missing_after_first_seen'
  ) then
    alter table dam.asset
      add constraint dam_asset_missing_after_first_seen
      check (
        missing_since is null
        or first_seen_at is null
        or missing_since >= first_seen_at
      ) not valid;
  end if;
end
$freshness_constraints$;

comment on column dam.asset.first_seen_at is
  'When this canonical Asset source identity was first observed. Null on rows that '
  'predate issue #2356; use created_at as the historical fallback.';

comment on column dam.asset.last_seen_at is
  'When this canonical Asset source identity was most recently observed. Callers '
  'record source sightings explicitly; metadata-only edits do not imply freshness.';

comment on column dam.asset.missing_since is
  'When the Asset stopped appearing in its authoritative source. Null means current. '
  'Source absence is retained for review and never expressed by deleting the Asset.';
