-- Insert dflow."Factory" rows missing from core into core.factory
-- and link via core.factory_source_ref (designflow_plm / Factory / <id>).
-- Idempotent: skips ids that already have a source_ref.
-- Safe to re-run on develop; promote via shared-db migration workflow later.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '10min';

create temporary table tmp_factory_missing (
  id integer primary key,
  factory_name text,
  factory_nickname text,
  factory_status text,
  factory_access text,
  factory_country text,
  sort_order integer,
  raw_sanitized jsonb
) on commit drop;

create temporary table tmp_factory_synced (
  dflow_id integer primary key,
  factory_id uuid not null
) on commit drop;

insert into tmp_factory_missing
select
  d.id,
  d.factory_name,
  d.factory_nickname,
  d.factory_status,
  d.factory_access,
  d.factory_country,
  d.sort_order,
  to_jsonb(d)
from dflow."Factory" d
where not exists (
  select 1
  from core.factory_source_ref csr
  where csr.source_system = 'designflow_plm'
    and csr.source_table = 'Factory'
    and csr.source_id = d.id::text
);

with ins as (
  insert into core.factory (
    name,
    display_name,
    code,
    status,
    country,
    metadata
  )
  select
    coalesce(nullif(trim(m.factory_name), ''), nullif(trim(m.factory_nickname), ''), 'factory-' || m.id::text),
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
  from tmp_factory_missing m
  returning id, (metadata->>'dflow_factory_id')::integer as dflow_id
)
insert into tmp_factory_synced (dflow_id, factory_id)
select dflow_id, id from ins;

insert into core.factory_source_ref (
  factory_id,
  source_system,
  source_table,
  source_id,
  source_code,
  confidence,
  raw
)
select
  t.factory_id,
  'designflow_plm',
  'Factory',
  t.dflow_id::text,
  'DFLOW-' || t.dflow_id::text,
  'verified',
  m.raw_sanitized
from tmp_factory_synced t
join tmp_factory_missing m on m.id = t.dflow_id
on conflict (source_system, source_table, source_id) do update
set factory_id = excluded.factory_id,
    source_code = excluded.source_code,
    confidence = excluded.confidence,
    raw = excluded.raw;

select count(*)::int as missing_before from tmp_factory_missing;
select count(*)::int as synced_into_core from tmp_factory_synced;

select count(*)::int as dflow_still_unlinked
from dflow."Factory" d
where not exists (
  select 1
  from core.factory_source_ref csr
  where csr.source_system = 'designflow_plm'
    and csr.source_table = 'Factory'
    and csr.source_id = d.id::text
);

commit;
