-- Issue #1658 preview-forward reconciliation.
-- Preview applied original version 20260827134155 in run 33095556822. Governed
-- reconciliation run 33100418436 removed that orphan ledger row but retained
-- its catalog. Verify that exact residue, then install only review hardening.

do $reconcile$
declare
  v_actual text[];
  v_expected constant text[] := array[
    'dcp_opa_property_resolution_approval_ck=CHECK (approval_status = ANY (ARRAY[''pending''::text, ''approved''::text, ''rejected''::text]))',
    'dcp_opa_property_resolution_approved_shape_ck=CHECK (approval_status = ''approved''::text AND approved_at IS NOT NULL AND approved_by IS NOT NULL AND btrim(approved_by) <> ''''::text OR approval_status <> ''approved''::text AND approved_at IS NULL AND approved_by IS NULL)',
    'dcp_opa_property_resolution_contract_assertion_ck=CHECK (contract_asserted_studio_code IS NULL AND contract_evidence_reference IS NULL AND contract_evidence_sha256 IS NULL OR (contract_asserted_studio_code = ANY (ARRAY[''disney''::text, ''marvel''::text, ''lucasfilm''::text, ''pixar''::text])) AND btrim(contract_evidence_reference) <> ''''::text AND contract_evidence_sha256 ~ ''^[0-9a-f]{64}$''::text)',
    'dcp_opa_property_resolution_evidence_ck=CHECK (btrim(evidence_reference) <> ''''::text AND evidence_sha256 ~ ''^[0-9a-f]{64}$''::text AND btrim(decision_reason) <> ''''::text)',
    'dcp_opa_property_resolution_id_identity_key=UNIQUE (resolution_id, source_system, source_table, source_property_id)',
    'dcp_opa_property_resolution_identity_ck=CHECK (btrim(source_system) <> ''''::text AND btrim(source_property_id) <> ''''::text AND (source_table = ANY (ARRAY[''plm.dcp_property''::text, ''plm.lucasfilm_dcp_property''::text, ''plm.marvel_dcp_property''::text])))',
    'dcp_opa_property_resolution_identity_version_key=UNIQUE (source_system, source_table, source_property_id, decision_version)',
    'dcp_opa_property_resolution_member_licensed_property_id_fkey=FOREIGN KEY (licensed_property_id) REFERENCES plm.opa_property(licensed_property_id) ON DELETE RESTRICT',
    'dcp_opa_property_resolution_member_ordinal_ck=CHECK (member_ordinal > 0)',
    'dcp_opa_property_resolution_member_ordinal_key=UNIQUE (resolution_id, member_ordinal)',
    'dcp_opa_property_resolution_member_pkey=PRIMARY KEY (resolution_id, licensed_property_id)',
    'dcp_opa_property_resolution_member_resolution_id_fkey=FOREIGN KEY (resolution_id) REFERENCES plm.dcp_opa_property_resolution(resolution_id) ON DELETE RESTRICT',
    'dcp_opa_property_resolution_not_self_superseding_ck=CHECK (supersedes_resolution_id IS NULL OR supersedes_resolution_id <> resolution_id)',
    'dcp_opa_property_resolution_pkey=PRIMARY KEY (resolution_id)',
    'dcp_opa_property_resolution_same_identity_supersession_fk=FOREIGN KEY (supersedes_resolution_id, source_system, source_table, source_property_id) REFERENCES plm.dcp_opa_property_resolution(resolution_id, source_system, source_table, source_property_id) ON DELETE RESTRICT',
    'dcp_opa_property_resolution_supersedes_key=UNIQUE (supersedes_resolution_id)',
    'dcp_opa_property_resolution_supersedes_resolution_id_fkey=FOREIGN KEY (supersedes_resolution_id) REFERENCES plm.dcp_opa_property_resolution(resolution_id) ON DELETE RESTRICT',
    'dcp_opa_property_resolution_version_ck=CHECK (decision_version > 0)'
  ];
begin
  if to_regclass('plm.dcp_opa_property_resolution') is null
     or to_regclass('plm.dcp_opa_property_resolution_member') is null then
    raise exception using errcode = '55000', message = 'expected #1658 preview residue tables are absent';
  end if;

  select array_agg(c.conname || '=' || pg_get_constraintdef(c.oid, true) order by c.conname)
    into v_actual
  from pg_constraint c
  where c.conrelid in ('plm.dcp_opa_property_resolution'::regclass,
                       'plm.dcp_opa_property_resolution_member'::regclass);
  if v_actual is distinct from v_expected then
    raise exception using errcode = '55000', message = 'retained #1658 constraints differ from the proven original catalog';
  end if;

  if (select count(*) from pg_attribute where attrelid = 'plm.dcp_opa_property_resolution'::regclass and attnum > 0 and not attisdropped) <> 16
     or (select count(*) from pg_attribute where attrelid = 'plm.dcp_opa_property_resolution_member'::regclass and attnum > 0 and not attisdropped) <> 4 then
    raise exception using errcode = '55000', message = 'retained #1658 columns differ from the proven original catalog';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'plm.dcp_opa_property_resolution'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'plm.dcp_opa_property_resolution_member'::regclass)
     or (select count(*) from pg_policies where schemaname = 'plm' and tablename in ('dcp_opa_property_resolution','dcp_opa_property_resolution_member')) <> 2
     or (select array_agg(policyname || '=' || cmd || '=' || array_to_string(roles, ',') || '=' || qual order by policyname)
         from pg_policies where schemaname = 'plm' and tablename in ('dcp_opa_property_resolution','dcp_opa_property_resolution_member'))
        is distinct from array[
          'dcp_opa_property_resolution_member_read=SELECT=authenticated=(app.has_role(''administrator''::app.app_role) OR app.has_app_access(''plm''::app.app_name) OR app.has_any_role(ARRAY[''sales''::app.app_role, ''licensing''::app.app_role]))',
          'dcp_opa_property_resolution_read=SELECT=authenticated=(app.has_role(''administrator''::app.app_role) OR app.has_app_access(''plm''::app.app_name) OR app.has_any_role(ARRAY[''sales''::app.app_role, ''licensing''::app.app_role]))'
        ]
     or has_table_privilege('anon', 'plm.dcp_opa_property_resolution', 'SELECT')
     or has_table_privilege('anon', 'plm.dcp_opa_property_resolution_member', 'SELECT')
     or not has_table_privilege('authenticated', 'plm.dcp_opa_property_resolution', 'SELECT')
     or not has_table_privilege('authenticated', 'plm.dcp_opa_property_resolution_member', 'SELECT')
     or has_table_privilege('authenticated', 'plm.dcp_opa_property_resolution', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'plm.dcp_opa_property_resolution_member', 'INSERT,UPDATE,DELETE') then
    raise exception using errcode = '55000', message = 'retained #1658 RLS, policies, or grants differ from the private contract';
  end if;

  if not has_table_privilege('service_role', 'plm.dcp_opa_property_resolution', 'SELECT,INSERT')
     or not has_table_privilege('service_role', 'plm.dcp_opa_property_resolution_member', 'SELECT,INSERT')
     or has_table_privilege('service_role', 'plm.dcp_opa_property_resolution', 'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('service_role', 'plm.dcp_opa_property_resolution_member', 'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception using errcode = '55000', message = 'retained #1658 service-role grants differ from the append-only contract';
  end if;

  if exists (select 1 from pg_constraint where conrelid = 'plm.dcp_opa_property_resolution'::regclass and conname = 'dcp_opa_property_resolution_single_chain_ck')
     or to_regprocedure('plm.reject_dcp_opa_resolution_mutation()') is not null
     or exists (select 1 from pg_trigger where tgrelid in ('plm.dcp_opa_property_resolution'::regclass,'plm.dcp_opa_property_resolution_member'::regclass) and not tgisinternal) then
    raise exception using errcode = '55000', message = 'one or more #1658 hardening objects already exist';
  end if;
end;
$reconcile$;

alter table plm.dcp_opa_property_resolution
  add constraint dcp_opa_property_resolution_single_chain_ck check (
    (decision_version = 1) = (supersedes_resolution_id is null)
  );

create function plm.reject_dcp_opa_resolution_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  raise exception
    'plm.% is append-only: % is not permitted. Record a new superseding decision instead.',
    tg_table_name, tg_op
    using errcode = 'restrict_violation';
end;
$$;

revoke all on function plm.reject_dcp_opa_resolution_mutation() from public;

create trigger dcp_opa_property_resolution_append_only
before update or delete on plm.dcp_opa_property_resolution
for each row execute function plm.reject_dcp_opa_resolution_mutation();

create trigger dcp_opa_property_resolution_member_append_only
before update or delete on plm.dcp_opa_property_resolution_member
for each row execute function plm.reject_dcp_opa_resolution_mutation();

do $verify$
begin
  if to_regprocedure('plm.reject_dcp_opa_resolution_mutation()') is null
     or (select count(*) from pg_trigger where tgrelid in ('plm.dcp_opa_property_resolution'::regclass,'plm.dcp_opa_property_resolution_member'::regclass) and tgname in ('dcp_opa_property_resolution_append_only','dcp_opa_property_resolution_member_append_only') and not tgisinternal) <> 2
     or not exists (select 1 from pg_constraint where conrelid = 'plm.dcp_opa_property_resolution'::regclass and conname = 'dcp_opa_property_resolution_single_chain_ck' and pg_get_constraintdef(oid, true) = 'CHECK ((decision_version = 1) = (supersedes_resolution_id IS NULL))') then
    raise exception using errcode = '55000', message = '#1658 forward hardening postconditions failed';
  end if;
end;
$verify$;
