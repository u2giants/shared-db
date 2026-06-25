-- Split CRM "ingested domains" out of core.company.
--
-- Problem this fixes
-- ------------------
-- core.company was being used for two different things at once:
--   1. Real, shared business entities (customers/prospects/vendors) that every
--      app (CRM, PM, PLM, DAM) legitimately joins to.
--   2. Every domain that ever appeared in an ingested email — email *noise*,
--      a CRM-internal triage artifact that no other app should see or join to.
-- They were distinguished only by the nullable CRM column `customer_status`
-- (null/UNASSIGNED == "New Company"), so the shared hub table was polluted with
-- thousands of rows that are not companies the business transacts with.
--
-- The fix: ingested email domains are NOT companies. They live in a CRM-private
-- registry, `crm.ingested_domain`. core.company holds only entities that have
-- been *promoted* — i.e. that someone decided is a real account worth tracking.
--
-- This migration is EXPAND-only (additive). It creates the new table, the
-- worker/promotion helper functions, an api view, and copies any existing
-- ingested-domain noise rows out of core.company into the new registry. It does
-- NOT delete the noise rows from core.company — that CONTRACT step is a separate,
-- owner-approved migration once the CRM worker/frontend stop reading them from
-- core.company (see docs/shared-database-vision.md "Company vs Customer").

-- ---------------------------------------------------------------------------
-- crm.ingested_domain  <-  Directus `ingested_domains`
-- CRM-private. Other apps never read or FK to this table.
-- ---------------------------------------------------------------------------
create table if not exists crm.ingested_domain (
  id uuid primary key default gen_random_uuid(),
  domain extensions.citext not null,
  display_name text,
  status text not null default 'new',          -- new | ignored | promoted
  email_count integer not null default 0 check (email_count >= 0),
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  last_sender extensions.citext,
  sample_subject text,
  -- Set only once a domain is promoted to a real, shared account. The promotion
  -- target is a core.company row; everything else hangs off that company id.
  promoted_company_id uuid references core.company(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (domain)
);

comment on table crm.ingested_domain is
  'CRM-private registry of every domain seen in ingested email. NOT a company. Other apps must not read or FK to this table. Promote to core.company to make a domain a shared account.';
comment on column crm.ingested_domain.status is
  'new = unreviewed email noise; ignored = explicitly not a company; promoted = an account exists in core.company (see promoted_company_id).';
comment on column crm.ingested_domain.promoted_company_id is
  'The core.company this domain was promoted into. Null until promoted.';

create index if not exists crm_ingested_domain_status_idx on crm.ingested_domain (status);
create index if not exists crm_ingested_domain_promoted_idx on crm.ingested_domain (promoted_company_id);

create trigger set_updated_at before update on crm.ingested_domain
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- Worker entry point: record an ingested domain WITHOUT creating a core.company.
-- The CRM email worker calls this instead of upserting into core.company.
-- ---------------------------------------------------------------------------
create or replace function crm.record_ingested_domain(
  p_domain text,
  p_sender text default null,
  p_subject text default null,
  p_display_name text default null
)
returns crm.ingested_domain
language plpgsql
security definer
set search_path = crm, core, app, extensions, public
as $$
declare
  v_domain extensions.citext := lower(btrim(p_domain))::extensions.citext;
  v_row crm.ingested_domain;
begin
  if v_domain is null or length(v_domain::text) = 0 then
    raise exception 'crm.record_ingested_domain: domain is required';
  end if;

  insert into crm.ingested_domain (
    domain, display_name, email_count, first_seen_at, last_seen_at,
    last_sender, sample_subject
  )
  values (
    v_domain, p_display_name, 1, now(), now(),
    nullif(p_sender, '')::extensions.citext, nullif(p_subject, '')
  )
  on conflict (domain) do update
  set email_count   = crm.ingested_domain.email_count + 1,
      last_seen_at  = now(),
      last_sender   = coalesce(nullif(p_sender, '')::extensions.citext, crm.ingested_domain.last_sender),
      sample_subject = coalesce(crm.ingested_domain.sample_subject, nullif(p_subject, '')),
      display_name  = coalesce(crm.ingested_domain.display_name, p_display_name)
  returning * into v_row;

  return v_row;
end;
$$;

comment on function crm.record_ingested_domain(text, text, text, text) is
  'Idempotently records an ingested email domain in crm.ingested_domain. Does NOT create a core.company. Replaces any worker path that previously inserted email-noise domains into core.company.';

-- ---------------------------------------------------------------------------
-- Promotion: turn an ingested domain into a real, shared account (a prospect).
-- Returns the core.company id. Idempotent: re-promoting returns the same id.
-- A "prospect" is just a core.company with NO ERP/PLM source ref yet; when the
-- business actually transacts, the PLM/ERP import (plm.import_master_data)
-- attaches a designflow_plm source ref to this same row and it becomes a
-- confirmed customer. No FK re-pointing — the id never changes.
-- ---------------------------------------------------------------------------
create or replace function crm.promote_ingested_domain(
  p_domain text,
  p_name text default null,
  p_customer_status text default 'POTENTIAL_CUSTOMER'
)
returns uuid
language plpgsql
security definer
set search_path = crm, core, app, extensions, public
as $$
declare
  v_domain extensions.citext := lower(btrim(p_domain))::extensions.citext;
  v_dom crm.ingested_domain;
  v_company_id uuid;
  v_name text;
begin
  select * into v_dom from crm.ingested_domain where domain = v_domain;
  if not found then
    raise exception 'crm.promote_ingested_domain: % is not a known ingested domain', p_domain;
  end if;

  if v_dom.promoted_company_id is not null then
    return v_dom.promoted_company_id;   -- already promoted
  end if;

  v_name := coalesce(nullif(p_name, ''), v_dom.display_name, v_domain::text);

  -- Reuse an existing account on the same domain if one already exists.
  select id into v_company_id
  from core.company
  where domain is not null and lower(domain) = v_domain::text
  order by created_at
  limit 1;

  if v_company_id is null then
    insert into core.company (name, company_type, status, domain, customer_status, metadata)
    values (
      v_name, 'customer', 'active', v_domain::text, nullif(p_customer_status, ''),
      jsonb_build_object('promoted_from_ingested_domain', v_domain::text)
    )
    returning id into v_company_id;
  end if;

  update crm.ingested_domain
  set status = 'promoted', promoted_company_id = v_company_id
  where id = v_dom.id;

  return v_company_id;
end;
$$;

comment on function crm.promote_ingested_domain(text, text, text) is
  'Promotes an ingested domain to a shared core.company prospect (no ERP source ref yet) and links it back via promoted_company_id. Idempotent.';

-- ---------------------------------------------------------------------------
-- Browser-facing view for the CRM triage screen.
-- ---------------------------------------------------------------------------
create or replace view api.crm_ingested_domain_list
with (security_invoker = true) as
select
  d.id,
  d.domain::text as domain,
  d.display_name,
  d.status,
  d.email_count,
  d.first_seen_at,
  d.last_seen_at,
  d.last_sender::text as last_sender,
  d.sample_subject,
  d.promoted_company_id,
  c.name as promoted_company_name,
  d.updated_at
from crm.ingested_domain d
left join core.company c on c.id = d.promoted_company_id;

comment on view api.crm_ingested_domain_list is
  'CRM email-domain triage registry. Email noise, not customers. Promote rows to core.company to track them as accounts.';

-- ---------------------------------------------------------------------------
-- RLS — CRM-only, mirrors the crm.* policies in 20260621151155_api_rls_realtime.sql
-- ---------------------------------------------------------------------------
alter table crm.ingested_domain enable row level security;

create policy crm_read on crm.ingested_domain
  for select to authenticated
  using (app.has_app_access('crm') or app.has_role('administrator'));

create policy crm_write on crm.ingested_domain
  for all to authenticated
  using (app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]))
  with check (app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

grant select on crm.ingested_domain to authenticated;
grant all on crm.ingested_domain to service_role;
grant select on api.crm_ingested_domain_list to authenticated;
revoke all on function crm.record_ingested_domain(text, text, text, text) from public;
revoke all on function crm.promote_ingested_domain(text, text, text) from public;
grant execute on function crm.record_ingested_domain(text, text, text, text) to service_role;
grant execute on function crm.promote_ingested_domain(text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill (EXPAND, safe): copy existing ingested-domain noise OUT of
-- core.company into crm.ingested_domain. We DO NOT delete from core.company here.
--
-- "Noise" = a company that:
--   * was sourced from Directus `ingested_domains`, AND
--   * has no ERP/PLM source ref (never confirmed as a real customer), AND
--   * is untriaged (customer_status is null or UNASSIGNED), AND
--   * is not referenced by any opportunity / contact / department.
-- Anything referenced or curated has effectively been promoted and stays in
-- core.company. Idempotent via `on conflict (domain) do nothing`.
-- ---------------------------------------------------------------------------
insert into crm.ingested_domain (domain, display_name, status, metadata, first_seen_at, last_seen_at)
select
  lower(coalesce(c.domain, sr.source_code, c.name))::extensions.citext as domain,
  c.name,
  'new',
  jsonb_build_object('backfilled_from_core_company_id', c.id),
  c.created_at,
  c.updated_at
from core.company c
join core.company_source_ref sr
  on sr.company_id = c.id and sr.source_table = 'ingested_domains'
where coalesce(lower(coalesce(c.domain, sr.source_code, c.name)), '') <> ''
  and (c.customer_status is null or upper(c.customer_status) = 'UNASSIGNED')
  -- never a confirmed ERP customer
  and not exists (
    select 1 from core.company_source_ref e
    where e.company_id = c.id and e.source_system in ('designflow_plm', 'coldlion')
  )
  -- not referenced by CRM workflow
  and not exists (select 1 from crm.opportunity o where o.company_id = c.id)
  and not exists (select 1 from crm.department dp where dp.company_id = c.id)
  and not exists (select 1 from core.contact_company cc where cc.company_id = c.id)
on conflict (domain) do nothing;
