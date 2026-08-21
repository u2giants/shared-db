-- Audit: dflow."Factory" vs core."Factory" table replica

select
  (select count(*)::int from dflow."Factory") as dflow_n,
  (select count(*)::int from core."Factory") as core_n,
  (select count(*)::int
     from dflow."Factory" d
    where not exists (select 1 from core."Factory" c where c.id = d.id)
  ) as missing_in_core,
  (select count(*)::int
     from core."Factory" c
    where not exists (select 1 from dflow."Factory" d where d.id = c.id)
  ) as extra_in_core;
