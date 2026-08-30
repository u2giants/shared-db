-- Issue #1881: durable Warner entity lifecycle. No source rows are included.

alter table plm.wb_asset_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column first_withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_asset_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_asset_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_character_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column first_withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_character_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_character_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_property
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column first_withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_property_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_property_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_style_guide_normalized
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column first_withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_style_guide_normalized_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint wb_style_guide_normalized_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.wb_franchise
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add column first_withdrawn_at timestamptz,
  add column change_signal text generated always as (source_hash) stored,
  add constraint wb_franchise_lifecycle_status_chk check (status in ('active', 'withdrawn')),
  add constraint wb_franchise_withdrawn_at_chk check ((status = 'withdrawn') = (withdrawn_at is not null));

create function plm.enforce_wb_entity_lifecycle()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if old.first_withdrawn_at is not null
     and new.first_withdrawn_at is distinct from old.first_withdrawn_at then
    raise exception 'Warner first withdrawal history is immutable.' using errcode = 'P0001';
  end if;
  if new.status = 'withdrawn' and new.first_withdrawn_at is null then
    new.first_withdrawn_at := new.withdrawn_at;
  end if;
  if new.first_withdrawn_at is not null and new.withdrawn_at is not null
     and new.first_withdrawn_at > new.withdrawn_at then
    raise exception 'Warner first withdrawal cannot follow current withdrawal.' using errcode = '23514';
  end if;
  return new;
end $$;

do $triggers$
declare v_table text;
begin
  foreach v_table in array array['wb_asset_normalized','wb_character_normalized','wb_property','wb_style_guide_normalized','wb_franchise'] loop
    execute format('create trigger %I before insert or update of status, withdrawn_at, first_withdrawn_at on plm.%I for each row execute function plm.enforce_wb_entity_lifecycle()', 'trg_' || v_table || '_lifecycle', v_table);
    execute format('create index %I on plm.%I(status, last_seen_at)', 'idx_' || v_table || '_lifecycle_status', v_table);
  end loop;
end
$triggers$;

comment on column plm.wb_asset_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_character_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_property.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_style_guide_normalized.change_signal is
  'Opaque deterministic equality signal generated from the retained source hash.';
comment on column plm.wb_franchise.change_signal is
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
    'wb_style_guide_normalized',
    'wb_franchise'
  ] loop
    select count(*) into v_columns
    from pg_catalog.pg_attribute
    where attrelid = format('plm.%I', v_table)::regclass
      and attname in ('status', 'withdrawn_at', 'first_withdrawn_at', 'change_signal')
      and not attisdropped;

    if v_columns <> 4 then
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
