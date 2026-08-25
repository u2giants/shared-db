-- Issue #1177: owner-approved widening of the ColdLion Property gate.
-- Exactly five genuinely new canonical Properties are admitted under the owner-approved
-- Paramount -> Viacom Multi Licensor alias. Each has two typed ColdLion identities, one in
-- CW001 and one in SP001. No fuzzy match or inferred ownership is permitted.

do $migration$
declare
  v_paramount_id uuid;
  v_paramount_matches integer;
  v_row record;
  v_hits integer;
  v_mirror_count integer;
  v_bad_mirrors integer;
  v_property_id uuid;
  v_plan_id uuid;
  v_snap jsonb;
  v_function_def text;
  v_pin_count integer;
  v_division text;
  v_mirror_raw jsonb;
  v_header_desc text;
  v_header_count integer;
  v_reason constant text :=
    'Owner-approved ColdLion mapping under Paramount: issue #539; implemented by issue #1177; '
    'approved artifact md5 09e18e47d67181b06483d6cf4454e053.';
begin
  -- Paramount is an owner-approved alias for exactly one canonical Licensor. Resolving by
  -- the alias preserves the existing canonical label/code instead of inventing another.
  select count(*),min(la.licensor_id::text)::uuid
    into v_paramount_matches,v_paramount_id
  from core.licensor_alias la
  join core.licensor l on l.id=la.licensor_id
  where la.normalized_alias=core.normalize_popsg_property_observation('Paramount')
    and la.approval_status='owner_approved'
    and la.approved_by='Albert Hazan';
  if v_paramount_matches<>1 then
    raise exception 'Paramount owner-approved alias resolved to % canonical Licensors, expected 1; refusing to guess',
      v_paramount_matches;
  end if;

  for v_row in
    select * from (values
      ('AM1','Anchorman: The Legend of Ron Burgundy',
        'b288be08-a859-4d92-b1ef-23b4e305ed26'::uuid),
      ('AM2','Anchorman 2: The Legend Continues',
        '2ebcdc69-88c9-4565-813b-9ce30a2b880f'::uuid),
      ('MGM','Mighty Mouse','336e0dac-2001-4a8b-be89-04b1620587ce'::uuid),
      ('WND','It''s a Wonderful Life (B/W)',
        '85fa1834-6094-41d0-94c1-24dddf9c8d8b'::uuid),
      ('EP','Emily in Paris','c1e2ba88-b5c3-4ed2-9ed3-7d4f75ec8230'::uuid)
    ) as approved(code,canonical_name,canonical_id)
  loop
    -- The approved artifact, not a prior capture in this environment, is the
    -- authority for these ten typed identities. Establish an absent exact key;
    -- never update an existing row here. The validation immediately below then
    -- requires both inserted-or-existing rows to agree on every governed field.
    foreach v_division in array array['CW001','SP001']
    loop
      select count(*),min(h.mg_type_desc) into v_header_count,v_header_desc
      from plm.merch_group_header h
      where h.company_code='EDGEHOME' and h.division_code=v_division
        and h.mg_type_code='06' and lower(btrim(h.mg_type_desc))='property';
      if v_header_count<>1 then
        raise exception 'ColdLion %/06 Property header resolved to % rows; refusing to fabricate source type authority',
          v_division,v_header_count;
      end if;
      v_mirror_raw:=jsonb_build_object(
        'authority','owner_approved_mapping_artifact',
        'approval_issue','#539','implementation_issue','#1177',
        'approved_mapping_hash','09e18e47d67181b06483d6cf4454e053',
        'companyCode','EDGEHOME','divisionCode',v_division,
        'mgTypeCode','06','mgTypeDesc',v_header_desc,
        'mgCode',v_row.code,'mgDesc',v_row.canonical_name);
      insert into plm.erp_property(company_code,division_code,mg_type_code,mg_code,
        mg_type_desc,name,raw,source_hash)
      values('EDGEHOME',v_division,'06',v_row.code,v_header_desc,v_row.canonical_name,
        v_mirror_raw,md5(v_mirror_raw::text))
      on conflict(company_code,division_code,mg_type_code,mg_code) do nothing;
    end loop;

    -- Both typed source rows must exist and agree exactly. The pair is the evidence that
    -- this is one approved Property used in both licensed divisions, never two records.
    select count(*),count(*) filter(where
      e.company_code<>'EDGEHOME' or e.mg_type_code<>'06'
      or e.division_code not in ('CW001','SP001')
      or lower(btrim(e.mg_type_desc))<>'property'
      or core.normalize_popsg_property_observation(e.name)
         <>core.normalize_popsg_property_observation(v_row.canonical_name)
      or e.property_id is not null or e.resolution_status<>'unresolved')
      into v_mirror_count,v_bad_mirrors
    from plm.erp_property e
    where e.company_code='EDGEHOME' and e.mg_type_code='06' and e.mg_code=v_row.code;
    if v_mirror_count<>2 or v_bad_mirrors<>0
       or (select count(distinct division_code) from plm.erp_property
           where company_code='EDGEHOME' and mg_type_code='06' and mg_code=v_row.code)<>2 then
      raise exception 'ColdLion Property % does not have exactly two unresolved, name-matching CW001/SP001 typed rows; refusing',v_row.code;
    end if;

    -- §6.4 matched-row abstention. Probe every canonical identifying surface before
    -- claiming the row is absent. Any hit is a possible match and aborts the migration.
    select
      (select count(*) from core.property p where p.id=v_row.canonical_id
        or core.normalize_popsg_property_observation(coalesce(p.code,''))=
           core.normalize_popsg_property_observation(v_row.code)
        or core.normalize_popsg_property_observation(p.name)=
           core.normalize_popsg_property_observation(v_row.canonical_name))
      +(select count(*) from core.property_alias a where
          a.normalized_alias=core.normalize_popsg_property_observation(v_row.code)
          or a.normalized_alias=core.normalize_popsg_property_observation(v_row.canonical_name))
      +(select count(*) from core.taxonomy_source_ref r where
          r.entity_table='property' and (
            core.normalize_popsg_property_observation(coalesce(r.source_code,''))=
              core.normalize_popsg_property_observation(v_row.code)
            or core.normalize_popsg_property_observation(coalesce(r.source_name,''))=
              core.normalize_popsg_property_observation(v_row.canonical_name)
            or r.source_id in ('EDGEHOME/CW001/06/'||v_row.code,
                               'EDGEHOME/SP001/06/'||v_row.code)))
      into v_hits;
    if v_hits<>0 then
      raise exception 'Property % has % existing canonical/alias/source-ref identity hit(s); matched-row abstention requires review, not overwrite or duplicate insert',
        v_row.code,v_hits;
    end if;

    -- The licensing guard requires reviewed creates to enter as potential. The same
    -- transaction then promotes only status under its separately consumed ColdLion
    -- status authorization, after the exact owner-approved source pair has passed.
    v_plan_id:=gen_random_uuid();
    insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,
      write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
    values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',v_plan_id,
      encode(extensions.digest('1177/create/'||v_row.canonical_id::text,'sha256'),'hex'),
      'shared-db migration 20260825050407',array['licensor_id','name','code','status'],
      clock_timestamp()+interval '1 minute');

    insert into core.property(id,licensor_id,name,code,status,metadata)
    values(v_row.canonical_id,v_paramount_id,v_row.canonical_name,v_row.code,'potential',
      jsonb_build_object('authority','owner_ruling','approval_issue','#539',
        'implementation_issue','#1177','approved_mapping_hash',
        '09e18e47d67181b06483d6cf4454e053'));
    v_property_id:=v_row.canonical_id;

    v_plan_id:=gen_random_uuid();
    insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,
      write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
    values(pg_backend_pid(),txid_current(),'core.property','coldlion_status',v_plan_id,
      encode(extensions.digest('1177/activate/'||v_row.canonical_id::text,'sha256'),'hex'),
      'shared-db migration 20260825050407',array['status'],clock_timestamp()+interval '1 minute');
    update core.property set status='active' where id=v_property_id and status='potential';
    get diagnostics v_hits=row_count;
    if v_hits<>1 then
      raise exception 'Property % activation updated % rows, expected 1',v_row.code,v_hits;
    end if;

    insert into core.taxonomy_source_ref(entity_schema,entity_table,entity_id,
      source_system,source_table,source_id,source_code,source_name,confidence,raw)
    select 'core','property',v_property_id,'coldlion','merchGroupDetails',
      concat_ws('/','EDGEHOME',e.division_code,'06',v_row.code),v_row.code,e.name,
      'verified',jsonb_build_object('approval_issue','#539','implementation_issue','#1177',
        'approved_mapping_hash','09e18e47d67181b06483d6cf4454e053')
    from plm.erp_property e
    where e.company_code='EDGEHOME' and e.mg_type_code='06' and e.mg_code=v_row.code
    order by e.division_code;

    update plm.erp_property e set property_id=v_property_id,
      resolution_status='manually_matched',resolution_reason=v_reason,
      resolved_at=now(),resolved_by='Albert Hazan'
    where e.company_code='EDGEHOME' and e.mg_type_code='06' and e.mg_code=v_row.code
      and e.division_code in ('CW001','SP001') and e.property_id is null;
    get diagnostics v_hits=row_count;
    if v_hits<>2 then
      raise exception 'Property % linked % typed mirrors, expected 2; transaction rolled back',v_row.code,v_hits;
    end if;
  end loop;

  if (select count(*) from core.property where id in(
      'b288be08-a859-4d92-b1ef-23b4e305ed26','2ebcdc69-88c9-4565-813b-9ce30a2b880f',
      '336e0dac-2001-4a8b-be89-04b1620587ce','85fa1834-6094-41d0-94c1-24dddf9c8d8b',
      'c1e2ba88-b5c3-4ed2-9ed3-7d4f75ec8230'))<>5
     or (select count(*) from core.taxonomy_source_ref where source_system='coldlion'
       and source_table='merchGroupDetails' and source_id ~
       '^EDGEHOME/(CW001|SP001)/06/(AM1|AM2|MGM|WND|EP)$')<>10
     or (select count(*) from plm.erp_property where company_code='EDGEHOME'
       and division_code in ('CW001','SP001') and mg_type_code='06'
       and mg_code in ('AM1','AM2','MGM','WND','EP') and property_id is not null
       and resolution_status='manually_matched')<>10 then
    raise exception 'Paramount five postcondition failed; transaction rolled back';
  end if;

  -- Keep the active Phase 4 preview health contract synchronized in the same
  -- atomic forward. Refuse if any affected old pin is already different: that is
  -- real concurrent baseline work, not permission to overwrite it.
  select count(*) into v_pin_count
  from plm.taxonomy_baseline_pin p
  join (values
    ('property_count','count',256,null::text),
    ('taxonomy_source_ref_count','count',1047,null),
    ('coldlion_source_ref_count','count',542,null),
    ('linked_property_count','count',504,null),
    ('property_uuid_hash','hash',null,'e0e6c36eb02bb2d320c0deaff7aa8f8c'),
    ('property_status_hash','hash',null,'f436d4acd79761fedbfc9b5796ac7bce'),
    ('parent_edge_hash','hash',null,'7459f6826cc59468779e7ead33ec0edc')
  ) old(metric_key,metric_kind,expected_int,expected_text)
    on old.metric_key=p.metric_key and old.metric_kind=p.metric_kind
   and p.expected_int is not distinct from old.expected_int
   and p.expected_text is not distinct from old.expected_text
  where p.baseline_key='phase4_preview' and p.superseded_at is null;
  if v_pin_count<>7 then
    raise exception 'phase4_preview has % of 7 exact pre-#1177 pins; refusing concurrent/stale baseline overwrite',v_pin_count;
  end if;

  v_snap:=plm.compute_taxonomy_immutability_snapshot();
  if (v_snap->>'property_count')::integer<>261
     or (v_snap->>'taxonomy_source_ref_count')::integer<>1057
     or (v_snap->>'coldlion_source_ref_count')::integer<>552
     or (v_snap->>'linked_property_count')::integer<>514 then
    raise exception 'post-#1177 baseline counts are not exactly 261/1057/552/514: %',v_snap;
  end if;

  update plm.taxonomy_baseline_pin
  set superseded_at=clock_timestamp()
  where baseline_key='phase4_preview' and superseded_at is null
    and metric_key in('property_count','taxonomy_source_ref_count','coldlion_source_ref_count',
      'linked_property_count','property_uuid_hash','property_status_hash','parent_edge_hash');
  get diagnostics v_hits=row_count;
  if v_hits<>7 then raise exception 'superseded % affected pins, expected 7',v_hits; end if;

  insert into plm.taxonomy_baseline_pin(baseline_key,metric_key,metric_kind,expected_int,
    expected_text,effective_from,pinned_by,pinned_reason,source_migration)
  select 'phase4_preview',x.metric_key,x.metric_kind,x.expected_int,x.expected_text,
    clock_timestamp(),'Albert Hazan (owner)',
    'REFRESHED for the five exact Paramount Properties approved in #539 and implemented by #1177; artifact md5 09e18e47d67181b06483d6cf4454e053.',
    '20260825050407_coldlion_paramount_five_approved_gate'
  from (values
    ('property_count','count',261,null::text),
    ('taxonomy_source_ref_count','count',1057,null),
    ('coldlion_source_ref_count','count',552,null),
    ('linked_property_count','count',514,null),
    ('property_uuid_hash','hash',null,v_snap->>'property_uuid_hash'),
    ('property_status_hash','hash',null,v_snap->>'property_status_hash'),
    ('parent_edge_hash','hash',null,v_snap->>'parent_edge_hash')
  ) x(metric_key,metric_kind,expected_int,expected_text);

  -- The recurring promotion function must accept exactly the newly approved
  -- fingerprint. Patch the live latest definition rather than reviving an older
  -- function body and losing subsequent status/authority capabilities.
  select pg_get_functiondef('plm.promote_coldlion_source_owned(jsonb,jsonb,boolean)'::regprocedure)
    into v_function_def;
  if v_function_def not like '%1230f5a12d0f2a3029f1d3df17fc5b5f%'
     or v_function_def not like '%''542''%'
     or v_function_def not like '%''271''%' then
    raise exception 'promotion function no longer carries the exact historical 542/271 fingerprint; refusing blind patch';
  end if;
  v_function_def:=replace(v_function_def,'1230f5a12d0f2a3029f1d3df17fc5b5f',
    '09e18e47d67181b06483d6cf4454e053');
  v_function_def:=replace(v_function_def,'''542''','''552''');
  v_function_def:=replace(v_function_def,'''271''','''276''');
  execute v_function_def;
  -- CREATE OR REPLACE normally preserves ACLs, but promotion authority is too
  -- sensitive to depend on that implicit behavior. Reassert the exact current
  -- internal-function ACL installed by #1429: nobody except the owner may call
  -- it directly; service_role continues through the unchanged public wrapper.
  revoke all on function plm.promote_coldlion_source_owned(jsonb,jsonb,boolean)
    from public,anon,authenticated,service_role;
end; $migration$;
