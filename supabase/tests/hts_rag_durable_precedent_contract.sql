-- Run after the migration in an ephemeral database. Every assertion is transactional.
begin;

do $$
declare v_count integer;
begin
  select count(*) into v_count from information_schema.tables
  where table_schema='public' and table_name in ('hts_rag_precedents','hts_rag_precedent_rulings','hts_rag_product_examples','hts_rag_determinations','hts_rag_extraction_jobs','hts_rag_review_events','hts_rag_product_family_allowlist');
  if v_count <> 7 then raise exception 'expected seven HTS RAG contract tables, got %', v_count; end if;

  select count(*) into v_count from pg_indexes where schemaname='public' and indexname in
    ('hts_rag_precedents_family_review_idx','hts_rag_precedents_extraction_idempotency_idx','hts_rag_precedent_rulings_ruling_idx','hts_rag_precedent_rulings_relationship_idx','hts_rag_product_examples_family_idx','hts_rag_determinations_family_created_idx','hts_rag_determinations_comparison_review_idx','hts_rag_extraction_jobs_pending_claim_idx','hts_rag_extraction_jobs_idempotency_idx','hts_rag_review_events_subject_created_idx','hts_rag_product_family_allowlist_enabled_idx');
  if v_count <> 11 then raise exception 'expected eleven claimed HTS RAG indexes, got %', v_count; end if;

  select count(*) into v_count from pg_policies where schemaname='public' and policyname like 'hts_rag_%';
  if v_count < 14 then raise exception 'expected fourteen HTS RAG policies, got %', v_count; end if;

  if exists (select 1 from information_schema.role_table_grants where table_schema='public' and table_name like 'hts_rag_%' and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE')) then
    raise exception 'browser role received a direct HTS RAG write grant';
  end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema='public' and table_name in ('hts_rag_determinations','hts_rag_review_events') and grantee='service_role' and privilege_type in ('UPDATE','DELETE','TRUNCATE')) then
    raise exception 'immutable comparison/review history received a mutation grant';
  end if;

  -- Row level security must be ENABLED, not merely policied. Policies on a table
  -- with RLS off are inert, so a dropped ENABLE line would expose every row the
  -- SELECT grants below reach while all the other assertions here stayed green.
  select count(*) into v_count from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname='public' and c.relrowsecurity
     and c.relname in ('hts_rag_precedents','hts_rag_precedent_rulings','hts_rag_product_examples','hts_rag_determinations','hts_rag_extraction_jobs','hts_rag_review_events','hts_rag_product_family_allowlist');
  if v_count <> 7 then raise exception 'row level security is not enabled on all seven HTS RAG tables, got %', v_count; end if;

  -- No read path for the unauthenticated browser role or PUBLIC, on any privilege.
  if exists (select 1 from information_schema.role_table_grants where table_schema='public' and table_name like 'hts_rag_%' and grantee in ('anon','PUBLIC')) then
    raise exception 'anon or PUBLIC holds a grant on an HTS RAG table';
  end if;

  -- Every authenticated read must sit behind an administrator policy, never a bare grant.
  if exists (
    select 1 from information_schema.role_table_grants g
     where g.table_schema='public' and g.table_name like 'hts_rag_%'
       and g.grantee='authenticated'
       and not exists (select 1 from pg_policies p where p.schemaname='public' and p.tablename=g.table_name and p.cmd in ('SELECT','ALL'))
  ) then
    raise exception 'authenticated holds a grant on an HTS RAG table with no read policy';
  end if;
end $$;

insert into public.hts_rag_product_examples(product_family,fixture_version,fixture_hash,input_hash)
values ('ceramic figurine','fixture-v1',repeat('a',64),repeat('b',64));

insert into public.hts_rag_precedents(product_family,fixture_version,prompt_version,classifier_model,verifier_model,extraction_version,fixture_hash,input_hash,raw_result_hash,proposed_hts,classification_state,missing_critical_facts,conflicts,decision_card_candidate,operative_eligible)
values ('ceramic figurine','fixture-v1','prompt-v1','classifier-v1','verifier-v1','extract-v1',repeat('a',64),repeat('b',64),repeat('c',64),'6913','needs_more_facts','["ceramic subtype"]','["toy function unresolved"]',true,false);

do $$ begin
  begin
    insert into public.hts_rag_precedents(product_family,fixture_version,prompt_version,classifier_model,verifier_model,extraction_version,fixture_hash,input_hash,raw_result_hash,classification_state)
    values ('ceramic figurine','fixture-v1','prompt-v1','classifier-v1','verifier-v1','extract-v1',repeat('a',64),repeat('b',64),repeat('c',64),'needs_more_facts');
    raise exception 'duplicate extraction identity was accepted';
  exception when unique_violation then null; end;

  begin
    insert into public.hts_rag_precedents(product_family,fixture_version,prompt_version,classifier_model,verifier_model,extraction_version,fixture_hash,input_hash,raw_result_hash,classification_state,operative_eligible)
    values ('bad','f','p','c','v','e',repeat('d',64),repeat('e',64),repeat('f',64),'needs_more_facts',true);
    raise exception 'incomplete classification became operative';
  exception when check_violation then null; end;

  begin
    insert into public.hts_rag_product_family_allowlist(product_family,enabled) values ('ceramic figurine',true);
    raise exception 'allowlist enabled without accountable review';
  exception when check_violation then null; end;
end $$;

insert into public.hts_rag_product_family_allowlist(product_family) values ('ceramic figurine');
do $$ begin
  if (select enabled from public.hts_rag_product_family_allowlist where product_family='ceramic figurine') then raise exception 'allowlist did not default disabled'; end if;
end $$;

rollback;
