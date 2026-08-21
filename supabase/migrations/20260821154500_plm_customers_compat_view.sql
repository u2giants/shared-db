-- DesignFlow customers compatibility over the shared import contract.
--
-- Data on develop is already linked (dflow.customers ↔ core.customer via
-- company_source_ref + plm.customer_import). This migration does NOT copy rows.
-- It exposes a DesignFlow-shaped plm.customers view so app code can map
-- `customers` → plm without a blind rename onto core.customer (uuid PK).
--
-- Writes INSTEAD OF the view still land in dflow.customers (integer PK kept for
-- RFQ/item FKs) and keep plm.customer_import + company_source_ref in sync.
-- core.customer.status stays app-owned (not force-updated from PLM status).

set lock_timeout = '5s';
set statement_timeout = '2min';

create or replace view plm.customers as
select
  nullif(ci.plm_customer_id, '')::integer as customers_id,
  ci.customer_name as customers_name,
  ci.email::character varying as customers_email,
  null::character varying as customers_level,
  null::character varying as customers_notes,
  null::character varying as customers_passw,
  null::character varying as customers_expire,
  ci.status as customers_status,
  null::character varying as customers_auditlog,
  ci.dilution::character varying as customers_dilution,
  null::character varying as customers_lastname,
  ci.phone as customers_phonenum,
  null::character varying as customers_subscription,
  ci.logistic_load::character varying as customers_logistic_load,
  null::character varying as customers_subleveladmin,
  null::character varying as customers_notificationsms,
  null::character varying as customers_notificationemail,
  ci.airbyte_emitted_at as customers_airbyte_emitted_at,
  ci.airbyte_customers_hashid as customers_airbyte_customers_hashid,
  ci.customer_code as customers_code,
  ci.logo_url as customers_logo,
  ci.company_id as core_company_id
from plm.customer_import ci
join core.customer c
  on c.id = ci.company_id
join core.company_source_ref csr
  on csr.company_id = c.id
 and csr.source_system = 'designflow_plm'
 and csr.source_table = 'customers'
 and csr.source_id = ci.plm_customer_id
where ci.plm_customer_id ~ '^[0-9]+$';

comment on view plm.customers is
  'DesignFlow-shaped customers over plm.customer_import + core.company_source_ref '
  '(designflow_plm). Integer customers_id is the PLM source id; core_company_id is '
  'core.customer.id. Dual-write to dflow via INSTEAD OF triggers until dflow is retired.';

create or replace function plm.customers_instead_of_insert()
returns trigger
language plpgsql
security definer
set search_path = plm, core, dflow, app, public, extensions
as $$
declare
  v_id integer;
  v_company_id uuid;
  v_status text := coalesce(nullif(new.customers_status, ''), 'ACTIVE');
  v_raw jsonb;
begin
  if new.customers_id is null then
    insert into dflow.customers (
      customers_name, customers_email, customers_status, customers_phonenum,
      customers_code, customers_logo, customers_dilution, customers_logistic_load,
      customers_passw, customers_notes, customers_level, customers_lastname
    ) values (
      new.customers_name, new.customers_email, v_status, new.customers_phonenum,
      new.customers_code, new.customers_logo,
      coalesce(new.customers_dilution, '0'), coalesce(new.customers_logistic_load, '0'),
      new.customers_passw, new.customers_notes, new.customers_level, new.customers_lastname
    )
    returning customers_id into v_id;
  else
    insert into dflow.customers (
      customers_id, customers_name, customers_email, customers_status, customers_phonenum,
      customers_code, customers_logo, customers_dilution, customers_logistic_load,
      customers_passw, customers_notes, customers_level, customers_lastname
    ) values (
      new.customers_id, new.customers_name, new.customers_email, v_status, new.customers_phonenum,
      new.customers_code, new.customers_logo,
      coalesce(new.customers_dilution, '0'), coalesce(new.customers_logistic_load, '0'),
      new.customers_passw, new.customers_notes, new.customers_level, new.customers_lastname
    )
    returning customers_id into v_id;
  end if;

  select csr.company_id into v_company_id
  from core.company_source_ref csr
  where csr.source_system = 'designflow_plm'
    and csr.source_table = 'customers'
    and csr.source_id = v_id::text;

  if v_company_id is null then
    insert into core.customer (
      name, company_type, status, phone, metadata, is_potential, display_name
    ) values (
      new.customers_name,
      'customer',
      case when upper(v_status) = 'ACTIVE' then 'active'::app.entity_status
           else 'inactive'::app.entity_status end,
      nullif(new.customers_phonenum, ''),
      jsonb_build_object(
        'plm_customers_id', v_id,
        'plm_customer_code', new.customers_code,
        'plm_import_source', 'designflow_plm'
      ),
      false,
      new.customers_name
    )
    returning id into v_company_id;
  end if;

  v_raw := to_jsonb(new) - 'customers_passw' - 'core_company_id';

  insert into core.company_source_ref (
    company_id, source_system, source_table, source_id,
    source_code, source_name, confidence, raw
  ) values (
    v_company_id, 'designflow_plm', 'customers', v_id::text,
    new.customers_code, new.customers_name, 'verified', v_raw
  )
  on conflict (source_system, source_table, source_id) do update
  set company_id = excluded.company_id,
      source_code = excluded.source_code,
      source_name = excluded.source_name,
      confidence = excluded.confidence,
      raw = excluded.raw;

  insert into plm.customer_import (
    plm_customer_id, company_id, customer_code, customer_name, status,
    email, phone, dilution, logistic_load, logo_url, raw, imported_at
  ) values (
    v_id::text, v_company_id, new.customers_code, new.customers_name, v_status,
    nullif(new.customers_email, '')::extensions.citext,
    nullif(new.customers_phonenum, ''),
    nullif(new.customers_dilution, '')::numeric,
    nullif(new.customers_logistic_load, '')::numeric,
    nullif(new.customers_logo, ''),
    v_raw,
    now()
  )
  on conflict (plm_customer_id) do update
  set company_id = excluded.company_id,
      customer_code = excluded.customer_code,
      customer_name = excluded.customer_name,
      status = excluded.status,
      email = excluded.email,
      phone = excluded.phone,
      dilution = excluded.dilution,
      logistic_load = excluded.logistic_load,
      logo_url = excluded.logo_url,
      raw = excluded.raw,
      updated_at = now();

  new.customers_id := v_id;
  new.core_company_id := v_company_id;
  new.customers_status := v_status;
  return new;
end;
$$;

create or replace function plm.customers_instead_of_update()
returns trigger
language plpgsql
security definer
set search_path = plm, core, dflow, app, public, extensions
as $$
declare
  v_company_id uuid;
begin
  update dflow.customers set
    customers_name = new.customers_name,
    customers_email = new.customers_email,
    customers_status = new.customers_status,
    customers_phonenum = new.customers_phonenum,
    customers_code = new.customers_code,
    customers_logo = new.customers_logo,
    customers_dilution = new.customers_dilution,
    customers_logistic_load = new.customers_logistic_load,
    customers_notes = new.customers_notes,
    customers_level = new.customers_level,
    customers_lastname = new.customers_lastname,
    customers_passw = coalesce(new.customers_passw, dflow.customers.customers_passw)
  where customers_id = old.customers_id;

  update plm.customer_import set
    customer_name = new.customers_name,
    status = new.customers_status,
    email = nullif(new.customers_email, '')::extensions.citext,
    phone = nullif(new.customers_phonenum, ''),
    customer_code = new.customers_code,
    logo_url = nullif(new.customers_logo, ''),
    dilution = nullif(new.customers_dilution, '')::numeric,
    logistic_load = nullif(new.customers_logistic_load, '')::numeric,
    updated_at = now()
  where plm_customer_id = old.customers_id::text;

  select company_id into v_company_id
  from core.company_source_ref
  where source_system = 'designflow_plm'
    and source_table = 'customers'
    and source_id = old.customers_id::text;

  if v_company_id is not null then
    update core.customer set
      name = coalesce(new.customers_name, name),
      display_name = coalesce(new.customers_name, display_name),
      phone = coalesce(nullif(new.customers_phonenum, ''), phone),
      metadata = metadata || jsonb_build_object(
        'plm_customer_code', new.customers_code,
        'plm_import_source', 'designflow_plm'
      ),
      updated_at = now()
    where id = v_company_id;

    update core.company_source_ref set
      source_code = new.customers_code,
      source_name = new.customers_name,
      raw = coalesce(raw, '{}'::jsonb) || (to_jsonb(new) - 'customers_passw' - 'core_company_id')
    where source_system = 'designflow_plm'
      and source_table = 'customers'
      and source_id = old.customers_id::text;
  end if;

  new.core_company_id := coalesce(v_company_id, old.core_company_id);
  return new;
end;
$$;

create or replace function plm.customers_instead_of_delete()
returns trigger
language plpgsql
security definer
set search_path = plm, core, dflow, app, public
as $$
begin
  delete from plm.customer_import where plm_customer_id = old.customers_id::text;
  delete from core.company_source_ref
  where source_system = 'designflow_plm'
    and source_table = 'customers'
    and source_id = old.customers_id::text;
  delete from dflow.customers where customers_id = old.customers_id;
  return old;
end;
$$;

drop trigger if exists customers_instead_of_insert on plm.customers;
create trigger customers_instead_of_insert
  instead of insert on plm.customers
  for each row execute function plm.customers_instead_of_insert();

drop trigger if exists customers_instead_of_update on plm.customers;
create trigger customers_instead_of_update
  instead of update on plm.customers
  for each row execute function plm.customers_instead_of_update();

drop trigger if exists customers_instead_of_delete on plm.customers;
create trigger customers_instead_of_delete
  instead of delete on plm.customers
  for each row execute function plm.customers_instead_of_delete();

revoke all on function plm.customers_instead_of_insert() from public;
revoke all on function plm.customers_instead_of_update() from public;
revoke all on function plm.customers_instead_of_delete() from public;
grant execute on function plm.customers_instead_of_insert() to service_role;
grant execute on function plm.customers_instead_of_update() to service_role;
grant execute on function plm.customers_instead_of_delete() to service_role;

grant select, insert, update, delete on plm.customers to service_role;
grant select on plm.customers to authenticated;
