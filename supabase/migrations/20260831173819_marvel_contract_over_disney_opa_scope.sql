-- Issue #1999: Disney OPA cannot distinguish Marvel from Disney submissions.
-- Preserve every existing fail-closed rule except this one proven false conflict.
do $migration$
declare
  v_definition text;
  v_updated text;
  v_disney_arm text;
  v_lucasfilm_arm text;
  v_disney_start integer;
  v_lucasfilm_start integer;
  v_updated_lucasfilm_start integer;
  v_old text := $old$and r.contract_asserted_studio_code <> o.opa_studio_code$old$;
  v_new text := $new$and r.contract_asserted_studio_code <> o.opa_studio_code
          and not (
            r.contract_asserted_studio_code = 'marvel'
            and o.opa_studio_code = 'disney'
          )$new$;
begin
  select pg_get_functiondef(
    'api.db_data_admin_scraped_properties(text,text,integer)'::regprocedure
  ) into v_definition;

  v_disney_start := position('from plm.dcp_property p' in v_definition);
  v_lucasfilm_start := position('from plm.lucasfilm_dcp_property p' in v_definition);

  if v_disney_start = 0
     or v_lucasfilm_start <= v_disney_start
     or position('from plm.dcp_property p' in
          substring(v_definition from v_disney_start + 1)) <> 0
     or position('from plm.lucasfilm_dcp_property p' in
          substring(v_definition from v_lucasfilm_start + 1)) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'db_data_admin_scraped_properties Disney/Lucasfilm authority arms differ from the reviewed #1999 definition';
  end if;

  v_disney_arm := substring(
    v_definition from v_disney_start for v_lucasfilm_start - v_disney_start
  );
  v_lucasfilm_arm := substring(v_definition from v_lucasfilm_start);

  if position(v_new in v_disney_arm) <> 0 then
    if position(v_old in v_lucasfilm_arm) = 0
       or position(v_new in v_lucasfilm_arm) <> 0 then
      raise exception using
        errcode = 'P0001',
        message = 'db_data_admin_scraped_properties Lucasfilm authority changed while #1999 was already installed';
    end if;
    return;
  end if;

  if position(v_old in v_disney_arm) = 0
     or position(v_old in substring(
          v_disney_arm from position(v_old in v_disney_arm) + 1)) <> 0
     or position('when o.opa_scope_count > 1 then ''opa_scope_conflict''' in v_disney_arm) = 0
     or position('when r.contract_asserted_studio_code is not null' in v_disney_arm) = 0
     or position('and o.opa_studio_code is not null' in v_disney_arm) = 0
     or position('then ''contract_opa_conflict''' in v_disney_arm) = 0
     or position('and mc.member_count > 0' in v_disney_arm) = 0
     or position(v_old in v_lucasfilm_arm) = 0
     or position(v_new in v_lucasfilm_arm) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'db_data_admin_scraped_properties authority expression differs from the reviewed #1999 definition';
  end if;

  v_updated := overlay(
    v_definition placing replace(v_disney_arm, v_old, v_new)
    from v_disney_start for length(v_disney_arm)
  );
  v_updated_lucasfilm_start := position(
    'from plm.lucasfilm_dcp_property p' in v_updated
  );

  if v_updated = v_definition
     or position(v_new in substring(
          v_updated from v_disney_start
          for v_updated_lucasfilm_start - v_disney_start
        )) = 0
     or substring(v_updated from v_updated_lucasfilm_start) <> v_lucasfilm_arm then
    raise exception using
      errcode = 'P0001',
      message = 'db_data_admin_scraped_properties Marvel/Disney tie-breaker replacement was not exact';
  end if;

  execute v_updated;
end;
$migration$;

comment on function api.db_data_admin_scraped_properties(text,text,integer) is
  'Licensing-manager-gated source Property vocabulary. Signed-contract and direct OPA scope disagreements fail closed, except that a Marvel contract assertion wins over Disney OPA scope because OPA does not expose a separate Marvel creation branch. Multi-scope OPA conflicts, Lucasfilm/Star Wars authority, Pixar authority, ASGARD-only Marvel Creative authority, pagination, sanitized review context, and the restricted response envelope remain unchanged.';

revoke all on function api.db_data_admin_scraped_properties(text,text,integer)
  from public, anon, service_role;
grant execute on function api.db_data_admin_scraped_properties(text,text,integer)
  to authenticated;
