-- Issue #1609: fresh supported successor for two permanently retired migrations.
-- Never apply or revive 20260814224937 / 20260814233423. This file also converges
-- CI replay, where those historical files exist, to the production-supported shape.

create table if not exists plm.source_resolution (
  source_system       text        not null,
  entity_kind         text        not null,
  source_id           text        not null,
  core_property_id    uuid            null,
  core_character_id   uuid            null,
  core_style_guide_id uuid            null,
  dam_asset_id        uuid            null,
  resolution_status   text        not null default 'unresolved',
  resolution_reason   text            null,
  resolved_at         timestamptz     null,
  resolved_by         text            null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint source_resolution_pkey primary key (source_system, entity_kind, source_id),
  constraint source_resolution_source_system_nonblank_chk check (btrim(source_system) <> ''),
  constraint source_resolution_source_id_nonblank_chk check (btrim(source_id) <> ''),
  constraint source_resolution_entity_kind_chk
    check (entity_kind in ('property','character','style_guide','asset')),
  constraint source_resolution_status_chk
    check (resolution_status in ('unresolved','matched','ambiguous','no_match','rejected','deferred')),
  constraint source_resolution_target_kind_chk check (
    case entity_kind
      when 'property' then core_character_id is null and core_style_guide_id is null and dam_asset_id is null
      when 'character' then core_property_id is null and core_style_guide_id is null and dam_asset_id is null
      when 'style_guide' then core_property_id is null and core_character_id is null and dam_asset_id is null
      when 'asset' then core_property_id is null and core_character_id is null and core_style_guide_id is null
      else false
    end
  ),
  constraint source_resolution_matched_target_chk check (
    (resolution_status = 'matched') =
    (num_nonnulls(core_property_id, core_character_id, core_style_guide_id, dam_asset_id) = 1)
  ),
  constraint source_resolution_audit_pair_chk check ((resolved_at is null) = (resolved_by is null)),
  constraint source_resolution_reason_nonblank_chk check (resolution_reason is null or btrim(resolution_reason) <> ''),
  constraint source_resolution_actor_nonblank_chk check (resolved_by is null or btrim(resolved_by) <> '')
);

-- The owner ruling requires plain UUID decisions. Every FK action either blocks target
-- lifecycle or destroys/invalidates the durable human decision. Historical CI replay may
-- have created these four constraints; production will not have them.
alter table plm.source_resolution
  drop constraint if exists source_resolution_core_property_id_fkey,
  drop constraint if exists source_resolution_core_character_id_fkey,
  drop constraint if exists source_resolution_core_style_guide_id_fkey,
  drop constraint if exists source_resolution_dam_asset_id_fkey;

comment on table plm.source_resolution is
  'Capture-independent durable human source-to-canonical decisions. Loaders never write this table; use plm.set_source_resolution(). Target UUIDs deliberately have no foreign keys.';
comment on column plm.source_resolution.updated_at is
  'Optimistic conflict token. Replacing a different decision requires this exact prior value.';

alter table plm.source_resolution enable row level security;
revoke all on table plm.source_resolution from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger, maintain
  on table plm.source_resolution from service_role;
grant select on table plm.source_resolution to authenticated, service_role;
drop policy if exists source_resolution_authenticated_read on plm.source_resolution;
create policy source_resolution_authenticated_read
  on plm.source_resolution for select to authenticated using (true);

create or replace function plm.source_resolution_target_missing(
  p_entity_kind text,
  p_core_property_id uuid,
  p_core_character_id uuid,
  p_core_style_guide_id uuid,
  p_dam_asset_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to pg_catalog
as $$
declare
  v_found boolean := false;
begin
  case p_entity_kind
    when 'property' then
      if to_regclass('core.property') is null then return true; end if;
      execute 'select true from core.property where id = $1' into v_found using p_core_property_id;
    when 'character' then
      if to_regclass('core.character') is null then return true; end if;
      execute 'select true from core.character where id = $1' into v_found using p_core_character_id;
    when 'style_guide' then
      if to_regclass('core.style_guide') is null then return true; end if;
      execute 'select true from core.style_guide where id = $1' into v_found using p_core_style_guide_id;
    when 'asset' then
      if to_regclass('dam.asset') is null then return true; end if;
      execute 'select true from dam.asset where id = $1' into v_found using p_dam_asset_id;
    else
      return true;
  end case;
  return not coalesce(v_found, false);
end;
$$;
revoke all on function plm.source_resolution_target_missing(text,uuid,uuid,uuid,uuid)
  from public, anon, authenticated;
grant execute on function plm.source_resolution_target_missing(text,uuid,uuid,uuid,uuid)
  to authenticated, service_role;

create or replace view api.source_resolution
with (security_invoker = true)
as
select r.source_system, r.entity_kind, r.source_id,
       r.core_property_id, r.core_character_id, r.core_style_guide_id, r.dam_asset_id,
       r.resolution_status, r.resolution_reason, r.resolved_at, r.resolved_by, r.updated_at,
       case when r.resolution_status = 'matched'
         then plm.source_resolution_target_missing(
           r.entity_kind, r.core_property_id, r.core_character_id,
           r.core_style_guide_id, r.dam_asset_id)
         else false
       end as target_missing
from plm.source_resolution r;
comment on view api.source_resolution is
  'Authenticated durable decision read path. target_missing keeps dangling decisions visible; consumers must LEFT JOIN and must not treat a missing target as an absent decision.';
revoke all on table api.source_resolution from public, anon;
grant select on table api.source_resolution to authenticated, service_role;

create or replace function plm.set_source_resolution(
  p_source_system text,
  p_entity_kind text,
  p_source_id text,
  p_resolution_status text,
  p_core_property_id uuid default null,
  p_core_character_id uuid default null,
  p_core_style_guide_id uuid default null,
  p_dam_asset_id uuid default null,
  p_resolution_reason text default null,
  p_expected_updated_at timestamptz default null
)
returns plm.source_resolution
language plpgsql
security definer
set search_path to pg_catalog
as $$
declare
  v_existing plm.source_resolution%rowtype;
  v_result plm.source_resolution%rowtype;
  v_target_found boolean := false;
  v_actor text := coalesce(
    auth.uid()::text,
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    session_user::text
  );
begin
  p_source_system := btrim(p_source_system);
  p_entity_kind := btrim(p_entity_kind);
  p_source_id := btrim(p_source_id);
  p_resolution_status := btrim(p_resolution_status);
  p_resolution_reason := nullif(btrim(p_resolution_reason), '');

  if coalesce(v_actor, '') = '' then
    raise exception using errcode = '42501', message = 'source resolution requires an authenticated actor';
  end if;

  -- Validate and lock the chosen target exactly as an FK would, but branch-by-branch.
  -- A future target-table retirement can disable only its own kind, never all decisions.
  if p_resolution_status = 'matched' then
    case p_entity_kind
      when 'property' then
        if to_regclass('core.property') is not null then
          execute 'select true from core.property where id = $1 for key share'
            into v_target_found using p_core_property_id;
        end if;
      when 'character' then
        if to_regclass('core.character') is not null then
          execute 'select true from core.character where id = $1 for key share'
            into v_target_found using p_core_character_id;
        end if;
      when 'style_guide' then
        if to_regclass('core.style_guide') is not null then
          execute 'select true from core.style_guide where id = $1 for key share'
            into v_target_found using p_core_style_guide_id;
        end if;
      when 'asset' then
        if to_regclass('dam.asset') is not null then
          execute 'select true from dam.asset where id = $1 for key share'
            into v_target_found using p_dam_asset_id;
        end if;
      else
        v_target_found := false;
    end case;
    if not coalesce(v_target_found, false) then
      raise exception using errcode = '23503',
        message = format('source resolution target is missing for kind %s', p_entity_kind),
        detail = format('target UUID: %s', coalesce(
          p_core_property_id, p_core_character_id, p_core_style_guide_id, p_dam_asset_id)::text);
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws(E'\x1f', p_source_system, p_entity_kind, p_source_id), 0));
  select * into v_existing from plm.source_resolution
   where source_system = p_source_system and entity_kind = p_entity_kind and source_id = p_source_id
   for update;

  if found then
    if v_existing.resolution_status is not distinct from p_resolution_status
       and v_existing.core_property_id is not distinct from p_core_property_id
       and v_existing.core_character_id is not distinct from p_core_character_id
       and v_existing.core_style_guide_id is not distinct from p_core_style_guide_id
       and v_existing.dam_asset_id is not distinct from p_dam_asset_id
       and v_existing.resolution_reason is not distinct from p_resolution_reason then
      return v_existing;
    end if;
    if p_expected_updated_at is null or p_expected_updated_at is distinct from v_existing.updated_at then
      raise exception using errcode = '40001',
        message = format('source resolution changed for %s/%s/%s; reload before replacing it',
          p_source_system, p_entity_kind, p_source_id);
    end if;
    update plm.source_resolution
       set resolution_status=p_resolution_status, core_property_id=p_core_property_id,
           core_character_id=p_core_character_id, core_style_guide_id=p_core_style_guide_id,
           dam_asset_id=p_dam_asset_id, resolution_reason=p_resolution_reason,
           resolved_at=clock_timestamp(), resolved_by=v_actor, updated_at=clock_timestamp()
     where source_system=p_source_system and entity_kind=p_entity_kind and source_id=p_source_id
     returning * into v_result;
  else
    if p_expected_updated_at is not null then
      raise exception using errcode = '40001',
        message = format('source resolution does not exist for %s/%s/%s; reload before writing',
          p_source_system, p_entity_kind, p_source_id);
    end if;
    insert into plm.source_resolution (
      source_system,entity_kind,source_id,resolution_status,
      core_property_id,core_character_id,core_style_guide_id,dam_asset_id,
      resolution_reason,resolved_at,resolved_by)
    values (p_source_system,p_entity_kind,p_source_id,p_resolution_status,
      p_core_property_id,p_core_character_id,p_core_style_guide_id,p_dam_asset_id,
      p_resolution_reason,clock_timestamp(),v_actor)
    returning * into v_result;
  end if;
  return v_result;
end;
$$;
comment on function plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz) is
  'Only write path for durable source resolution. Validates and locks matched targets, stamps the actor, serializes first writers, preserves identical repeats, and requires the current token for replacement.';
revoke all on function plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)
  from public, anon;
grant execute on function plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)
  to authenticated, service_role;

create or replace function plm.reject_legacy_landing_resolution_write()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb;
  v_column text;
begin
  if tg_op = 'INSERT' then
    if coalesce(v_new ->> 'resolution_status', 'unresolved') <> 'unresolved' then
      raise exception using errcode='23514', message=format(
        '%I.%I.resolution_status is legacy; use plm.set_source_resolution()',tg_table_schema,tg_table_name);
    end if;
    foreach v_column in array array['core_property_id','core_character_id','core_style_guide_id',
      'dam_asset_id','resolution_reason','resolution_note','resolved_at','resolved_by'] loop
      if v_new ? v_column and v_new -> v_column <> 'null'::jsonb then
        raise exception using errcode='23514', message=format(
          '%I.%I.%I is legacy; use plm.set_source_resolution()',tg_table_schema,tg_table_name,v_column);
      end if;
    end loop;
    return new;
  end if;
  v_old := to_jsonb(old);
  foreach v_column in array array['core_property_id','core_character_id','core_style_guide_id',
    'dam_asset_id','resolution_status','resolution_reason','resolution_note','resolved_at','resolved_by'] loop
    if v_new ? v_column and (v_new -> v_column) is distinct from (v_old -> v_column) then
      raise exception using errcode='23514', message=format(
        '%I.%I.%I is legacy and immutable; use plm.set_source_resolution()',
        tg_table_schema,tg_table_name,v_column);
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function plm.reject_legacy_landing_resolution_write() from public, anon, authenticated;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('plm','pmt_property','pmt_property_resolution_immutable'),
    ('plm','pmt_character','pmt_character_resolution_immutable'),
    ('plm','nbcu_property','nbcu_property_resolution_immutable'),
    ('plm','nbcu_character','nbcu_character_resolution_immutable'),
    ('plm','nbcu_style_guide','nbcu_style_guide_resolution_immutable'),
    ('plm','nbcu_asset','nbcu_asset_resolution_immutable'),
    ('plm','opa_property_character','opa_property_character_resolution_immutable'),
    ('plm','opa_property','opa_property_resolution_immutable'),
    ('plm','opa_character','opa_character_resolution_immutable'),
    ('plm','dcp_portal_tile','dcp_portal_tile_resolution_immutable'),
    ('plm','dcp_style_guide','dcp_style_guide_resolution_immutable'),
    ('plm','dcp_property','dcp_property_resolution_immutable'),
    ('plm','dcp_character','dcp_character_resolution_immutable'),
    ('plm','lucasfilm_dcp_portal_tile','lucasfilm_dcp_portal_tile_resolution_immutable'),
    ('plm','lucasfilm_dcp_style_guide','lucasfilm_dcp_style_guide_resolution_immutable'),
    ('plm','lucasfilm_dcp_property','lucasfilm_dcp_property_resolution_immutable'),
    ('plm','lucasfilm_dcp_character','lucasfilm_dcp_character_resolution_immutable'),
    ('plm','marvel_dcp_portal_tile','marvel_dcp_portal_tile_resolution_immutable'),
    ('plm','marvel_dcp_style_guide','marvel_dcp_style_guide_resolution_immutable'),
    ('plm','marvel_dcp_property','marvel_dcp_property_resolution_immutable'),
    ('plm','marvel_dcp_character','marvel_dcp_character_resolution_immutable'),
    ('plm','twentieth_century_dcp_portal_tile','twentieth_century_dcp_portal_tile_resolution_immutable'),
    ('plm','twentieth_century_dcp_style_guide','twentieth_century_dcp_style_guide_resolution_immutable'),
    ('plm','twentieth_century_dcp_property','twentieth_century_dcp_property_resolution_immutable'),
    ('plm','twentieth_century_dcp_character','twentieth_century_dcp_character_resolution_immutable'),
    ('plm','wb_property_character_normalized','wb_property_character_normalized_resolution_immutable')
  ) v(table_schema,table_name,trigger_name)
  loop
    execute format('drop trigger if exists %I on %I.%I',r.trigger_name,r.table_schema,r.table_name);
    execute format('create trigger %I before insert or update on %I.%I for each row execute function plm.reject_legacy_landing_resolution_write()',r.trigger_name,r.table_schema,r.table_name);
  end loop;
end;
$$;

-- Hash-bound post-apply truth. No row values are read or emitted.
do $$
declare
  v_count integer;
begin
  if to_regclass('plm.source_resolution') is null then raise exception 'plm.source_resolution missing'; end if;
  select count(*) into v_count from pg_constraint
   where conrelid='plm.source_resolution'::regclass and contype='f';
  if v_count <> 0 then raise exception 'source_resolution must have zero foreign keys, found %',v_count; end if;
  select count(*) into v_count from pg_trigger
   where tgfoid='plm.reject_legacy_landing_resolution_write()'::regprocedure and not tgisinternal;
  if v_count <> 26 then raise exception 'landing resolution guard trigger count %, expected 26',v_count; end if;
  if position('target_missing' in pg_get_viewdef('api.source_resolution'::regclass,true))=0 then
    raise exception 'api.source_resolution lacks dangling visibility';
  end if;
  if position('for key share' in lower(pg_get_functiondef(
      'plm.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure)))=0 then
    raise exception 'set_source_resolution lacks target lock';
  end if;
end;
$$;
