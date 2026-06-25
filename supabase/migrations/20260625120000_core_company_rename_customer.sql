-- Rename core.company -> core.customer, and add the "potential customer" flag.
--
-- Why rename
-- ----------
-- "company" is too broad and invites the wrong rows. A factory is a company; a
-- licensor is a company; neither belongs in a list of customers. Those already
-- have their own canonical homes (core.factory, core.licensor). The shared hub
-- table actually holds *customers* (prospects + confirmed customers), so it
-- should be named core.customer to stop other concepts from leaking into it.
--
-- Why a compat view
-- -----------------
-- Every app reaches this table through api.* views + RPCs (all security_invoker),
-- not by hitting core.company directly. Renaming the table and leaving a
-- security_invoker view named core.company means all existing api views, RPCs,
-- RLS, FKs, and app code keep working unchanged while each app migrates to
-- core.customer on its own schedule. FKs and table privileges follow the table
-- automatically across a rename. The compat view is DEPRECATED and gets dropped
-- in a later, owner-approved contract migration once all four apps reference
-- core.customer directly.
--
-- Potential vs active customer
-- ----------------------------
-- Active/confirmed customers are companies we have actually done business with.
-- Their authoritative source is PLM/ERP (ColdLion): a row is a confirmed customer
-- iff it has a designflow_plm / coldlion source ref. Everything else in the table
-- (CRM/PM created, promoted from an ingested domain) is a *potential* customer.
-- is_potential makes that explicit and is kept authoritative by a trigger that
-- flips it to false the moment an ERP source ref is attached.

-- 1. Rename the table. FKs from plm/dam/pim/crm and all table grants follow it.
alter table core.company rename to customer;

-- 2. Potential-customer flag. Default true: anything not ERP-verified is potential.
alter table core.customer
  add column if not exists is_potential boolean not null default true;

comment on column core.customer.is_potential is
  'true = potential customer (not in PLM/ERP). false = active/confirmed customer (has a designflow_plm/coldlion source ref). Maintained by core.sync_customer_potential().';

create index if not exists core_customer_is_potential_idx on core.customer (is_potential);

-- 3. Backfill: anything already linked to ERP is an active customer, not potential.
update core.customer c
set is_potential = false
where exists (
  select 1 from core.company_source_ref sr
  where sr.company_id = c.id
    and sr.source_system in ('designflow_plm', 'coldlion')
);

-- 4. Keep is_potential authoritative: attaching an ERP source ref => active customer.
create or replace function core.sync_customer_potential()
returns trigger
language plpgsql
security definer
set search_path = core, public
as $$
begin
  if new.source_system in ('designflow_plm', 'coldlion') then
    update core.customer
    set is_potential = false
    where id = new.company_id and is_potential is distinct from false;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_customer_potential on core.company_source_ref;
create trigger sync_customer_potential
  after insert or update on core.company_source_ref
  for each row execute function core.sync_customer_potential();

-- 5. Backward-compatible shim so existing core.company references keep working.
--    security_invoker = true so the underlying core.customer RLS still applies.
create view core.company
with (security_invoker = true) as
select * from core.customer;

comment on view core.company is
  'DEPRECATED compatibility shim for the rename to core.customer. New code must use core.customer. Dropped in a later owner-approved contract migration once CRM/PM/PLM/DAM no longer reference core.company.';

grant select on core.company to authenticated;
grant all on core.company to service_role;
