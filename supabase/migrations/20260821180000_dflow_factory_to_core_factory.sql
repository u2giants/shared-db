-- Land dflow."Factory" → core.factory link contract + PLM-shaped compat view.
-- Idempotent: inserts only missing designflow_plm / Factory source_refs.
-- Reverse sync (core → dflow) stays in scripts/dflow-core-sync/factory/02_*.sql
-- and is not applied by this migration.

do $migrate$
begin
  if to_regclass('dflow."Factory"') is null then
    raise notice '20260821180000: skip factory sync — dflow."Factory" not present';
  else
    execute $sql$
      with missing as (
        select
          d.id,
          d.factory_name,
          d.factory_nickname,
          d.factory_status,
          d.factory_access,
          d.factory_country,
          d.sort_order,
          to_jsonb(d) as raw_sanitized
        from dflow."Factory" d
        where not exists (
          select 1
          from core.factory_source_ref csr
          where csr.source_system = 'designflow_plm'
            and csr.source_table = 'Factory'
            and csr.source_id = d.id::text
        )
      ),
      ins_core as (
        insert into core.factory (name, display_name, code, status, country, metadata)
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
      ),
      linked as (
        select m.*, i.id as factory_id
        from missing m
        join ins_core i on i.dflow_id = m.id
      )
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
        l.factory_id,
        'designflow_plm',
        'Factory',
        l.id::text,
        'DFLOW-' || l.id::text,
        'verified',
        l.raw_sanitized
      from linked l
      on conflict (source_system, source_table, source_id) do update
      set factory_id = excluded.factory_id,
          source_code = excluded.source_code,
          confidence = excluded.confidence,
          raw = excluded.raw
    $sql$;
  end if;
end
$migrate$;

-- Compat view: integer PK shape expected by PLM Sequelize model `Factory`
create or replace view core."Factory" as
select
  nullif(csr.source_id, '')::integer as id,
  c.name as factory_name,
  coalesce(c.display_name, c.name) as factory_nickname,
  case when c.status::text = 'active' then 'Active' else 'Inactive' end as factory_status,
  c.metadata->>'factory_access' as factory_access,
  c.country as factory_country,
  nullif(c.metadata->>'sort_order', '')::integer as sort_order
from core.factory_source_ref csr
join core.factory c on c.id = csr.factory_id
where csr.source_system = 'designflow_plm'
  and csr.source_table = 'Factory'
  and csr.source_id ~ '^[0-9]+$';

grant select on core."Factory" to service_role;
grant select on core."Factory" to authenticated;

comment on view core."Factory" is
  'PLM-shaped projection of core.factory rows linked via factory_source_ref '
  '(designflow_plm / Factory / <integer id>). Used by designflow-backend '
  'Sequelize model Factory when multi-schema maps Factory → core.';
