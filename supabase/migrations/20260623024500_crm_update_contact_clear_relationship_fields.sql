-- Let popcrm-web intentionally clear CRM contact relationship fields.
--
-- The original RPC used coalesce() for relationship attributes, so passing null
-- meant "leave unchanged". That made UI actions such as clearing Contact Type or
-- unassigning a Department look successful optimistically while the database kept
-- the previous value. Add explicit clear flags so null remains unambiguous.

drop function if exists api.crm_update_contact(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text
);

create or replace function api.crm_update_contact(
  p_contact_id uuid,
  p_first_name text default null,
  p_last_name text default null,
  p_full_name text default null,
  p_email text default null,
  p_phone text default null,
  p_job_title text default null,
  p_company_id uuid default null,
  p_crm_department_id uuid default null,
  p_contact_type text default null,
  p_scope text default null,
  p_clear_company boolean default false,
  p_clear_crm_department boolean default false,
  p_clear_contact_type boolean default false,
  p_clear_scope boolean default false
)
returns core.contact
language plpgsql
security definer
set search_path = app, core, crm, public
as $$
declare
  result core.contact;
begin
  if not app.has_app_access('crm') then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  update core.contact ct
  set
    first_name = coalesce(p_first_name, ct.first_name),
    last_name  = coalesce(p_last_name, ct.last_name),
    full_name  = coalesce(
      p_full_name,
      nullif(trim(concat_ws(' ', coalesce(p_first_name, ct.first_name), coalesce(p_last_name, ct.last_name))), ''),
      ct.full_name
    ),
    email      = coalesce(p_email::extensions.citext, ct.email),
    phone      = coalesce(p_phone, ct.phone),
    title      = coalesce(p_job_title, ct.title)
  where ct.id = p_contact_id
  returning ct.* into result;

  if not found then
    raise exception 'crm: contact % not found', p_contact_id using errcode = 'no_data_found';
  end if;

  if p_clear_company then
    delete from core.contact_company cc
    where cc.id = (
      select x.id
      from core.contact_company x
      where x.contact_id = p_contact_id
        and x.relationship_type = 'buyer'
      order by x.is_primary desc nulls last, x.id
      limit 1
    );
  elsif p_company_id is not null then
    update core.contact_company
    set is_primary = false
    where contact_id = p_contact_id
      and relationship_type = 'buyer';

    insert into core.contact_company (
      contact_id,
      company_id,
      relationship_type,
      contact_type,
      scope,
      crm_department_id,
      is_primary
    )
    values (
      p_contact_id,
      p_company_id,
      'buyer',
      case when p_clear_contact_type then null else p_contact_type end,
      case when p_clear_scope then null else p_scope end,
      case when p_clear_crm_department then null else p_crm_department_id end,
      true
    )
    on conflict (contact_id, company_id, relationship_type) do update
    set
      contact_type = case
        when p_clear_contact_type then null
        else coalesce(excluded.contact_type, core.contact_company.contact_type)
      end,
      scope = case
        when p_clear_scope then null
        else coalesce(excluded.scope, core.contact_company.scope)
      end,
      crm_department_id = case
        when p_clear_crm_department then null
        else coalesce(excluded.crm_department_id, core.contact_company.crm_department_id)
      end,
      is_primary = true;
  end if;

  return result;
end;
$$;

revoke all on function api.crm_update_contact(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  boolean,
  boolean,
  boolean,
  boolean
) from public;

grant execute on function api.crm_update_contact(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  boolean,
  boolean,
  boolean,
  boolean
) to authenticated;

notify pgrst, 'reload schema';
