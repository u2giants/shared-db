-- Push latest dflow."Factory" → core.factory (one direction only).
-- 1) INSERT any dflow row not yet linked via factory_source_ref
-- 2) UPDATE already-linked core.factory rows from current dflow columns
-- Idempotent. Does NOT write back to dflow.
--
-- Link key: core.factory_source_ref
--   source_system = 'designflow_plm'
--   source_table  = 'Factory'
--   source_id     = dflow."Factory".id::text

begin;

set local lock_timeout = '5s';
set local statement_timeout = '10min';

create temporary table tmp_dflow_factory (
  id integer primary key,
  factory_name text,
  factory_nickname text,
  factory_status text,
  factory_access text,
  factory_country text,
  sort_order integer,
  raw_sanitized jsonb
) on commit drop;

create temporary table tmp_inserted (
  dflow_id integer primary key,
  factory_id uuid not null
) on commit drop;

create temporary table tmp_updated (
  factory_id uuid primary key
) on commit drop;

insert into tmp_dflow_factory
select
  d.id,
  d.factory_name,
  d.factory_nickname,
  d.factory_status,
  d.factory_access,
  d.factory_country,
  d.sort_order,
  to_jsonb(d)
from dflow."Factory" d;

-- 1) Insert missing
with missing as (
  select t.*
  from tmp_dflow_factory t
  where not exists (
    select 1
    from core.factory_source_ref csr
    where csr.source_system = 'designflow_plm'
      and csr.source_table = 'Factory'
      and csr.source_id = t.id::text
  )
),
ins as (
  insert into core.factory (
    name, display_name, code, status, country, metadata
  )
  select
    coalesce(
      nullif(trim(m.factory_name), ''),
      nullif(trim(m.factory_nickname), ''),
      'factory-' || m.id::text
    ),
    nullif(trim(m.factory_nickname), ''),
    'DFLOW-' || m.id::text,
    case
      when upper(coalesce(m.factory_status, '')) = 'ACTIVE'
        then 'active'::app.entity_status
      when upper(coalesce(m.factory_status, '')) = 'INACTIVE'
        then 'inactive'::app.entity_status
      when m.factory_status is null or btrim(m.factory_status) = ''
        then 'active'::app.entity_status
      else 'inactive'::app.entity_status
    end,
    nullif(trim(m.factory_country), ''),
    jsonb_build_object(
      'dflow_factory_id', m.id,
      'factory_access', m.factory_access,
      'sort_order', m.sort_order,
      'synced_from', 'dflow.Factory',
      'synced_at', now()
    )
  from missing m
  returning id, (metadata->>'dflow_factory_id')::integer as dflow_id
)
insert into tmp_inserted (dflow_id, factory_id)
select dflow_id, id from ins;

insert into core.factory_source_ref (
  factory_id, source_system, source_table, source_id, source_code, confidence, raw
)
select
  i.factory_id,
  'designflow_plm',
  'Factory',
  i.dflow_id::text,
  'DFLOW-' || i.dflow_id::text,
  'verified',
  t.raw_sanitized
from tmp_inserted i
join tmp_dflow_factory t on t.id = i.dflow_id
on conflict (source_system, source_table, source_id) do update
set factory_id = excluded.factory_id,
    source_code = excluded.source_code,
    confidence = excluded.confidence,
    raw = excluded.raw;

-- 2) Refresh linked core.factory from latest dflow
with linked as (
  select
    csr.factory_id,
    coalesce(
      nullif(trim(t.factory_name), ''),
      nullif(trim(t.factory_nickname), ''),
      'factory-' || t.id::text
    ) as core_name,
    nullif(trim(t.factory_nickname), '') as core_display_name,
    case
      when upper(coalesce(t.factory_status, '')) = 'ACTIVE'
        then 'active'::app.entity_status
      when upper(coalesce(t.factory_status, '')) = 'INACTIVE'
        then 'inactive'::app.entity_status
      when t.factory_status is null or btrim(t.factory_status) = ''
        then 'active'::app.entity_status
      else 'inactive'::app.entity_status
    end as core_status,
    nullif(trim(t.factory_country), '') as core_country,
    t.factory_access,
    t.sort_order,
    t.id as dflow_id,
    t.raw_sanitized
  from tmp_dflow_factory t
  join core.factory_source_ref csr
    on csr.source_system = 'designflow_plm'
   and csr.source_table = 'Factory'
   and csr.source_id = t.id::text
),
upd as (
  update core.factory c
  set
    name = linked.core_name,
    display_name = linked.core_display_name,
    status = linked.core_status,
    country = linked.core_country,
    metadata = coalesce(c.metadata, '{}'::jsonb) || jsonb_build_object(
      'dflow_factory_id', linked.dflow_id,
      'factory_access', linked.factory_access,
      'sort_order', linked.sort_order,
      'synced_from', 'dflow.Factory',
      'synced_at', now()
    ),
    updated_at = now()
  from linked
  where c.id = linked.factory_id
    and (
      c.name is distinct from linked.core_name
      or c.display_name is distinct from linked.core_display_name
      or c.status is distinct from linked.core_status
      or c.country is distinct from linked.core_country
      or c.metadata->>'factory_access' is distinct from linked.factory_access
      or c.metadata->>'sort_order' is distinct from linked.sort_order::text
    )
  returning c.id
)
insert into tmp_updated (factory_id)
select id from upd;

-- Keep source_ref.raw current for all linked rows
update core.factory_source_ref csr
set
  source_code = coalesce(csr.source_code, 'DFLOW-' || t.id::text),
  confidence = 'verified',
  raw = t.raw_sanitized
from tmp_dflow_factory t
where csr.source_system = 'designflow_plm'
  and csr.source_table = 'Factory'
  and csr.source_id = t.id::text;

select count(*)::int as dflow_rows from tmp_dflow_factory;
select count(*)::int as inserted_into_core from tmp_inserted;
select count(*)::int as updated_in_core from tmp_updated;
select count(*)::int as still_unlinked
from dflow."Factory" d
where not exists (
  select 1
  from core.factory_source_ref csr
  where csr.source_system = 'designflow_plm'
    and csr.source_table = 'Factory'
    and csr.source_id = d.id::text
);

commit;
