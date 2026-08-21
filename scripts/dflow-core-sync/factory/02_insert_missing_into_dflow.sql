-- Optional reverse sync: active core.factory rows with no designflow_plm
-- Factory source_ref → insert into dflow."Factory" and link.
-- Default scope: status = 'active' only.
-- Idempotent on source_ref; skips name collisions with existing dflow nicknames/names.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '10min';

create temporary table tmp_core_missing (
  factory_id uuid primary key,
  name text not null,
  display_name text,
  status text not null,
  country text
) on commit drop;

create temporary table tmp_dflow_synced (
  factory_id uuid primary key,
  dflow_id integer not null
) on commit drop;

insert into tmp_core_missing (factory_id, name, display_name, status, country)
select
  c.id,
  c.name,
  c.display_name,
  c.status::text,
  c.country
from core.factory c
where c.status = 'active'
  and not exists (
    select 1
    from core.factory_source_ref csr
    where csr.factory_id = c.id
      and csr.source_system = 'designflow_plm'
      and csr.source_table = 'Factory'
  )
  and not exists (
    select 1
    from dflow."Factory" d
    where lower(trim(coalesce(nullif(d.factory_nickname, ''), d.factory_name)))
        = lower(trim(coalesce(nullif(c.display_name, ''), c.name)))
  );

do $$
declare
  r record;
  new_id integer;
begin
  for r in
    select * from tmp_core_missing order by name
  loop
    insert into dflow."Factory" (
      factory_name,
      factory_nickname,
      factory_status,
      factory_country
    ) values (
      r.name,
      coalesce(nullif(trim(r.display_name), ''), r.name),
      'ACTIVE',
      r.country
    )
    returning id into new_id;

    insert into tmp_dflow_synced (factory_id, dflow_id)
    values (r.factory_id, new_id);
  end loop;
end $$;

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
  null,
  'verified',
  jsonb_build_object(
    'synced_from', 'core.factory',
    'synced_at', now(),
    'factory_id', t.factory_id
  )
from tmp_dflow_synced t
on conflict (source_system, source_table, source_id) do update
set factory_id = excluded.factory_id,
    confidence = excluded.confidence,
    raw = excluded.raw;

select setval(
  pg_get_serial_sequence('dflow."Factory"', 'id'),
  greatest((select coalesce(max(id), 1) from dflow."Factory"), 1),
  true
);

select count(*)::int as missing_active_before from tmp_core_missing;
select count(*)::int as synced_into_dflow from tmp_dflow_synced;

commit;
