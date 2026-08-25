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
    -- Both typed source rows must exist and agree exactly. The pair is the evidence that
    -- this is one approved Property used in both licensed divisions, never two records.
    select count(*),count(*) filter(where
      e.company_code<>'EDGEHOME' or e.mg_type_code<>'06'
      or e.division_code not in ('CW001','SP001')
      or core.normalize_popsg_property_observation(e.name)
         <>core.normalize_popsg_property_observation(v_row.canonical_name)
      or e.property_id is not null)
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

    insert into core.property(id,licensor_id,name,code,status,metadata)
    values(v_row.canonical_id,v_paramount_id,v_row.canonical_name,v_row.code,'active',
      jsonb_build_object('authority','owner_ruling','approval_issue','#539',
        'implementation_issue','#1177','approved_mapping_hash',
        '09e18e47d67181b06483d6cf4454e053'));
    v_property_id:=v_row.canonical_id;

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
end; $migration$;
