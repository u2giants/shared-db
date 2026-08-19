-- =====================================================================================
-- NBCU capture publication gate -- close the JSON-null / non-number expected-count hole.
--
-- Issue u2giants/shared-db #1219 (SYSTEMIC), claim #1230.
-- OBJECT REPLACED BY THIS MIGRATION: plm.finalize_nbcu_capture(uuid). NOTHING ELSE.
--
-- THE DEFECT, EXACTLY.
--   The gate decided a count had been supplied with `v_exp ? v_key`. `jsonb ? key` is
--   TRUE for a key whose value is JSON `null`, so {"assets": null} passed that test,
--   `v_want` became SQL NULL, `v_n <> v_want` evaluated to UNKNOWN, and the IF never
--   fired. The count check was SILENTLY SKIPPED. A missing key was correctly rejected;
--   a present-but-null key was not.
--
--   This is not a theoretical shape. `jsonb_build_object('assets', v_unset)` stores
--   `"assets": null`, not an omitted key, so an ordinary loader bug produces it. The
--   capture then reached status 'complete' having landed a fraction of the data, and
--   api.source_capture_inventory reported it as latest-complete.
--
--   The same two lines carried a second defect: `(v_exp ->> v_key)::bigint` is a RAW
--   cast on the TEXT form of the value, so the gate never saw the JSON type at all.
--   A JSON true, a float or an oversized number died with a bare Postgres cast error
--   instead of a named, structured rejection -- which wedges a capture in 'loading'
--   with no recorded reason. A numeric-looking STRING ("12") was worse: it cast
--   cleanly and was ACCEPTED as a count. Both behaviours are measured, not assumed;
--   see supabase/tests/nbcu_landing_contracts.sql section G7.
--
--   Both were live in blocks A and C. Block C's `excluded_unlicensed_assets` and
--   `failures` tests used the identical `?`-then-raw-cast shape and are fixed here too.
--
-- WHAT CHANGES.
--   Every expected count is now decided in FOUR named outcomes instead of two:
--     expected_count_missing                     -- the key is absent
--     expected_count_not_a_number                -- present, but null/string/bool/object/array
--     expected_count_not_a_nonnegative_integer   -- a number, but negative or fractional
--     count_mismatch                             -- a valid count that disagrees with the tables
--   and the numeric cast is reached ONLY after the type test has already passed.
--
--   TWO SEPARATE TESTS, NOT ONE `or`-ED PREDICATE. SQL does not promise to short-circuit
--   `or`, so a single combined predicate may evaluate the numeric cast against a JSON
--   string and die with a raw cast error instead of the intended named message. The
--   WildBrain author hit exactly this (#1197); it is why the checks below are an
--   `elsif` chain rather than a compound condition.
--
--   The gate re-reads the STORED expected_counts object rather than trusting that any
--   validation ran at begin_ time: plm.nbcu_capture is writable by the owner, so an
--   UPDATE can reach the stored value after the capture started.
--
-- WHAT DELIBERATELY DOES NOT CHANGE.
--   * plm.begin_nbcu_capture is NOT touched. It is outside this migration's object
--     claim (#1230 covers plm.finalize_nbcu_capture only), and CI refuses a migration
--     that writes an undeclared object. Issue #1219 also asks for an argument-time
--     refusal there; that half needs its own claim and is reported back, not smuggled
--     in here. The gate below is the load-bearing half regardless -- #1219 requires
--     finalize to re-check the stored object even when begin_ did validate.
--   * excluded_unlicensed_assets and failures stay OPTIONAL keys, exactly as before.
--     Making them required would refuse captures that are legitimate today. What is
--     fixed is that when they ARE present they can no longer be a null or a string that
--     skips or crashes the check.
--   * Every other block (B, D, E, F, F2) and the verdict are re-derived UNCHANGED from
--     20260811070000, the current head definition of this function.
--
-- CONTRACT TESTS: supabase/tests/nbcu_landing_contracts.sql, section G7, added with this
-- migration. Each one FAILS against the pre-fix body.
-- =====================================================================================

create or replace function plm.finalize_nbcu_capture(p_capture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = plm, core, pg_temp
as $$
declare
  v_cap      plm.nbcu_capture%rowtype;
  v_exp      jsonb;
  v_obs      jsonb;
  v_err      jsonb := '[]'::jsonb;
  v_n        bigint;
  v_want     bigint;
  v_key      text;
  v_pairs    text[][] := array[
    ['assets','nbcu_asset'], ['properties','nbcu_property'], ['characters','nbcu_character'],
    ['style_guides','nbcu_style_guide'], ['scopes','nbcu_scope'],
    ['ip_family_property','nbcu_ip_family_property'],
    ['property_character','nbcu_property_character'],
    ['asset_property','nbcu_asset_property'],
    ['asset_character','nbcu_asset_character'],
    ['asset_style_guide','nbcu_asset_style_guide'],
    ['style_guide_property','nbcu_style_guide_property'],
    ['asset_ip_family','nbcu_asset_ip_family']
  ];
  i integer;
begin
  select * into v_cap from plm.nbcu_capture where id = p_capture_id for update;
  if not found then
    raise exception 'finalize_nbcu_capture: no capture %', p_capture_id;
  end if;
  if v_cap.status = 'complete' then
    -- Idempotent. A retry after a successful finalize is a no-op, not an error.
    return jsonb_build_object('capture_id', p_capture_id, 'status', 'complete',
                              'observed_counts', v_cap.observed_counts, 'already_complete', true);
  end if;
  if v_cap.status <> 'loading' then
    raise exception 'finalize_nbcu_capture: capture % is %, not loading', p_capture_id, v_cap.status;
  end if;

  v_exp := v_cap.expected_counts;
  v_obs := '{}'::jsonb;

  -- ---- A. Every entity and edge count must equal what the source contract expects.
  -- Counted from the TABLES, never from a ledger or a summary document. This repository
  -- has shipped a migration that recorded a clean ledger row while its object did nothing,
  -- so "it reported success" is not accepted as evidence of anything.
  for i in 1 .. array_length(v_pairs, 1) loop
    v_key := v_pairs[i][1];
    execute format('select count(*) from plm.%I where capture_id = $1', v_pairs[i][2])
      into v_n using p_capture_id;
    v_obs := v_obs || jsonb_build_object(v_key, v_n);

    -- A KEY PRESENT WITH JSON `null` IS NOT A SUPPLIED COUNT. `v_exp ? v_key` is TRUE
    -- for {"assets": null}, and every comparison against the resulting SQL NULL is
    -- UNKNOWN -- so the old `if v_n <> v_want` never fired and the count went UNCHECKED,
    -- which is the same publication failure as omitting the key entirely.
    -- jsonb_build_object with an unset variable produces exactly that shape.
    -- The elsif chain is deliberate: the numeric cast is only reached after the type
    -- test has ALREADY passed, because SQL does not promise to short-circuit `or` and a
    -- single combined predicate can cast a JSON string and die with a raw cast error
    -- instead of the named rejection below.
    if not (v_exp ? v_key) then
      v_err := v_err || jsonb_build_object('code','expected_count_missing','entity',v_key);
    elsif jsonb_typeof(v_exp -> v_key) <> 'number' then
      v_err := v_err || jsonb_build_object('code','expected_count_not_a_number','entity',v_key,
                                           'json_type', jsonb_typeof(v_exp -> v_key));
    elsif (v_exp ->> v_key)::numeric < 0
       or (v_exp ->> v_key)::numeric <> trunc((v_exp ->> v_key)::numeric) then
      -- A fractional or negative expectation is a broken loader, not a count. Named
      -- here rather than left to blow up on the ::bigint cast below.
      v_err := v_err || jsonb_build_object('code','expected_count_not_a_nonnegative_integer',
                                           'entity',v_key,'expected', v_exp -> v_key);
    elsif (v_exp ->> v_key)::numeric > 9223372036854775807::numeric then
      -- Larger than bigint. The raw cast would raise `bigint out of range` and wedge the
      -- capture in 'loading' with no recorded reason; this records one instead.
      v_err := v_err || jsonb_build_object('code','expected_count_out_of_range',
                                           'entity',v_key,'expected', v_exp -> v_key);
    else
      v_want := (v_exp ->> v_key)::bigint;
      if v_n <> v_want then
        v_err := v_err || jsonb_build_object('code','count_mismatch','entity',v_key,
                                             'expected',v_want,'observed',v_n);
      end if;
    end if;
  end loop;

  -- ---- B. Scope paging must be complete. Belt and braces over the table CHECKs.
  select count(*) into v_n from plm.nbcu_scope
   where capture_id = p_capture_id and (terminal is not true or cardinality(missing_offsets) <> 0);
  if v_n <> 0 then
    v_err := v_err || jsonb_build_object('code','nonterminal_or_gapped_scope','count',v_n);
  end if;

  -- ---- C. Capture-level invariants that are scope rules, not counts.
  if v_cap.media_downloaded <> 0 then
    v_err := v_err || jsonb_build_object('code','media_downloaded_nonzero',
                                         'observed', v_cap.media_downloaded);
  end if;
  -- Both scalars below carried the SAME defect as block A: `?` said "supplied" for a
  -- JSON null, the comparison then evaluated to UNKNOWN and the invariant was skipped;
  -- and a JSON string or float reached a raw ::integer cast. Both keys remain OPTIONAL
  -- -- their absence is not an error, exactly as before -- but a present value must be
  -- a non-negative integer NUMBER, tested BEFORE anything casts it.
  if (v_exp ? 'excluded_unlicensed_assets') then
    if jsonb_typeof(v_exp -> 'excluded_unlicensed_assets') <> 'number' then
      v_err := v_err || jsonb_build_object('code','expected_count_not_a_number',
                 'entity','excluded_unlicensed_assets',
                 'json_type', jsonb_typeof(v_exp -> 'excluded_unlicensed_assets'));
    elsif (v_exp ->> 'excluded_unlicensed_assets')::numeric < 0
       or (v_exp ->> 'excluded_unlicensed_assets')::numeric
          <> trunc((v_exp ->> 'excluded_unlicensed_assets')::numeric)
       or (v_exp ->> 'excluded_unlicensed_assets')::numeric > 2147483647::numeric then
      v_err := v_err || jsonb_build_object('code','expected_count_not_a_nonnegative_integer',
                 'entity','excluded_unlicensed_assets',
                 'expected', v_exp -> 'excluded_unlicensed_assets');
    elsif v_cap.excluded_unlicensed_assets
          <> (v_exp ->> 'excluded_unlicensed_assets')::integer then
      v_err := v_err || jsonb_build_object('code','excluded_unlicensed_mismatch',
                 'expected',(v_exp ->> 'excluded_unlicensed_assets')::integer,
                 'observed', v_cap.excluded_unlicensed_assets);
    end if;
  end if;
  if (v_exp ? 'failures') then
    if jsonb_typeof(v_exp -> 'failures') <> 'number' then
      v_err := v_err || jsonb_build_object('code','expected_count_not_a_number',
                 'entity','failures',
                 'json_type', jsonb_typeof(v_exp -> 'failures'));
    elsif (v_exp ->> 'failures')::numeric <> 0 then
      -- Any non-zero -- including a fraction or a negative, which are themselves broken
      -- loader output -- is a refusal. Compared as numeric so nothing casts to integer
      -- before the type test has passed.
      v_err := v_err || jsonb_build_object('code','expected_failures_nonzero',
                 'expected', v_exp -> 'failures');
    end if;
  end if;

  -- ---- D. Every asset must carry at least one metadata-value row. An asset that landed
  -- with no metadata means the detail expansion silently produced nothing for it.
  select count(*) into v_n
    from plm.nbcu_asset a
   where a.capture_id = p_capture_id
     and not exists (select 1 from plm.nbcu_asset_metadata_value m
                      where m.capture_id = a.capture_id
                        and m.asset_source_key = a.asset_source_key);
  if v_n <> 0 then
    v_err := v_err || jsonb_build_object('code','asset_without_metadata_value','count',v_n);
  end if;
  select count(*) into v_n from plm.nbcu_asset_metadata_value where capture_id = p_capture_id;
  v_obs := v_obs || jsonb_build_object('asset_metadata_values', v_n);

  select count(*) into v_n from plm.nbcu_asset_scope where capture_id = p_capture_id;
  v_obs := v_obs || jsonb_build_object('asset_scopes', v_n);
  select count(*) into v_n from plm.nbcu_right where capture_id = p_capture_id;
  v_obs := v_obs || jsonb_build_object('rights', v_n);

  -- ---- E. Relationship endpoints. The composite FKs already make a cross-capture edge
  -- impossible, so this is an assertion that they are still in force, not a substitute
  -- for them. It is cheap and it fails loudly if a future migration weakens a constraint.
  select count(*) into v_n
    from plm.nbcu_asset_property l
   where l.capture_id = p_capture_id
     and (not exists (select 1 from plm.nbcu_asset a
                       where a.capture_id = l.capture_id and a.asset_source_key = l.asset_source_key)
       or not exists (select 1 from plm.nbcu_property p
                       where p.capture_id = l.capture_id and p.property_key = l.property_key));
  if v_n <> 0 then
    v_err := v_err || jsonb_build_object('code','orphan_asset_property_link','count',v_n);
  end if;

  -- ---- F. No relationship may cite a Property label that the snapshot never landed.
  -- This is the check that would have caught the unrelated search results if the
  -- upstream exclusion had ever failed.
  select count(*) into v_n
    from plm.nbcu_asset_property l
    left join plm.nbcu_property p
      on p.capture_id = l.capture_id and p.property_key = l.property_key
   where l.capture_id = p_capture_id
     and (p.property_label is null or p.property_label is distinct from l.property_label);
  if v_n <> 0 then
    v_err := v_err || jsonb_build_object('code','unknown_or_mismatched_property_label','count',v_n);
  end if;

  -- ---- F2. ADDED BY MIGRATION 20260811070000 (issue #757). EVERYTHING ELSE IN THIS
  -- FUNCTION IS BYTE-IDENTICAL TO 20260810070000 EXCEPT THE ONE v_pairs ENTRY ABOVE.
  -- The Asset-to-IP-Family twin of check F. The composite FK already proves the
  -- ip_family_key exists in THIS capture; what it cannot prove is that the label the
  -- loader resolved is the label that snapshot actually landed. A loader that resolved
  -- an NBCU Franchise label onto the wrong family row would satisfy every constraint and
  -- still silently misstate the source. The specification requires finalization to reject
  -- when an exact IP Family label cannot be resolved, so it is asserted, not assumed.
  select count(*) into v_n
    from plm.nbcu_asset_ip_family l
    left join plm.nbcu_ip_family f
      on f.capture_id = l.capture_id and f.ip_family_key = l.ip_family_key
   where l.capture_id = p_capture_id
     and (f.ip_family_label is null or f.ip_family_label is distinct from l.ip_family_label);
  if v_n <> 0 then
    v_err := v_err || jsonb_build_object('code','unknown_or_mismatched_ip_family_label','count',v_n);
  end if;

  -- ---- Verdict. There is no partial publish: either every check passed or the capture
  -- is rejected and the PREVIOUS complete capture stays current.
  --
  -- WHY THIS RETURNS INSTEAD OF RAISING, AND WHY THAT IS NOT A WEAKENING.
  -- Spec section 7 asks for BOTH "set status='rejected', record structured errors" AND
  -- "raise an exception". In PostgreSQL those two instructions destroy each other: the
  -- exception aborts the very transaction that wrote the rejection row, so the evidence
  -- is rolled back and the capture is left sitting in `loading` with no record of why it
  -- failed. That directly defeats the spec's own auditability goal. It is an impossibility
  -- in the spec, not a choice, and it is FLAGGED in the pull request.
  -- The safety property the spec actually wants is "never partially publish", and that is
  -- fully preserved: the capture is marked `rejected`, it is not `complete`, no
  -- current-capture reader will ever select it, and the previous complete capture stays
  -- current. The failure is loud in three ways at once -- a WARNING in the server log, a
  -- persisted `rejected` status, and a returned status of 'rejected' the loader must check.
  --
  if jsonb_array_length(v_err) > 0 then
    update plm.nbcu_capture
       set status = 'rejected', observed_counts = v_obs, error_summary = v_err,
           load_completed_at = null
     where id = p_capture_id;
    raise warning 'finalize_nbcu_capture: capture % REJECTED with % error(s)',
      p_capture_id, jsonb_array_length(v_err);
    return jsonb_build_object('capture_id', p_capture_id, 'status', 'rejected',
                              'observed_counts', v_obs, 'errors', v_err,
                              'already_complete', false);
  end if;

  update plm.nbcu_capture
     set status = 'complete', observed_counts = v_obs,
         error_summary = '[]'::jsonb, load_completed_at = now()
   where id = p_capture_id;

  return jsonb_build_object('capture_id', p_capture_id, 'status', 'complete',
                            'observed_counts', v_obs, 'already_complete', false);
end;
$$;

comment on function plm.finalize_nbcu_capture(uuid) is
  'The publication gate. In ONE transaction it counts every entity and edge table for the '
  'capture -- including asset_ip_family -- checks scope completeness, the media-zero and '
  'exclusion invariants, that every asset has metadata, and that no edge is orphaned or '
  'cites an unknown Property or IP Family label. All pass -> status complete. Any fail -> '
  'status rejected, structured errors PERSISTED, a server WARNING raised, and a jsonb '
  'whose status is ''rejected'' returned; the previous complete capture is left untouched. '
  'NEVER a partial publish. THE CALLER MUST CHECK THE RETURNED status -- it does not raise, '
  'because raising would roll back the very rejection record the spec asks it to keep. '
  'Since 20260819112451 (#1219) an expected count that is present but NOT a JSON number -- '
  'a JSON null, string, bool, object or array -- is a NAMED rejection '
  '(expected_count_not_a_number), never a skipped check: jsonb ? key is true for a null '
  'value, so the old code compared against SQL NULL and silently published unverified '
  'counts. A negative, fractional or out-of-bigint-range number is rejected by name too, '
  'instead of dying on a raw cast. The same applies to the optional excluded_unlicensed_'
  'assets and failures keys. The expected zero for asset-to-character, and an expected '
  'zero for asset-to-IP-family, are normal passes and not special cases. service_role only.';

-- `create or replace function` preserves the existing ACL, so these are no-ops on a
-- database that already has the function -- but this file must also be correct on a
-- database applying the history in order, and stating the intended privilege explicitly
-- is cheaper than depending on REPLACE's ACL-preservation rule.
revoke all on function plm.finalize_nbcu_capture(uuid) from public;
grant execute on function plm.finalize_nbcu_capture(uuid) to service_role;


-- =====================================================================================
-- ASSERT THE OUTCOME, IN THE MIGRATION.
--
-- This repository has shipped a migration that recorded a clean ledger row while its
-- object did nothing, so the migration proves its own effect rather than assuming it.
-- Everything below is synthetic (ZZTEST-/.invalid), lives only inside this transaction's
-- own rows, and is deleted before the migration ends.
-- =====================================================================================
do $$
declare
  v_cap uuid;
  v_res jsonb;
  v_exp jsonb := jsonb_build_object(
    'assets',0,'properties',0,'characters',0,'style_guides',0,'scopes',0,
    'ip_family_property',0,'property_character',0,'asset_property',0,
    'asset_character',0,'asset_style_guide',0,'style_guide_property',0,
    'asset_ip_family',0,'excluded_unlicensed_assets',0,'failures',0);
begin
  -- The source text must still carry the guard. A future `create or replace` that drops
  -- it would otherwise pass every behavioural check below only because the counts are 0.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='plm' and p.proname='finalize_nbcu_capture'
         and p.prosrc like '%expected_count_not_a_number%') <> 1 then
    raise exception
      'MIGRATION 20260819112451 FAILED: plm.finalize_nbcu_capture does not carry the '
      'expected_count_not_a_number guard after replacement.';
  end if;

  insert into plm.nbcu_capture (
    capture_key, source_repository, source_commit_sha, source_manifest_sha256,
    portal_base_url, source_captured_at, status, expected_counts, raw_summary, created_by
  ) values (
    'nbcu:ZZTEST-1219:'||repeat('c',40), 'u2giants/ZZTEST', repeat('c',40), repeat('d',64),
    'https://portal.example.invalid/', now(), 'loading', v_exp, '{}'::jsonb,
    'migration-20260819112451'
  ) returning id into v_cap;

  -- 1. An all-zero snapshot with zero rows is publishable. Baseline: without this the
  --    two rejection assertions below could pass for the wrong reason.
  v_res := plm.finalize_nbcu_capture(v_cap);
  if (v_res ->> 'status') <> 'complete' then
    raise exception 'MIGRATION 20260819112451 FAILED: a correct zero snapshot returned %',
      v_res::text;
  end if;

  -- 2. THE DEFECT ITSELF. A JSON null expected count must be REJECTED BY NAME. Before
  --    this migration it published as 'complete'.
  update plm.nbcu_capture
     set status='loading', load_completed_at=null, expected_counts = v_exp || '{"assets":null}'::jsonb
   where id = v_cap;
  v_res := plm.finalize_nbcu_capture(v_cap);
  if (v_res ->> 'status') <> 'rejected'
     or not (v_res -> 'errors') @> '[{"code":"expected_count_not_a_number","entity":"assets"}]'::jsonb then
    raise exception
      'MIGRATION 20260819112451 FAILED: a JSON-null expected count was not rejected by name: %',
      v_res::text;
  end if;

  -- 3. A JSON string must be a NAMED rejection, not a raw cast error. A raw cast would
  --    abort this DO block and fail the migration, which is itself the proof.
  update plm.nbcu_capture
     set status='loading', load_completed_at=null, expected_counts = v_exp || '{"assets":"12"}'::jsonb
   where id = v_cap;
  v_res := plm.finalize_nbcu_capture(v_cap);
  if (v_res ->> 'status') <> 'rejected'
     or not (v_res -> 'errors') @> '[{"code":"expected_count_not_a_number","entity":"assets"}]'::jsonb then
    raise exception
      'MIGRATION 20260819112451 FAILED: a string expected count was not rejected by name: %',
      v_res::text;
  end if;

  -- 4. A float must be a NAMED rejection, not a raw cast error.
  update plm.nbcu_capture
     set status='loading', load_completed_at=null, expected_counts = v_exp || '{"assets":0.5}'::jsonb
   where id = v_cap;
  v_res := plm.finalize_nbcu_capture(v_cap);
  if (v_res ->> 'status') <> 'rejected'
     or not (v_res -> 'errors')
            @> '[{"code":"expected_count_not_a_nonnegative_integer","entity":"assets"}]'::jsonb then
    raise exception
      'MIGRATION 20260819112451 FAILED: a fractional expected count was not rejected by name: %',
      v_res::text;
  end if;

  -- 5. A null in the OPTIONAL failures key must not skip the failures invariant either.
  update plm.nbcu_capture
     set status='loading', load_completed_at=null, expected_counts = v_exp || '{"failures":null}'::jsonb
   where id = v_cap;
  v_res := plm.finalize_nbcu_capture(v_cap);
  if (v_res ->> 'status') <> 'rejected'
     or not (v_res -> 'errors')
            @> '[{"code":"expected_count_not_a_number","entity":"failures"}]'::jsonb then
    raise exception
      'MIGRATION 20260819112451 FAILED: a JSON-null failures key was not rejected by name: %',
      v_res::text;
  end if;

  delete from plm.nbcu_capture where id = v_cap;
  raise notice 'MIGRATION 20260819112451: NBCU count-gate hardening PROVED (5 assertions).';
end;
$$;
