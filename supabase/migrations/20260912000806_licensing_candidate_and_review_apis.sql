-- Issue #2357 (#1090 successor): browser-safe read contracts for licensing entity
-- candidates, relationship candidates, and the audited resolution queue.
--
-- This migration creates THREE api views and nothing else. No review decisions and no
-- curated rows are authorized by it, and it writes no data.
--
-- Security model, and why it is shaped this way.
--
-- All three views are `security_invoker = true`, so every read runs with the caller's own
-- rights and the existing RLS policies on the base tables remain the gate. Proven live
-- against production before authoring (pg_class.relacl / has_table_privilege, not
-- information_schema, which is permission-filtered in this project and under-reports):
--
--   plm.source_resolution                 rowsecurity=t  authenticated=SELECT  anon=none  1 policy
--   plm.licensing_relationship_resolution rowsecurity=t  authenticated=SELECT  anon=none  1 policy
--   plm.licensing_source_scope            rowsecurity=t  authenticated=SELECT  anon=none  1 policy
--   plm.opa_capture                       rowsecurity=t  authenticated=NONE    anon=none  0 policies
--   plm.opa_property_character_capture    rowsecurity=t  authenticated=NONE    anon=none  0 policies
--
-- The two OPA capture tables grant SELECT to service_role ONLY and carry no policy, so a
-- browser role cannot read them at all. That asymmetry drives the one real design decision
-- here: joining those tables into an invoker view would NOT deny a browser read, it would
-- silently return zero corroboration rows and read exactly like "no evidence exists". A
-- silent zero that is indistinguishable from a real answer is worse than no column, so the
-- OPA evidence is exposed as an explicitly-labelled aggregate whose visibility the caller
-- can test (`opa_evidence_readable`), never as licensed capture rows. A caller without
-- rights sees opa_evidence_readable = false and NULL counts -- not 0, which would be a
-- false statement about the source data.
--
-- No licensed row leakage: no property_name, character_name, licensed_property_id,
-- brand_property_id, option_source_id, source hash, capture path or authentication evidence
-- appears in any of these views. Only resolution decisions, ambiguity state, scope authority
-- and bounded counts are exposed -- the same posture api.source_resolution already takes.
--
-- derived-from: none

begin;

set local lock_timeout = '2s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------------------
-- 1. Entity candidates -- one row per source entity decision, with the scope
--    authority that governs it and bounded OPA corroboration evidence.
-- ---------------------------------------------------------------------------

create view api.licensing_entity_candidates
with (security_invoker = true) as
select
  sr.source_system,
  sr.entity_kind,
  sr.source_id,
  sr.resolution_status,
  sr.resolution_reason,
  -- Which canonical target the decision points at, if any. Exactly one is non-null for a
  -- matched row (enforced by source_resolution_matched_target_chk); all are null otherwise.
  sr.core_property_id,
  sr.core_character_id,
  sr.core_style_guide_id,
  sr.core_licensor_id,
  sr.core_franchise_id,
  sr.dam_asset_id,
  (sr.resolution_status in ('unresolved', 'ambiguous')) as needs_decision,
  (sr.resolution_status = 'ambiguous')                  as is_ambiguous,
  -- Scope authority: is this source system actually permitted to assert this entity kind,
  -- and under what purpose? Aggregated so one candidate stays one row.
  scope.authority_count,
  scope.canonical_identity_permitted,
  scope.source_purposes,
  -- OPA corroboration. Readable only by a caller with rights on the capture tables; a
  -- browser role sees false/NULL rather than a misleading zero. See the header note.
  opa.evidence_readable as opa_evidence_readable,
  opa.observation_count as opa_observation_count,
  sr.resolved_at,
  sr.resolved_by,
  sr.created_at,
  sr.updated_at
from plm.source_resolution sr
left join lateral (
  select
    count(*)                                                           as authority_count,
    bool_or(lss.source_purpose = 'canonical_identity')                 as canonical_identity_permitted,
    array_agg(distinct lss.source_purpose)                             as source_purposes
  from plm.licensing_source_scope lss
  where lss.source_system  = sr.source_system
    and lss.scope_axis     = 'entity'
    and lss.permitted_kind = sr.entity_kind
) scope on true
left join lateral (
  -- has_table_privilege is the authoritative readability test here; information_schema is
  -- permission-filtered in this project and cannot be trusted for it.
  select
    has_table_privilege('plm.opa_property_character_capture', 'SELECT') as evidence_readable,
    case when has_table_privilege('plm.opa_property_character_capture', 'SELECT')
      then (
        select count(*)
        from plm.opa_property_character_capture occ
        join plm.opa_capture oc on oc.id = occ.capture_id and oc.status = 'complete'
        where sr.source_system = 'disney_opa'
          and sr.entity_kind   = 'property'
          and occ.licensed_property_id::text = sr.source_id
      )
      else null
    end as observation_count
) opa on true;

comment on view api.licensing_entity_candidates is
  'Browser-safe entity resolution candidates: one row per plm.source_resolution decision with '
  'its ambiguity state, the canonical target it points at, and the licensing scope authority '
  'that governs the source system for that entity kind. Invoker security preserves the existing '
  'source_resolution and licensing_source_scope read policies. OPA corroboration is a bounded '
  'count guarded by opa_evidence_readable: a caller without rights on the capture tables sees '
  'false and NULL, never a zero that would misstate the source data. No licensed row value, '
  'property or character name, capture identity, source hash or authentication evidence appears here.';

revoke all on api.licensing_entity_candidates from public, anon;
grant select on api.licensing_entity_candidates to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Relationship candidates -- one row per relationship decision, with its evidence
--    strength and the scope authority permitting that relationship kind.
-- ---------------------------------------------------------------------------

create view api.licensing_relationship_candidates
with (security_invoker = true) as
select
  lrr.licensor_id,
  lrr.source_system,
  lrr.relationship_kind,
  lrr.source_left_id,
  lrr.source_right_id,
  lrr.resolution_status,
  lrr.resolution_reason,
  lrr.evidence_kind,
  lrr.is_direct_source_relationship,
  lrr.source_evidence,
  lrr.core_property_id,
  lrr.core_character_id,
  lrr.core_style_guide_id,
  lrr.core_franchise_id,
  lrr.dam_asset_id,
  (lrr.resolution_status in ('unresolved', 'ambiguous')) as needs_decision,
  (lrr.resolution_status = 'ambiguous')                  as is_ambiguous,
  -- A relationship can only reach 'matched' on direct_source_assertion evidence
  -- (licensing_relationship_resolution's own check constraint). Surfacing that as a column
  -- tells a reviewer why an otherwise-complete row is not eligible to be matched.
  (lrr.evidence_kind = 'direct_source_assertion')        as eligible_for_match,
  scope.authority_count,
  scope.relationship_evidence_permitted,
  scope.source_purposes,
  lrr.resolved_at,
  lrr.resolved_by,
  lrr.created_at,
  lrr.updated_at
from plm.licensing_relationship_resolution lrr
left join lateral (
  select
    count(*)                                              as authority_count,
    bool_or(lss.source_purpose = 'relationship_evidence') as relationship_evidence_permitted,
    array_agg(distinct lss.source_purpose)                as source_purposes
  from plm.licensing_source_scope lss
  where lss.licensor_id    = lrr.licensor_id
    and lss.source_system  = lrr.source_system
    and lss.scope_axis     = 'relationship'
    and lss.permitted_kind = lrr.relationship_kind
) scope on true;

comment on view api.licensing_relationship_candidates is
  'Browser-safe relationship resolution candidates: one row per plm.licensing_relationship_resolution '
  'decision with its evidence kind, whether it is eligible to be matched (direct source assertion only), '
  'and the licensing scope authority permitting that relationship kind for the licensor and source system. '
  'Invoker security preserves the existing read policies. Source-side identifiers are the opaque source '
  'ids already carried by the resolution table; no licensed name, capture row or source hash appears here.';

revoke all on api.licensing_relationship_candidates from public, anon;
grant select on api.licensing_relationship_candidates to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Resolution queue -- the audited backlog across both axes, one row per
--    (axis, source_system, kind, status) bucket. Counts only; no row content.
-- ---------------------------------------------------------------------------

create view api.licensing_resolution_queue
with (security_invoker = true) as
with entity_queue as (
  select
    'entity'::text        as scope_axis,
    sr.source_system,
    sr.entity_kind        as item_kind,
    sr.resolution_status,
    count(*)              as item_count,
    min(sr.created_at)    as oldest_created_at,
    max(sr.updated_at)    as latest_updated_at
  from plm.source_resolution sr
  where sr.resolution_status in ('unresolved', 'ambiguous', 'deferred')
  group by 1, 2, 3, 4
),
relationship_queue as (
  select
    'relationship'::text   as scope_axis,
    lrr.source_system,
    lrr.relationship_kind  as item_kind,
    lrr.resolution_status,
    count(*)               as item_count,
    min(lrr.created_at)    as oldest_created_at,
    max(lrr.updated_at)    as latest_updated_at
  from plm.licensing_relationship_resolution lrr
  where lrr.resolution_status in ('unresolved', 'ambiguous', 'deferred')
  group by 1, 2, 3, 4
)
select
  q.scope_axis,
  q.source_system,
  q.item_kind,
  q.resolution_status,
  q.item_count,
  (q.resolution_status = 'ambiguous') as is_ambiguous,
  q.oldest_created_at,
  q.latest_updated_at
from (
  select * from entity_queue
  union all
  select * from relationship_queue
) q;

comment on view api.licensing_resolution_queue is
  'Audited licensing resolution backlog: counts of open decisions (unresolved, ambiguous, deferred) '
  'bucketed by axis, source system, item kind and status, with the age of the oldest open item. '
  'Aggregate only -- it exposes no source identifier and no row content, so it stays readable '
  'without widening access to any licensed value. Invoker security preserves the existing read '
  'policies, so the counts a caller sees are the counts that caller is entitled to see.';

revoke all on api.licensing_resolution_queue from public, anon;
grant select on api.licensing_resolution_queue to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Post-create verification. Positive AND negative controls, from the authoritative
--    catalog (pg_class.relacl / has_table_privilege), never information_schema.
--    Each control is written so it CAN fail -- an assertion nothing can falsify is
--    furniture, not a check.
-- ---------------------------------------------------------------------------

do $verify$
declare
  v_view text;
  v_exposed text;
begin
  foreach v_view in array array[
    'api.licensing_entity_candidates',
    'api.licensing_relationship_candidates',
    'api.licensing_resolution_queue'
  ] loop
    -- Exists, and is a view.
    if to_regclass(v_view) is null then
      raise exception '#2357 VERIFY FAILED: % was not created', v_view;
    end if;

    -- security_invoker must be ON. This is the control that keeps RLS in force; without it
    -- the views would read with the definer's rights and bypass every base-table policy.
    if not exists (
      select 1 from pg_class c
      where c.oid = to_regclass(v_view)
        and 'security_invoker=true' = any(coalesce(c.reloptions, '{}'))
    ) then
      raise exception '#2357 VERIFY FAILED: % is not security_invoker', v_view;
    end if;

    -- POSITIVE control: the browser role must be able to read it.
    if not has_table_privilege('authenticated', v_view, 'SELECT') then
      raise exception '#2357 VERIFY FAILED: browser role authenticated cannot read %', v_view;
    end if;

    -- NEGATIVE control: the unauthenticated role must NOT. If this never fires, the grant
    -- above is not doing what it claims; it fires today if `revoke ... from anon` is dropped.
    if has_table_privilege('anon', v_view, 'SELECT') then
      raise exception '#2357 VERIFY FAILED: unauthorized role anon can read %', v_view;
    end if;

    -- PUBLIC must not hold a residual grant either.
    if has_table_privilege('public', v_view, 'SELECT') then
      raise exception '#2357 VERIFY FAILED: PUBLIC can read %', v_view;
    end if;
  end loop;

  -- Positive control on the controls themselves: prove the privilege probe can return
  -- both answers, so a green run above means "checked", not "always true".
  if has_table_privilege('anon', 'plm.opa_property_character_capture', 'SELECT') then
    raise exception '#2357 VERIFY FAILED: anon unexpectedly holds SELECT on the OPA capture table';
  end if;
  if not has_table_privilege('authenticated', 'plm.source_resolution', 'SELECT') then
    raise exception '#2357 VERIFY FAILED: expected authenticated SELECT on plm.source_resolution is absent';
  end if;

  -- No licensed or capture-identity column may appear in any of the three views. Checked
  -- against the catalog rather than by reading the SQL above.
  select string_agg(format('%s.%s', c.relname, a.attname), ', ')
    into v_exposed
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  where n.nspname = 'api'
    and c.relname in ('licensing_entity_candidates','licensing_relationship_candidates','licensing_resolution_queue')
    and a.attname in (
      'property_name','character_name','licensed_property_id','brand_property_id',
      'option_source_id','source_row_sha256','chunk_sha256','source_manifest_sha256',
      'source_commit_sha','capture_key','created_by'
    );
  if v_exposed is not null then
    raise exception '#2357 VERIFY FAILED: licensed or capture-identity column exposed: %', v_exposed;
  end if;
end
$verify$;

commit;
