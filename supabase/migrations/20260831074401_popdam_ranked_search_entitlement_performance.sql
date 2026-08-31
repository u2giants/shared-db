-- #1703: enforce DAM entitlement and bound ranked search before pagination.
-- derived-from: 20260830110517, 20260831041629, 20260831044913

create or replace function public.require_dam_access()
returns boolean
language plpgsql
stable
security definer
set search_path = app, auth, public
as $$
begin
  if auth.role() = 'service_role' or app.has_app_access('dam'::app.app_name) then
    return true;
  end if;
  raise insufficient_privilege using message = 'DAM access is required';
end;
$$;

revoke all on function public.require_dam_access() from public, anon;
grant execute on function public.require_dam_access() to authenticated, service_role;

-- Preserve the proven inlinable body from #1945 behind an entitlement gate.
alter function public.filter_effective_assets(jsonb)
  rename to filter_effective_assets_unchecked_1703;
revoke all on function public.filter_effective_assets_unchecked_1703(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.filter_effective_assets(p_filters jsonb default '{}'::jsonb)
returns setof public.assets
language sql
stable
security invoker
as $$
  select a.*
  from public.filter_effective_assets_unchecked_1703(p_filters) a
  where public.require_dam_access();
$$;

revoke all on function public.filter_effective_assets(jsonb) from public, anon;
grant execute on function public.filter_effective_assets(jsonb) to authenticated, service_role;

-- Keep the two count APIs compatible while closing their direct bypasses.
alter function public.get_effective_filter_counts(jsonb)
  rename to get_effective_filter_counts_unchecked_1703;
revoke all on function public.get_effective_filter_counts_unchecked_1703(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.get_effective_filter_counts(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_dam_access();
  return public.get_effective_filter_counts_unchecked_1703(p_filters);
end;
$$;

alter function public.get_filter_counts(jsonb)
  rename to get_filter_counts_unchecked_1703;
revoke all on function public.get_filter_counts_unchecked_1703(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.get_filter_counts(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_dam_access();
  return public.get_filter_counts_unchecked_1703(p_filters);
end;
$$;

revoke all on function public.get_effective_filter_counts(jsonb) from public, anon;
revoke all on function public.get_filter_counts(jsonb) from public, anon;
grant execute on function public.get_effective_filter_counts(jsonb) to authenticated, service_role;
grant execute on function public.get_filter_counts(jsonb) to authenticated, service_role;

create or replace function public.search_dam_documents(
  p_query text,
  p_filters jsonb,
  p_limit int,
  p_offset int,
  p_document_types text[] default null,
  p_query_embedding extensions.vector(384) default null,
  p_min_rank real default 0
)
returns table(
  document_type text, entity_id uuid, asset_id uuid, style_group_id uuid,
  keyword_rank real, semantic_rank real, rank real,
  total_count bigint, has_more boolean, facets jsonb
)
language sql stable security definer
set search_path = public, extensions
set statement_timeout = '8s'
as $$
  with params as materialized (
    select nullif(trim(p_query), '') query_text,
      greatest(1, least(coalesce(p_limit, 100), 20000)) page_limit,
      greatest(coalesce(p_offset, 0), 0) page_offset,
      greatest(coalesce(p_min_rank, 0), 0)::real min_rank
    where public.require_dam_access()
  ),
  queries as materialized (
    select websearch_to_tsquery('simple', q.query_text) tsq,
      '%' || q.query_text || '%' like_pattern,
      length(q.query_text) >= 3 allow_substring
    from params p
    cross join public.expand_dam_search_queries(p.query_text) q
    where p.query_text is not null
  ),
  keyword_candidates as materialized (
    select d.document_type, d.entity_id, d.asset_id, d.style_group_id,
      greatest(ts_rank_cd(d.search_tsv, q.tsq), 0.01)::real keyword_rank
    from queries q
    join public.dam_search_documents d on d.search_tsv @@ q.tsq
    where p_document_types is null or d.document_type = any(p_document_types)
    union all
    select d.document_type, d.entity_id, d.asset_id, d.style_group_id,
      case when d.title ilike q.like_pattern then 0.04
           when d.path ilike q.like_pattern then 0.03
           when d.customer ilike q.like_pattern or d.program ilike q.like_pattern then 0.02
           else 0.01 end::real keyword_rank
    from queries q
    join public.dam_search_documents d on q.allow_substring and (
      d.title ilike q.like_pattern or d.path ilike q.like_pattern
      or d.customer ilike q.like_pattern or d.program ilike q.like_pattern
    )
    where p_document_types is null or d.document_type = any(p_document_types)
  ),
  semantic_candidates as materialized (
    select d.document_type, d.entity_id, d.asset_id, d.style_group_id,
      greatest(0, 1 - (d.embedding <=> p_query_embedding))::real semantic_rank
    from params p
    join public.dam_search_documents d on p_query_embedding is not null and d.embedding is not null
    where p_document_types is null or d.document_type = any(p_document_types)
    order by d.embedding <=> p_query_embedding
    limit 20000
  ),
  candidate_ranks as materialized (
    select c.document_type, c.entity_id, c.asset_id, c.style_group_id,
      max(c.keyword_rank)::real keyword_rank,
      max(c.semantic_rank)::real semantic_rank,
      (coalesce(max(c.keyword_rank),0) + coalesce(max(c.semantic_rank),0) * 0.35)::real rank
    from (
      select k.document_type,k.entity_id,k.asset_id,k.style_group_id,
        k.keyword_rank,null::real semantic_rank from keyword_candidates k
      union all
      select s.document_type,s.entity_id,s.asset_id,s.style_group_id,
        null::real keyword_rank,s.semantic_rank from semantic_candidates s
    ) c
    group by c.document_type,c.entity_id,c.asset_id,c.style_group_id
    having (coalesce(max(c.keyword_rank),0) + coalesce(max(c.semantic_rank),0) * 0.35)
      >= (select min_rank from params)
  ),
  visible_assets as materialized (
    select a.*
    from public.filter_effective_assets(coalesce(p_filters, '{}'::jsonb) - 'search') a
    where exists (
      select 1 from candidate_ranks c
      where c.asset_id = a.id or c.style_group_id = a.style_group_id
    )
  ),
  ranked_documents as materialized (
    select c.* from candidate_ranks c
    where (c.document_type = 'asset' and exists (
      select 1 from visible_assets a where a.id = c.asset_id
    )) or (c.document_type = 'style_group' and exists (
      select 1 from visible_assets a where a.style_group_id = c.style_group_id
    ))
  ),
  matched_assets as materialized (
    select distinct a.*
    from visible_assets a
    join ranked_documents r on r.asset_id = a.id or r.style_group_id = a.style_group_id
  ),
  summary as materialized (
    select count(*) total_count,
      jsonb_build_object(
        'fileType', coalesce((select jsonb_object_agg(k,c) from (select file_type::text k,count(*) c from matched_assets group by 1) x),'{}'::jsonb),
        'status', coalesce((select jsonb_object_agg(k,c) from (select status::text k,count(*) c from matched_assets group by 1) x),'{}'::jsonb),
        'workflowStatus', coalesce((select jsonb_object_agg(k,c) from (select workflow_status::text k,count(*) c from matched_assets where workflow_status is not null group by 1) x),'{}'::jsonb),
        'stage', coalesce((select jsonb_object_agg(k,c) from (select stage k,count(*) c from matched_assets where stage is not null group by 1) x),'{}'::jsonb),
        'isLicensed', jsonb_build_object(
          'true',(select count(*) from matched_assets where is_licensed is true),
          'false',(select count(*) from matched_assets where is_licensed is not true)
        )
      ) facets
    from ranked_documents
  ),
  page as materialized (
    select r.* from ranked_documents r
    order by r.rank desc,r.document_type,r.entity_id
    offset (select page_offset from params)
    limit (select page_limit from params)
  )
  select p.document_type,p.entity_id,p.asset_id,p.style_group_id,
    p.keyword_rank,p.semantic_rank,p.rank,s.total_count,
    s.total_count > ((select page_offset + page_limit from params)) has_more,
    s.facets
  from page p cross join summary s
  order by p.rank desc,p.document_type,p.entity_id;
$$;

create or replace function public.search_assets_full_text(p_query text, p_limit int default 10000)
returns table(asset_id uuid, style_group_id uuid, rank real)
language sql stable security definer set search_path=public set statement_timeout='8s'
as $$
  select d.asset_id,d.style_group_id,d.rank
  from public.search_dam_documents(p_query,'{}'::jsonb,p_limit,0,array['asset']::text[],null,0) d
  where d.asset_id is not null;
$$;

create or replace function public.search_style_groups_full_text(p_query text, p_limit int default 10000)
returns table(style_group_id uuid, rank real)
language sql stable security definer set search_path=public set statement_timeout='8s'
as $$
  with candidates as materialized (
    select d.* from public.search_dam_documents(
      p_query,'{}'::jsonb,20000,0,array['asset','style_group']::text[],null,0
    ) d
  ), direct_groups as (
    select d.style_group_id,d.rank from candidates d
    where d.document_type = 'style_group'
  ), asset_groups as (
    select d.style_group_id,max(d.rank)*0.8 rank from candidates d
    where d.document_type = 'asset' and d.style_group_id is not null
    group by d.style_group_id
  )
  select x.style_group_id,max(x.rank)::real rank
  from (select * from direct_groups union all select * from asset_groups) x
  where x.style_group_id is not null
  group by x.style_group_id
  order by max(x.rank) desc,x.style_group_id
  limit greatest(1,least(coalesce(p_limit,10000),20000));
$$;

revoke all on function public.search_dam_documents(text,jsonb,int,int,text[],extensions.vector(384),real) from public,anon;
revoke all on function public.search_assets_full_text(text,int) from public,anon;
revoke all on function public.search_style_groups_full_text(text,int) from public,anon;
grant execute on function public.search_dam_documents(text,jsonb,int,int,text[],extensions.vector(384),real) to authenticated,service_role;
grant execute on function public.search_assets_full_text(text,int) to authenticated,service_role;
grant execute on function public.search_style_groups_full_text(text,int) to authenticated,service_role;

comment on function public.search_dam_documents(text,jsonb,int,int,text[],extensions.vector(384),real) is
  'DAM-entitled ranked search: indexed candidates first; effective visibility and filters precede totals, facets, and pagination.';
