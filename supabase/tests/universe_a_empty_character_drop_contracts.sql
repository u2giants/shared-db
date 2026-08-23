-- Focused contracts for 20260823133150_drop_empty_universe_a_character_tables.sql.

do $contracts$
declare
  v_function regprocedure;
  v_definition text;
  v_constraint_count integer;
begin
  if to_regclass('core.character') is not null then
    raise exception 'core.character still exists';
  end if;
  if to_regclass('core.property_character') is not null then
    raise exception 'core.property_character still exists';
  end if;

  select count(*) into v_constraint_count
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where c.contype = 'f'
    and (n.nspname, t.relname, c.conname) in (
      ('core', 'style_guide_character', 'style_guide_character_character_id_fkey'),
      ('dam', 'asset_character', 'asset_character_character_id_fkey'),
      ('plm', 'nbcu_character', 'nbcu_character_core_character_id_fkey'),
      ('plm', 'opa_character', 'opa_character_core_character_id_fkey'),
      ('plm', 'pmt_character', 'pmt_character_core_character_id_fkey'),
      ('plm', 'source_resolution', 'source_resolution_core_character_id_fkey')
    );
  if v_constraint_count <> 0 then
    raise exception '% obsolete core.character foreign key(s) remain', v_constraint_count;
  end if;

  foreach v_function in array array[
    'api.db_data_admin_licensor_property_list(text,boolean,text,integer)'::regprocedure,
    'api.db_data_admin_licensor_property_tree(text,boolean,text,integer)'::regprocedure
  ] loop
    select pg_get_functiondef(v_function) into v_definition;
    if position('core.character' in v_definition) <> 0 then
      raise exception '% still depends on core.character', v_function;
    end if;
    if (length(v_definition) - length(replace(v_definition, '''character_count'', 0', '')))
       / length('''character_count'', 0') <> 2 then
      raise exception '% does not preserve both character_count fields as zero', v_function;
    end if;
  end loop;
end
$contracts$;

-- Reversibility rehearsal.  The transaction reconstructs the retired tables
-- and every removed FK with its original delete action, proves the dependencies,
-- then rolls back so the post-migration catalog stays retired.
begin;

create table core.character (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references core.property(id) on delete cascade,
  name text not null,
  code text,
  status app.entity_status not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (property_id, code)
);

create table core.property_character (
  property_id uuid not null,
  character_id uuid not null,
  is_primary boolean not null default false,
  source text not null default 'opa',
  created_at timestamptz not null default now(),
  primary key (property_id, character_id),
  constraint property_character_property_id_fkey
    foreign key (property_id) references core.property(id) on delete restrict,
  constraint property_character_character_id_fkey
    foreign key (character_id) references core.character(id) on delete cascade,
  constraint property_character_source_chk check (btrim(source) <> '')
);

alter table core.style_guide_character add constraint style_guide_character_character_id_fkey
  foreign key (character_id) references core.character(id) on delete cascade;
alter table dam.asset_character add constraint asset_character_character_id_fkey
  foreign key (character_id) references core.character(id) on delete cascade;
alter table plm.nbcu_character add constraint nbcu_character_core_character_id_fkey
  foreign key (core_character_id) references core.character(id) on delete restrict;
alter table plm.opa_character add constraint opa_character_core_character_id_fkey
  foreign key (core_character_id) references core.character(id) on delete restrict;
alter table plm.pmt_character add constraint pmt_character_core_character_id_fkey
  foreign key (core_character_id) references core.character(id) on delete restrict;
do $optional_source_resolution$
begin
  if to_regclass('plm.source_resolution') is not null then
    alter table plm.source_resolution add constraint source_resolution_core_character_id_fkey
      foreign key (core_character_id) references core.character(id) on delete restrict;
  end if;
end
$optional_source_resolution$;

do $reversal$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_constraint c
  where c.contype = 'f'
    and c.confrelid = 'core.character'::regclass;
  if v_count <> (case when to_regclass('plm.source_resolution') is null then 6 else 7 end) then
    raise exception 'reversal rehearsal found an unexpected core.character foreign-key count: %', v_count;
  end if;
end
$reversal$;

rollback;

do $clean$
begin
  if to_regclass('core.character') is not null
     or to_regclass('core.property_character') is not null then
    raise exception 'reversal rehearsal did not roll back cleanly';
  end if;
end
$clean$;
