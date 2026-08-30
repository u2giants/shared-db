-- Issue #1872: privacy-safe Creative mapping and signed-contract status.
-- Structure only: no licensed labels, mappings, document identifiers, or evidence values.

create table plm.creative_submission_contract_resolution (
  resolution_id uuid primary key default gen_random_uuid(),
  submission_source_system text not null check (btrim(submission_source_system) <> ''),
  submission_source_table text not null check (btrim(submission_source_table) <> ''),
  submission_source_id text not null check (btrim(submission_source_id) <> ''),
  decision_version bigint not null check (decision_version > 0),
  decision_state text not null check (decision_state in ('evidenced','not_evidenced','conflict')),
  supersedes_resolution_id uuid null references plm.creative_submission_contract_resolution(resolution_id) on delete restrict,
  contract_capture_id uuid null,
  contract_property_id uuid null,
  reviewed_batch_id uuid not null,
  reviewed_batch_digest text not null check (reviewed_batch_digest ~ '^sha256:[0-9a-f]{64}$'),
  approval_actor_id uuid not null,
  approved_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint creative_submission_contract_resolution_identity_version_uq unique
    (submission_source_system, submission_source_table, submission_source_id, decision_version),
  constraint creative_submission_contract_resolution_supersedes_uq unique (supersedes_resolution_id),
  constraint creative_submission_contract_resolution_contract_fk foreign key
    (contract_capture_id, contract_property_id)
    references plm.contract_property(capture_id, id) on delete restrict,
  constraint creative_submission_contract_resolution_shape_ck check (
    (decision_state = 'evidenced' and contract_capture_id is not null and contract_property_id is not null)
    or (decision_state <> 'evidenced' and contract_capture_id is null and contract_property_id is null)
  ),
  constraint creative_submission_contract_resolution_not_self_ck check
    (supersedes_resolution_id is null or supersedes_resolution_id <> resolution_id)
);

create index creative_submission_contract_resolution_latest_idx
  on plm.creative_submission_contract_resolution
  (submission_source_system, submission_source_table, submission_source_id, decision_version desc, resolution_id desc);

alter table plm.creative_submission_contract_resolution enable row level security;
alter table plm.creative_submission_contract_resolution force row level security;
revoke all on plm.creative_submission_contract_resolution from public, anon, authenticated, service_role;
grant select, insert on plm.creative_submission_contract_resolution to service_role;

comment on table plm.creative_submission_contract_resolution is
  'Private service-only exact Submissions identity decisions linking to signed-contract Property evidence. Browser access is only through sanitized API status.';

do $migration$
declare
  v_definition text;
  v_from_needle constant text := '    from source_rows s';
  v_from_replacement constant text := $sql$    from source_rows s
    left join lateral (
      select r.*
      from plm.creative_submission_property_resolution r
      where r.creative_source_system = s.source_system
        and r.creative_source_table = s.source_table
        and r.creative_source_id = s.source_property_id
        and not exists (
          select 1 from plm.creative_submission_property_resolution newer
          where newer.supersedes_resolution_id = r.resolution_id
        )
      order by r.decision_version desc, r.approved_at desc, r.resolution_id desc
      limit 1
    ) creative_decision on true
    left join lateral (
      select
        coalesce(jsonb_agg(jsonb_build_object(
          'source_system', m.submission_source_system,
          'source_table', m.submission_source_table,
          'source_id', m.submission_source_id,
          'display_label', m.submission_source_id
        ) order by m.submission_source_system, m.submission_source_table, m.submission_source_id), '[]'::jsonb) as members,
        case
          when bool_or(contract_decision.decision_state = 'conflict') then 'conflict'
          when bool_or(contract_decision.resolution_id is null) then 'unknown'
          when bool_or(contract_decision.decision_state = 'evidenced' and not capture.controlling_chain_complete) then 'incomplete_chain'
          when bool_or(contract_decision.decision_state = 'not_evidenced')
            or bool_or(contract_decision.decision_state = 'evidenced' and evidence.id is null) then 'not_evidenced'
          when bool_and(contract_decision.decision_state = 'evidenced'
            and capture.controlling_chain_complete and evidence.id is not null) then 'entitled_evidenced'
          else 'unknown'
        end as contract_status
      from plm.creative_submission_property_resolution_member m
      left join lateral (
        select cr.* from plm.creative_submission_contract_resolution cr
        where cr.submission_source_system = m.submission_source_system
          and cr.submission_source_table = m.submission_source_table
          and cr.submission_source_id = m.submission_source_id
          and not exists (select 1 from plm.creative_submission_contract_resolution newer
            where newer.supersedes_resolution_id = cr.resolution_id)
        order by cr.decision_version desc, cr.approved_at desc, cr.resolution_id desc limit 1
      ) contract_decision on true
      left join plm.contract_property_capture capture on capture.id = contract_decision.contract_capture_id
      left join lateral (
        select e.id from plm.contract_property_evidence e
        where e.capture_id = contract_decision.contract_capture_id
          and e.property_id = contract_decision.contract_property_id limit 1
      ) evidence on true
      where m.resolution_id = creative_decision.resolution_id
    ) submission_summary on true$sql$;
  v_json_needle constant text := $sql$        'review_guidance', n.review_guidance,$sql$;
  v_json_replacement constant text := $sql$        'review_guidance', n.review_guidance,
        'mapping_state', case when n.source_purpose like 'Creative%'
          then coalesce(n.creative_mapping_state, 'unmapped') else null end,
        'submissions', case when n.source_purpose like 'Creative%'
          then coalesce(n.submission_members, '[]'::jsonb) else '[]'::jsonb end,
        'contract_status', case when n.source_purpose not like 'Creative%' then null
          when coalesce(n.creative_mapping_state, 'unmapped') = 'conflict' then 'conflict'
          when coalesce(n.creative_mapping_state, 'unmapped') <> 'mapped' then 'unknown'
          else coalesce(n.sanitized_contract_status, 'unknown') end,$sql$;
begin
  select pg_get_functiondef('api.db_data_admin_scraped_properties(text,text,integer)'::regprocedure)
    into v_definition;
  if position(v_from_needle in v_definition) = 0 or position(v_json_needle in v_definition) = 0
     or position('creative_mapping_state' in v_definition) <> 0 then
    raise exception using errcode = '55000', message = '#1872 API predecessor differs from reviewed definition';
  end if;
  v_definition := replace(v_definition, v_from_needle, v_from_replacement);
  v_definition := replace(v_definition,
    '      s.*,' || chr(10),
    '      s.*,' || chr(10) ||
    '      creative_decision.decision_state::text as creative_mapping_state,' || chr(10) ||
    '      coalesce(submission_summary.members, ''[]''::jsonb) as submission_members,' || chr(10) ||
    '      submission_summary.contract_status::text as sanitized_contract_status,' || chr(10));
  v_definition := replace(v_definition, v_json_needle, v_json_replacement);
  execute v_definition;
end;
$migration$;

comment on function api.db_data_admin_scraped_properties(text,text,integer) is
  'Licensing-manager-gated source Property vocabulary with exact Creative-to-Submissions decisions and sanitized contract status. Private contract evidence and licensed source rows are never returned.';
revoke all on function api.db_data_admin_scraped_properties(text,text,integer) from public, anon, service_role;
grant execute on function api.db_data_admin_scraped_properties(text,text,integer) to authenticated;

-- derived-from: none
