-- #2138: restore LIMIT-bounded row fetching in the effective asset filter.
-- The identity arms returned ids only, so every row needed a self-join back to
-- public.assets. Under the generic plan PostgREST gets for a bound p_filters the
-- planner cannot tell which arm supplies ids, drops the primary-key path and
-- rescans the whole identity set once per output row, so cost grows with the
-- page size until the authenticated 8s statement_timeout fires. Selecting whole
-- rows in each arm makes the union a plain append relation the LIMIT can stop
-- early, and entitlement moves back to the Var-free outer conjunct #1703 used,
-- which is evaluated once as a one-time filter and keeps the function inlinable.
-- derived-from: 20260901142825

create or replace function public.filter_effective_assets(p_filters jsonb default '{}'::jsonb)
returns setof public.assets
language sql stable security invoker
as $$
  select a.*
  from (
    -- No identity filter: preserve the simple active-assets path.
    select a.*
    from public.assets a
    where nullif(p_filters ->> 'licensorId', '') is null
      and nullif(p_filters ->> 'propertyId', '') is null
      and nullif(p_filters ->> 'customerId', '') is null
    union all
    -- Licensor is the leading key when supplied; property/customer still narrow.
    select a.*
    from public.assets a
    where nullif(p_filters ->> 'licensorId', '') is not null
      and a.style_group_id is null
      and a.licensor_id = (p_filters ->> 'licensorId')::uuid
      and (nullif(p_filters ->> 'propertyId', '') is null or a.property_id = (p_filters ->> 'propertyId')::uuid)
      and (nullif(p_filters ->> 'customerId', '') is null or a.customer_id = (p_filters ->> 'customerId')::uuid)
    union all
    select a.*
    from public.style_groups sg
    join public.assets a on a.style_group_id = sg.id
    where nullif(p_filters ->> 'licensorId', '') is not null
      and sg.licensor_id = (p_filters ->> 'licensorId')::uuid
      and (nullif(p_filters ->> 'propertyId', '') is null or sg.property_id = (p_filters ->> 'propertyId')::uuid)
      and (nullif(p_filters ->> 'customerId', '') is null or sg.customer_id = (p_filters ->> 'customerId')::uuid)
    union all
    -- Property leads only when licensor is absent.
    select a.*
    from public.assets a
    where nullif(p_filters ->> 'licensorId', '') is null
      and nullif(p_filters ->> 'propertyId', '') is not null
      and a.style_group_id is null
      and a.property_id = (p_filters ->> 'propertyId')::uuid
      and (nullif(p_filters ->> 'customerId', '') is null or a.customer_id = (p_filters ->> 'customerId')::uuid)
    union all
    select a.*
    from public.style_groups sg
    join public.assets a on a.style_group_id = sg.id
    where nullif(p_filters ->> 'licensorId', '') is null
      and nullif(p_filters ->> 'propertyId', '') is not null
      and sg.property_id = (p_filters ->> 'propertyId')::uuid
      and (nullif(p_filters ->> 'customerId', '') is null or sg.customer_id = (p_filters ->> 'customerId')::uuid)
    union all
    -- Customer leads only when neither taxonomy key is supplied.
    select a.*
    from public.assets a
    where nullif(p_filters ->> 'licensorId', '') is null
      and nullif(p_filters ->> 'propertyId', '') is null
      and nullif(p_filters ->> 'customerId', '') is not null
      and a.style_group_id is null
      and a.customer_id = (p_filters ->> 'customerId')::uuid
    union all
    select a.*
    from public.style_groups sg
    join public.assets a on a.style_group_id = sg.id
    where nullif(p_filters ->> 'licensorId', '') is null
      and nullif(p_filters ->> 'propertyId', '') is null
      and nullif(p_filters ->> 'customerId', '') is not null
      and sg.customer_id = (p_filters ->> 'customerId')::uuid
  ) a
  where public.require_dam_access()
    and a.is_deleted = false
    and (a.modified_at >= public.assets_thumbnail_min_date()
      or a.file_created_at >= public.assets_thumbnail_min_date() or a.thumbnail_url is not null)
    and (nullif(p_filters ->> 'search','') is null or a.filename ilike '%' || (p_filters ->> 'search') || '%')
    and (nullif(p_filters ->> 'tagFilter','') is null or exists (
      select 1 from public.asset_effective_tags e where e.asset_id = a.id and e.tag = p_filters ->> 'tagFilter'))
    and (jsonb_array_length(coalesce(p_filters -> 'fileType','[]')) = 0 or a.file_type::text in (select jsonb_array_elements_text(p_filters -> 'fileType')))
    and (jsonb_array_length(coalesce(p_filters -> 'contentType','[]')) = 0 or a.content_type in (select jsonb_array_elements_text(p_filters -> 'contentType')))
    and (jsonb_array_length(coalesce(p_filters -> 'productMaterial','[]')) = 0 or a.product_material && array(select jsonb_array_elements_text(p_filters -> 'productMaterial')))
    and (jsonb_array_length(coalesce(p_filters -> 'status','[]')) = 0 or a.status::text in (select jsonb_array_elements_text(p_filters -> 'status')))
    and (jsonb_array_length(coalesce(p_filters -> 'workflowStatus','[]')) = 0 or a.workflow_status::text in (select jsonb_array_elements_text(p_filters -> 'workflowStatus')))
    and (jsonb_array_length(coalesce(p_filters -> 'stage','[]')) = 0 or a.stage in (select jsonb_array_elements_text(p_filters -> 'stage')))
    and ((p_filters ->> 'isLicensed') is null or a.is_licensed = (p_filters ->> 'isLicensed')::boolean)
    and (jsonb_array_length(coalesce(p_filters -> 'assetType','[]')) = 0 or a.asset_type::text in (select jsonb_array_elements_text(p_filters -> 'assetType')))
    and (jsonb_array_length(coalesce(p_filters -> 'artSource','[]')) = 0 or a.art_source::text in (select jsonb_array_elements_text(p_filters -> 'artSource')))
    and (jsonb_array_length(coalesce(p_filters -> 'fileStatus','[]')) = 0 or exists (
      select 1 from jsonb_array_elements_text(p_filters -> 'fileStatus') fs where
        (fs = 'has_preview' and a.thumbnail_url is not null) or
        (fs = 'no_preview_renderable' and a.thumbnail_url is null and a.thumbnail_error is null) or
        (fs = 'no_pdf_compat' and a.thumbnail_url is null and a.thumbnail_error = 'no_pdf_compat') or
        (fs = 'no_preview_unsupported' and a.thumbnail_url is null and a.thumbnail_error = 'no_preview_or_render_failed')))
    and (jsonb_array_length(coalesce(p_filters -> 'productCategory','[]')) = 0 or
      a.product_category in (select jsonb_array_elements_text(p_filters -> 'productCategory')) or
      ('Wall' in (select jsonb_array_elements_text(p_filters -> 'productCategory')) and
        (a.relative_path ilike '%WALL ART%' or a.relative_path ilike '%3FZ%')))
    and (nullif(p_filters ->> 'customer','') is null or a.customer = p_filters ->> 'customer')
    and (nullif(p_filters ->> 'program','') is null or a.program = p_filters ->> 'program');
$$;

revoke all on function public.filter_effective_assets(jsonb) from public, anon;
grant execute on function public.filter_effective_assets(jsonb) to authenticated, service_role;

do $$
declare
  v_filter text := pg_get_functiondef('public.filter_effective_assets(jsonb)'::regprocedure);
  v_secdef boolean;
  v_config text[];
begin
  select p.prosecdef, p.proconfig into v_secdef, v_config
  from pg_proc p where p.oid = 'public.filter_effective_assets(jsonb)'::regprocedure;

  -- The CTE barrier and the id self-join are the regression; both must be gone.
  if position('identity_asset_ids' in lower(v_filter)) > 0
     or position('as materialized' in lower(v_filter)) > 0
     or position('a.id = i.id' in lower(v_filter)) > 0 then
    raise exception 'effective filter still materialises identity ids before the join';
  end if;

  -- Entitlement stays enforced, as an outer conjunct rather than a CTE.
  if position('public.require_dam_access()' in lower(v_filter)) = 0
     or position('a.is_deleted = false' in lower(v_filter)) = 0 then
    raise exception 'effective filter lost its entitlement or visibility predicate';
  end if;

  -- The seven mutually exclusive identity arms must survive intact.
  if position('union all' in lower(v_filter)) = 0
     or position('left join public.style_groups' in lower(v_filter)) > 0
     or position('a.licensor_id = ' in lower(v_filter)) = 0
     or position('sg.licensor_id = ' in lower(v_filter)) = 0
     or position('a.property_id = ' in lower(v_filter)) = 0
     or position('sg.property_id = ' in lower(v_filter)) = 0
     or position('a.customer_id = ' in lower(v_filter)) = 0
     or position('sg.customer_id = ' in lower(v_filter)) = 0
     or position('a.style_group_id is null' in lower(v_filter)) = 0 then
    raise exception 'effective identity predicates lost index-leading UNION arms';
  end if;

  -- Every filter key the DAM sends must still be honoured.
  if position('search' in v_filter) = 0
     or position('tagFilter' in v_filter) = 0
     or position('fileType' in v_filter) = 0
     or position('contentType' in v_filter) = 0
     or position('productMaterial' in v_filter) = 0
     or position('workflowStatus' in v_filter) = 0
     or position('isLicensed' in v_filter) = 0
     or position('assetType' in v_filter) = 0
     or position('artSource' in v_filter) = 0
     or position('fileStatus' in v_filter) = 0
     or position('productCategory' in v_filter) = 0
     or position('''program''' in v_filter) = 0
     or position('''customer''' in v_filter) = 0
     or position('''stage''' in v_filter) = 0
     or position('''status''' in v_filter) = 0 then
    raise exception 'effective filter lost one of its filter keys';
  end if;

  -- #1945: a SECURITY DEFINER flag or any per-function SET blocks SRF inlining,
  -- which is what makes the outer LIMIT reach the scan at all.
  if v_secdef or v_config is not null then
    raise exception 'effective filter is no longer inlinable (security definer or per-function SET)';
  end if;

  if has_function_privilege('anon','public.filter_effective_assets(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.filter_effective_assets(jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.filter_effective_assets(jsonb)','EXECUTE') then
    raise exception 'effective filter privileges changed';
  end if;
end;
$$;
