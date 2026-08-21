-- DEVELOP / shared sync — audit dflow."Factory" vs core.factory
-- Link authority: core.factory_source_ref
--   (source_system='designflow_plm', source_table='Factory', source_id=id::text)

select
  (select count(*)::int from dflow."Factory") as dflow_factory,
  (select count(*)::int from core.factory) as core_factory,
  (select count(*)::int
     from core.factory_source_ref
    where source_system = 'designflow_plm'
      and source_table = 'Factory') as plm_factory_refs,
  (select count(*)::int
     from dflow."Factory" d
    where not exists (
      select 1
      from core.factory_source_ref csr
      where csr.source_system = 'designflow_plm'
        and csr.source_table = 'Factory'
        and csr.source_id = d.id::text
    )) as dflow_missing_core_link,
  (select count(*)::int
     from core.factory c
    where c.status = 'active'
      and not exists (
        select 1
        from core.factory_source_ref csr
        where csr.factory_id = c.id
          and csr.source_system = 'designflow_plm'
          and csr.source_table = 'Factory'
      )) as core_active_missing_dflow_link;

-- dflow rows with no designflow_plm factory_source_ref
select d.id, d.factory_name, d.factory_nickname, d.factory_status, d.factory_country
from dflow."Factory" d
where not exists (
  select 1
  from core.factory_source_ref csr
  where csr.source_system = 'designflow_plm'
    and csr.source_table = 'Factory'
    and csr.source_id = d.id::text
)
order by d.id;
