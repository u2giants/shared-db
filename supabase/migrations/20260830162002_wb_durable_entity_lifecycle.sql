-- Issue #1881: durable Warner entity lifecycle. No source rows are included.

alter table plm.wb_asset_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_asset_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_asset_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_character_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_character_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_character_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_property
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_property_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_property_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_style_guide_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_style_guide_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_style_guide_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

comment on column plm.wb_asset_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_character_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_property.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_style_guide_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';

do $verify$
declare
  v_table text;
  v_columns integer;
  v_checks integer;
begin
  foreach v_table in array array[
    'wb_asset_normalized',
    'wb_character_normalized',
    'wb_property',
    'wb_style_guide_normalized'
  ] loop
    select count(*) into v_columns
    from pg_catalog.pg_attribute
    where attrelid = format('plm.%I', v_table)::regclass
      and attname in ('status', 'withdrawn_at', 'change_signal')
      and not attisdropped;

    if v_columns <> 3 then
      raise exception 'verify: %.% lifecycle columns are incomplete', 'plm', v_table;
    end if;

    select count(*) into v_checks
    from pg_catalog.pg_constraint
    where conrelid = format('plm.%I', v_table)::regclass
      and contype = 'c'
      and convalidated
      and conname in (
        v_table || '_lifecycle_status_chk',
        v_table || '_withdrawn_at_chk'
      );

    if v_checks <> 2 then
      raise exception 'verify: %.% lifecycle constraints are incomplete', 'plm', v_table;
    end if;

    if not exists (
      select 1 from pg_catalog.pg_attribute
      where attrelid = format('plm.%I', v_table)::regclass
        and attname = 'change_signal'
        and attgenerated = 's'
    ) then
      raise exception 'verify: %.% change_signal is not generated', 'plm', v_table;
    end if;
  end loop;
end
$verify$;
