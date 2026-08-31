-- #1945: restore bounded authenticated effective-filter execution.
--
-- PostgreSQL cannot inline a SQL-language function that has a per-function SET
-- clause.  The original effective-filter migration attached
-- `SET search_path = public`, so PostgREST's outer LIMIT could not reach the
-- assets scan and every call materialized the full result first.  The body
-- already schema-qualifies every relation and helper function it references;
-- removing only that configuration restores inlining without changing filter,
-- identity, tag, thumbnail, RLS, or privilege semantics.
-- derived-from: 20260830110517

alter function public.filter_effective_assets(jsonb) reset all;

comment on function public.filter_effective_assets(jsonb) is
  'Effective PopDAM asset list with group-winning identity and active effective tags; fully schema-qualified and intentionally free of per-function SET options so caller LIMIT and predicates can be inlined.';

do $$
declare
  v_config text[];
  v_language text;
  v_volatility "char";
  v_security_definer boolean;
  v_source text;
begin
  select p.proconfig, l.lanname, p.provolatile, p.prosecdef, p.prosrc
    into v_config, v_language, v_volatility, v_security_definer, v_source
  from pg_proc p
  join pg_language l on l.oid = p.prolang
  where p.oid = 'public.filter_effective_assets(jsonb)'::regprocedure;

  if v_config is not null then
    raise exception 'filter_effective_assets still has a per-function SET option and cannot inline: %', v_config;
  end if;
  if v_language <> 'sql' or v_volatility <> 's' or v_security_definer then
    raise exception 'filter_effective_assets execution contract changed: language %, volatility %, security definer %',
      v_language, v_volatility, v_security_definer;
  end if;
  if v_source !~ 'from[[:space:]]+public\.assets'
     or v_source !~ 'join[[:space:]]+public\.style_groups'
     or v_source !~ 'from[[:space:]]+public\.asset_effective_tags'
     or v_source !~ 'public\.assets_thumbnail_min_date\(\)' then
    raise exception 'filter_effective_assets is not fully schema-qualified after removing its search_path option';
  end if;
end;
$$;
