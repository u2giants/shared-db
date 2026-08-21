-- One-way: copy latest dflow."Factory" → core."Factory" (real table replica).
-- Upsert by id. Does not touch core.factory / factory_source_ref.
-- Run on develop (SQL editor) when you want core."Factory" to match dflow.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Ensure table exists (no-op if migration already applied)
create table if not exists core."Factory" (
  id integer not null,
  factory_name character varying,
  factory_nickname character varying,
  factory_status character varying,
  factory_access character varying,
  sort_order integer,
  factory_country character varying(255),
  constraint "Factory_pkey" primary key (id)
);

insert into core."Factory" (
  id,
  factory_name,
  factory_nickname,
  factory_status,
  factory_access,
  sort_order,
  factory_country
)
select
  d.id,
  d.factory_name,
  d.factory_nickname,
  d.factory_status,
  d.factory_access,
  d.sort_order,
  d.factory_country
from dflow."Factory" d
on conflict (id) do update
set
  factory_name = excluded.factory_name,
  factory_nickname = excluded.factory_nickname,
  factory_status = excluded.factory_status,
  factory_access = excluded.factory_access,
  sort_order = excluded.sort_order,
  factory_country = excluded.factory_country;

-- Drop rows in core that no longer exist in dflow (full replica)
delete from core."Factory" c
where not exists (
  select 1 from dflow."Factory" d where d.id = c.id
);

-- Keep identity sequence ahead of max id
select setval(
  pg_get_serial_sequence('core."Factory"', 'id'),
  greatest((select coalesce(max(id), 1) from core."Factory"), 1),
  true
);

select
  (select count(*)::int from dflow."Factory") as dflow_n,
  (select count(*)::int from core."Factory") as core_n,
  (select count(*)::int
     from dflow."Factory" d
     full outer join core."Factory" c on c.id = d.id
    where d.id is null or c.id is null
       or d.factory_name is distinct from c.factory_name
       or d.factory_nickname is distinct from c.factory_nickname
       or d.factory_status is distinct from c.factory_status
       or d.factory_access is distinct from c.factory_access
       or d.sort_order is distinct from c.sort_order
       or d.factory_country is distinct from c.factory_country
  ) as mismatches;

commit;
