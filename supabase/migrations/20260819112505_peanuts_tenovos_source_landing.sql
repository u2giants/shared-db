-- =====================================================================================
-- Peanuts (Tenovos) -- source landing schema (release 1).
--
-- Migration: 20260819112505_peanuts_tenovos_source_landing.sql
-- Issue:     u2giants/shared-db #1217 (schema contract)
-- Claim:     u2giants/shared-db #1231, reserved version 20260819112505
--
-- SCHEMA ONLY. THIS MIGRATION LOADS NO DATA AND CONTAINS NO PEANUTS VALUES.
-- -------------------------------------------------------------------------------------
-- u2giants/shared-db is a PUBLIC repository. The Peanuts extract is licensed source data
-- held in the PRIVATE repo u2giants/licensor-source-data under `peanuts/`. No Peanuts art
-- program, style guide, character, initiative, holiday, animation title, asset type,
-- file name, title, keyword, era or raw payload value may ever appear in this file, in a
-- contract test, in CI output, or in a pull request or issue on this repository.
--   SCHEMA IN GIT. DATA OUT OF GIT.
-- Rows arrive at runtime from the private loader through the INSERT grants below. The
-- contract tests use INVENTED fixture values only.
--
-- WHAT THIS IS
--   A lossless, append-only, capture-scoped landing of one Peanuts Asset Library
--   (Tenovos DAM v3.5.0, AWS AppSync GraphQL) capture. Every source table is keyed by
--   `capture_id`, so a refresh ADDS a snapshot and never overwrites or deletes an earlier
--   one. Retry safety is `on conflict do nothing`, which needs no UPDATE privilege.
--
-- WHAT THIS DELIBERATELY IS NOT
--   It creates, renames, updates, merges and deletes NOTHING in core.* or dam.*. It
--   resolves NOTHING: this release ships no reconciliation columns at all, so there is no
--   half-built resolution surface to misread. Nothing here is canonical.
--
-- FOUR PORTAL FACTS THIS SHAPE EXISTS TO SURVIVE
--
--   1. THERE IS NO HIERARCHY ABOVE THE ASSET. Tenovos stores one flat metadata document
--      per asset plus a set of controlled vocabularies. There is no style-guide entity,
--      no character roster, no property tree and no folder path. Every axis below is a
--      vocabulary value stamped on the asset, so the vocabulary tables are peers of the
--      asset table, not parents of it.
--
--   2. THE INTERNAL FIELD NAME AND THE PORTAL LABEL DISAGREE ON THE TWO MOST IMPORTANT
--      FIELDS. The field internally named `property` is labelled "Art Program" in the UI,
--      and the field internally named `program` is labelled "Initiative". Neither is a
--      property in our master-data sense. EVERY TABLE AND COLUMN HERE IS NAMED AFTER THE
--      LABEL, and both names are stored on every vocabulary row (source_field_name +
--      source_field_label) and again in plm.peanuts_metadata_field. This is not
--      bookkeeping: a search filter built from the internal name is SILENTLY IGNORED by
--      the API and returns the unfiltered total, so a mis-named filter yields a capture
--      that looks complete and is not.
--
--   3. VOCABULARY VALUES EXIST THAT NO ASSET USES, AND THEY ARE LICENSED CONTENT WE ARE
--      ENTITLED TO. Deriving the master lists from `distinct(value)` over assets -- the
--      obvious loader shortcut -- discards hundreds of style guides and a double-digit
--      number of characters. The vocabularies are pulled from their own API
--      (getControlledVocabularyByIds) and land in their own tables. `asset_count` is
--      therefore `>= 0`, NOT `> 0`: a zero-usage value is exactly the content the naive
--      loader loses, and it must be storable. plm.peanuts_capture carries
--      `vocabularies_loaded_from_source` as the guard against that shortcut.
--
--   4. THE SEARCH API HAS A HARD 10,000-ROW DEEP-PAGING WALL. `from + size > 10000`
--      returns zero hits with HTTP 200 -- silent truncation. The capture converges a
--      little short of the portal's own reported total, and that shortfall is REAL.
--      `assets_unreachable` is the arithmetic proof it was accounted for rather than
--      hidden: a 'complete' capture must satisfy
--      assets_captured + assets_unreachable = portal_reported_asset_total, so a capture
--      claiming zero unreachable assets while sitting below the portal total cannot
--      publish.
--
-- DECLARED FACT vs RECONSTRUCTED, AND THE ONE LINK THAT IS REFUSED OUTRIGHT
--   Declared by the portal and stored as fact: every vocabulary value; every value
--   stamped on an asset; and plm.peanuts_asset_relationship, the asset parent/child graph
--   returned by getRelationshipByObjectId with an explicit link type, which is preserved
--   verbatim in `link_type` rather than assumed.
--   Reconstructed by us and pinned to relationship_truth = 'derived' by a CHECK that
--   permits no other value: plm.peanuts_style_guide_character and
--   plm.peanuts_style_guide_art_program. The style-guide field is SINGLE-select, which is
--   what makes those derivations unambiguous; guide-to-art-program is many-to-many
--   because guides already appear under more than one art program in the source.
--   REFUSED: there is NO art-program-to-character table in this schema, derived or
--   otherwise, and none may be added. The art-program field is multi-select, so an asset
--   carrying two art programs and four characters states nothing about which character
--   belongs to which program. Pairing two independent arrays on one asset is exactly the
--   Disney DCP Vault fabrication this project has already paid for once.
--
-- IMMUTABILITY IS DELIVERED BY PRIVILEGE SEPARATION, NOT BY TRIGGERS
--   Same mechanism, and the same reason, as the NBCU, WildBrain and Sega landings. This
--   database has been burned by a BEFORE trigger that read a GENERATED ... STORED column,
--   which Postgres populates AFTER before-triggers fire: the guard never fired and
--   nothing ever raised. Privilege separation fails closed and is INSPECTABLE in
--   information_schema.role_table_grants, so a contract test can assert the guarantee
--   itself rather than assert that some guard code exists.
--
--   THE TRAP THAT MADE 20260810080000 NECESSARY IS HANDLED IN THIS FILE. The schema `plm`
--   carries `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO service_role`, so every
--   table below is BORN holding UPDATE, DELETE and TRUNCATE for service_role and a bare
--   `grant select, insert` is a no-op. The explicit REVOKE block near the end is what
--   actually makes these rows immutable, and the assertion block after it fails the
--   migration if the revokes did not take.
--
--   Every privilege statement below is written out IN FULL, one per table, statically and
--   schema-qualified. No `DO` loop, no `execute format(...)`. Dynamic privilege SQL hides
--   the privilege model from the cross-PR object guard and from every human reader, and
--   was rejected on the Sega landing (#1196) for exactly that reason.
--
-- ⚠️ OPEN DEPENDENCY -- READ BEFORE LOADING ANYTHING
--   Per the schema contract, service_role holds SELECT ONLY on plm.peanuts_capture: the
--   capture root is meant to be written by security-definer functions
--   (plm.begin_peanuts_capture / plm.finalize_peanuts_capture) exactly as the NBCU,
--   WildBrain and Sega landings do. THOSE FUNCTIONS ARE NOT IN THIS MIGRATION. The
--   object claim for issue #1217 (claim #1231) covers these 19 TABLES and nothing else,
--   and inventing an unclaimed function would defeat the object guard that keeps parallel
--   migration authors from silently overwriting one another.
--   CONSEQUENCE, STATED LOUDLY RATHER THAN PAPERED OVER: until those two functions ship
--   under their own claim, NO capture row can be created, so no snapshot row can be
--   inserted either (every snapshot table has a foreign key to plm.peanuts_capture). This
--   schema is therefore INERT-BY-DESIGN on arrival. It is not a silent failure -- an
--   attempted load fails immediately and visibly with `permission denied for table
--   peanuts_capture`. Do not "fix" it by granting INSERT on plm.peanuts_capture to
--   service_role: that would let a loader mint a capture that skipped every validation
--   the begin/finalize pair exists to perform.
--   The completion rule is ALSO enforced here as a table CHECK
--   (peanuts_capture_complete_requirements_chk), so it holds even against a writer that
--   reaches this table some other way, and does not depend on the functions being correct.
--
-- Depends on (exact 14-digit versions):
--   20260621150714  foundation  -- schema plm
--   20260621150815  app_core    -- app.has_role / has_any_role / has_app_access
-- =====================================================================================


-- =====================================================================================
-- 1. plm.peanuts_capture -- one row per attempted load. The root of every snapshot.
--
-- capture_key is the loader's idempotency key.
--
-- source_commit_sha vs read_commit_sha are TWO DIFFERENT FACTS and must not be collapsed.
-- source_commit_sha identifies the DATA -- the private-repo commit the extract was merged
-- at. read_commit_sha is the commit the loader actually had checked out when it read the
-- bytes, which can be a LATER commit that changed only documentation.
-- =====================================================================================
create table plm.peanuts_capture (
  id                             uuid        primary key default gen_random_uuid(),
  capture_key                    text        not null unique,
  source_repository              text        not null,
  source_commit_sha              text        not null,
  read_commit_sha                text            null,
  source_manifest_sha256         text        not null,
  portal_base_url                text        not null,
  api_endpoint                   text        not null,
  source_customer_id             text        not null,
  source_captured_at             timestamptz not null,
  load_started_at                timestamptz not null default now(),
  load_completed_at              timestamptz     null,
  status                         text        not null default 'loading',
  expected_counts                jsonb       not null,
  observed_counts                jsonb       not null default '{}'::jsonb,
  media_downloaded               integer     not null default 0,
  portal_reported_asset_total    integer     not null,
  assets_captured                integer     not null,
  assets_unreachable             integer     not null,
  deep_paging_partitioned        boolean     not null default false,
  vocabularies_loaded_from_source boolean    not null default false,
  relationship_graph_walked      boolean     not null default false,
  error_summary                  jsonb       not null default '[]'::jsonb,
  raw_summary                    jsonb       not null,
  created_by                     text        not null,

  constraint peanuts_capture_status_chk
    check (status in ('loading','complete','rejected','abandoned')),
  constraint peanuts_capture_key_nonblank_chk         check (btrim(capture_key) <> ''),
  constraint peanuts_capture_repository_nonblank_chk  check (btrim(source_repository) <> ''),
  constraint peanuts_capture_portal_nonblank_chk      check (btrim(portal_base_url) <> ''),
  constraint peanuts_capture_api_endpoint_nonblank_chk check (btrim(api_endpoint) <> ''),
  constraint peanuts_capture_customer_id_nonblank_chk check (btrim(source_customer_id) <> ''),
  constraint peanuts_capture_created_by_nonblank_chk  check (btrim(created_by) <> ''),
  constraint peanuts_capture_commit_sha_chk
    check (source_commit_sha ~ '^[0-9a-f]{40}$'),
  constraint peanuts_capture_read_commit_sha_chk
    check (read_commit_sha is null or read_commit_sha ~ '^[0-9a-f]{40}$'),
  constraint peanuts_capture_manifest_sha256_chk
    check (source_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  -- Scope guard, not a style preference: this project may never download Peanuts media.
  constraint peanuts_capture_media_zero_chk check (media_downloaded = 0),
  constraint peanuts_capture_portal_total_nonneg_chk
    check (portal_reported_asset_total >= 0),
  constraint peanuts_capture_assets_captured_nonneg_chk check (assets_captured >= 0),
  constraint peanuts_capture_assets_unreachable_nonneg_chk check (assets_unreachable >= 0),
  constraint peanuts_capture_complete_time_chk
    check ((status = 'complete') = (load_completed_at is not null)),
  -- The completion rule from the schema contract, enforced by the TABLE and not only by a
  -- function, so a writer that reaches this table another way still cannot mint a
  -- 'complete' capture that was un-partitioned, vocabulary-shortcut, media-bearing,
  -- error-carrying, or arithmetically short of the portal's own total.
  constraint peanuts_capture_complete_requirements_chk
    check (
      status <> 'complete'
      or (
        load_completed_at is not null
        and deep_paging_partitioned = true
        and vocabularies_loaded_from_source = true
        and media_downloaded = 0
        and jsonb_array_length(error_summary) = 0
        and assets_captured + assets_unreachable = portal_reported_asset_total
      )
    ),
  constraint peanuts_capture_expected_counts_obj_chk
    check (jsonb_typeof(expected_counts) = 'object'),
  constraint peanuts_capture_observed_counts_obj_chk
    check (jsonb_typeof(observed_counts) = 'object'),
  constraint peanuts_capture_error_summary_arr_chk
    check (jsonb_typeof(error_summary) = 'array'),
  constraint peanuts_capture_raw_summary_obj_chk
    check (jsonb_typeof(raw_summary) = 'object')
);

comment on table plm.peanuts_capture is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. One row per attempted '
  'Peanuts (Tenovos) load. Append-only snapshot root: a refresh adds a new capture and '
  'NEVER edits or deletes an earlier one. service_role holds SELECT only -- writes are '
  'reserved for the begin/finalize security-definer pair, which ships under its own '
  'object claim and is NOT in this migration.';
comment on column plm.peanuts_capture.source_commit_sha is
  'The private-repo commit that identifies the DATA. capture_key is built from this.';
comment on column plm.peanuts_capture.read_commit_sha is
  'The private-repo commit the loader actually had checked out. May be LATER than '
  'source_commit_sha when only documentation changed. A separate fact; do not collapse.';
comment on column plm.peanuts_capture.status is
  'loading -> complete | rejected. A rejected capture stays visible as immutable evidence '
  'and the previous complete capture remains current. ''abandoned'' is permitted by the '
  'CHECK but nothing in this release sets it -- flagged, not invented.';
comment on column plm.peanuts_capture.media_downloaded is
  'Hard zero. Constrained, not merely defaulted: storing Peanuts media bytes is out of scope.';
comment on column plm.peanuts_capture.portal_reported_asset_total is
  'The asset total the portal states for itself. The capture is expected to converge '
  'SHORT of this because of the 10,000-row deep-paging wall; the shortfall belongs in '
  'assets_unreachable, never rounded away.';
comment on column plm.peanuts_capture.assets_unreachable is
  'Not a fudge column: the arithmetic proof that the deep-paging wall was accounted for. '
  'assets_captured + assets_unreachable must equal portal_reported_asset_total before a '
  'capture may be ''complete'', so zero-unreachable-but-short cannot publish.';
comment on column plm.peanuts_capture.deep_paging_partitioned is
  'The crawl worked around the 10,000-row wall by sorting in both directions and then '
  'partitioning by vocabulary term. False means the crawl was silently truncatable.';
comment on column plm.peanuts_capture.vocabularies_loaded_from_source is
  'Set only once the loader has proven the vocabulary tables came from the vocabulary API '
  'and NOT from distinct() over assets. This is the guard against silently discarding the '
  'hundreds of vocabulary values that no asset uses.';
comment on column plm.peanuts_capture.relationship_graph_walked is
  'The asset parent/child graph is populated by a per-asset call and is the slowest part '
  'of the capture. False makes a partial walk visible rather than silently short.';


-- =====================================================================================
-- 2-9. THE EIGHT CONTROLLED-VOCABULARY TABLES.
--
-- One table per axis. All eight share one shape and one identity rule.
--
-- IDENTITY IS `value_key`, A NORMALISED LABEL WE GENERATE. The vocabulary API does return
-- a `valueId` per value, and it is kept in `source_value_id` as evidence -- but it is a
-- vocabulary-ROW identifier, not a stable licensor number, nothing else in the portal
-- references it, and NOTHING MAY JOIN ON IT. It is deliberately nullable and carries no
-- unique constraint so that no future reader can mistake it for a key.
--
-- `asset_count` is `>= 0` and zero is legal and MEANINGFUL -- see fact 3 in the header.
-- =====================================================================================

-- 2. Art programme. Internal field name and UI label disagree here (see header fact 2):
--    this axis is stored under its LABEL. Multi-select on the asset.
create table plm.peanuts_art_program (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_art_program_pkey primary key (capture_id, value_key),
  constraint peanuts_art_program_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_art_program_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_art_program_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_art_program_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_art_program_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_art_program_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_art_program_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_art_program_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_art_program_usage_idx
  on plm.peanuts_art_program (capture_id, asset_count);

comment on table plm.peanuts_art_program is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Art Program '
  'controlled vocabulary, in full, straight from the vocabulary API. Named after the '
  'PORTAL LABEL: the underlying metadata field has a different internal name, and the '
  'mismatch is recorded on every row. This axis is an art-style/era bucket and is NOT a '
  'property in the core.property sense. Resolves nothing.';
comment on column plm.peanuts_art_program.source_value_id is
  'Vocabulary-row id, evidence only. NOT identity. Nothing may join on it.';
comment on column plm.peanuts_art_program.asset_count is
  'Usage, not existence: >= 0, and zero is a legitimate, meaningful row.';

-- 3. Style guide. SINGLE-select on the asset -- this is the fact that licenses the two
--    derived tables at the end of this file, so it is pinned by a CHECK rather than
--    merely stored. Has NO usable source identifier of its own.
create table plm.peanuts_style_guide (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_style_guide_pkey primary key (capture_id, value_key),
  constraint peanuts_style_guide_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_style_guide_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_style_guide_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_style_guide_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_style_guide_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_style_guide_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_style_guide_asset_count_nonneg_chk   check (asset_count >= 0),
  -- Load-bearing, not decorative. Both derived tables below are only unambiguous because
  -- an asset carries at most ONE style guide. If the portal ever turns this field
  -- multi-select, the load must fail here and loudly rather than quietly poison the
  -- derivations with pairings nobody asserted.
  constraint peanuts_style_guide_single_select_chk       check (is_multi_select = false),
  constraint peanuts_style_guide_raw_obj_chk             check (jsonb_typeof(raw) = 'object')
);
create index peanuts_style_guide_usage_idx
  on plm.peanuts_style_guide (capture_id, asset_count);

comment on table plm.peanuts_style_guide is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Style Guide '
  'controlled vocabulary, in full. Identity is the normalised label we generate, because '
  'the portal issues no stable style-guide number. MOST of these values are used by NO '
  'asset, which is precisely why the list is loaded from the vocabulary API instead of '
  'from distinct() over assets. Not merged with the style-guide DOCUMENT assets: those '
  'are rows in plm.peanuts_asset and are connected only through '
  'plm.peanuts_asset.style_guide_key and the declared parent/child graph.';
comment on column plm.peanuts_style_guide.is_multi_select is
  'Pinned false by CHECK. The single-select property of this field is what makes '
  'plm.peanuts_style_guide_character and plm.peanuts_style_guide_art_program derivable '
  'without inventing pairings.';

-- 4. Character. Multi-select on the asset.
create table plm.peanuts_character (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_character_pkey primary key (capture_id, value_key),
  constraint peanuts_character_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_character_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_character_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_character_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_character_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_character_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_character_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_character_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_character_usage_idx
  on plm.peanuts_character (capture_id, asset_count);

comment on table plm.peanuts_character is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Character controlled '
  'vocabulary, in full, including values no asset uses. Resolves nothing to core.character.';

-- 5. Animation title. Multi-select on the asset.
create table plm.peanuts_animation_title (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_animation_title_pkey primary key (capture_id, value_key),
  constraint peanuts_animation_title_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_animation_title_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_animation_title_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_animation_title_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_animation_title_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_animation_title_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_animation_title_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_animation_title_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_animation_title_usage_idx
  on plm.peanuts_animation_title (capture_id, asset_count);

comment on table plm.peanuts_animation_title is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Animation Title '
  'controlled vocabulary, in full. Resolves nothing.';

-- 6. Holiday. Multi-select on the asset.
create table plm.peanuts_holiday (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_holiday_pkey primary key (capture_id, value_key),
  constraint peanuts_holiday_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_holiday_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_holiday_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_holiday_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_holiday_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_holiday_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_holiday_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_holiday_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_holiday_usage_idx
  on plm.peanuts_holiday (capture_id, asset_count);

comment on table plm.peanuts_holiday is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Holiday controlled '
  'vocabulary, in full. Resolves nothing.';

-- 7. Initiative. Internal field name and UI label disagree here too (see header fact 2):
--    stored under its LABEL. Single-select on the asset.
create table plm.peanuts_initiative (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_initiative_pkey primary key (capture_id, value_key),
  constraint peanuts_initiative_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_initiative_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_initiative_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_initiative_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_initiative_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_initiative_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_initiative_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_initiative_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_initiative_usage_idx
  on plm.peanuts_initiative (capture_id, asset_count);

comment on table plm.peanuts_initiative is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Initiative controlled '
  'vocabulary, in full. Named after the PORTAL LABEL; the underlying metadata field '
  'carries a different internal name, recorded on every row. Resolves nothing.';

-- 8. Asset type. Single-select on the asset. Comic-strip type is a SUB-axis of this one
--    and lands as a column on plm.peanuts_asset, not as its own vocabulary table.
create table plm.peanuts_asset_type (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_asset_type_pkey primary key (capture_id, value_key),
  constraint peanuts_asset_type_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_asset_type_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_asset_type_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_asset_type_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_asset_type_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_asset_type_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_asset_type_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_asset_type_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_type_usage_idx
  on plm.peanuts_asset_type (capture_id, asset_count);

comment on table plm.peanuts_asset_type is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Asset Type controlled '
  'vocabulary, in full. Comic-strip type is a sub-axis of this vocabulary and is stored as '
  'plm.peanuts_asset.comic_strip_type rather than as a table of its own.';

-- 9. Licensing status. Single-select on the asset.
create table plm.peanuts_licensing_status (
  capture_id         uuid    not null,
  value_key          text    not null,
  value_label        text    not null,
  source_value_id    text        null,
  source_field_name  text    not null,
  source_field_label text    not null,
  is_multi_select    boolean not null,
  asset_count        integer not null,
  raw                jsonb   not null,

  constraint peanuts_licensing_status_pkey primary key (capture_id, value_key),
  constraint peanuts_licensing_status_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_licensing_status_value_key_nonblank_chk   check (btrim(value_key) <> ''),
  constraint peanuts_licensing_status_value_label_nonblank_chk check (btrim(value_label) <> ''),
  constraint peanuts_licensing_status_source_value_id_nonblank_chk
    check (source_value_id is null or btrim(source_value_id) <> ''),
  constraint peanuts_licensing_status_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_licensing_status_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_licensing_status_asset_count_nonneg_chk   check (asset_count >= 0),
  constraint peanuts_licensing_status_raw_obj_chk              check (jsonb_typeof(raw) = 'object')
);
create index peanuts_licensing_status_usage_idx
  on plm.peanuts_licensing_status (capture_id, asset_count);

comment on table plm.peanuts_licensing_status is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The Licensing Status '
  'controlled vocabulary, in full. This is the PORTAL''s status wording and is NOT a POP '
  'Creations licensing decision. Resolves nothing.';


-- =====================================================================================
-- 10. plm.peanuts_metadata_field -- the field dictionary.
--
-- This table exists because the internal-name / UI-label mismatch (header fact 2) is the
-- single most dangerous property of this portal and must be STORED rather than
-- remembered. The unique constraint on (capture_id, source_field_label) is what makes the
-- dictionary usable in the label direction, which is the direction every table in this
-- schema is named in.
-- =====================================================================================
create table plm.peanuts_metadata_field (
  capture_id           uuid    not null,
  source_field_name    text    not null,
  source_field_label   text    not null,
  source_definition_id text    not null,
  source_vocabulary_id text        null,
  is_multi_select      boolean not null,
  is_facetable         boolean not null,
  field_type           text    not null,
  raw                  jsonb   not null,

  constraint peanuts_metadata_field_pkey primary key (capture_id, source_field_name),
  constraint peanuts_metadata_field_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  constraint peanuts_metadata_field_label_uk unique (capture_id, source_field_label),
  constraint peanuts_metadata_field_name_nonblank_chk  check (btrim(source_field_name) <> ''),
  constraint peanuts_metadata_field_label_nonblank_chk check (btrim(source_field_label) <> ''),
  constraint peanuts_metadata_field_definition_id_nonblank_chk
    check (btrim(source_definition_id) <> ''),
  constraint peanuts_metadata_field_vocabulary_id_nonblank_chk
    check (source_vocabulary_id is null or btrim(source_vocabulary_id) <> ''),
  constraint peanuts_metadata_field_type_nonblank_chk  check (btrim(field_type) <> ''),
  constraint peanuts_metadata_field_raw_obj_chk        check (jsonb_typeof(raw) = 'object')
);

comment on table plm.peanuts_metadata_field is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. The portal''s metadata '
  'field dictionary for one capture: internal field name, the label the UI shows, and the '
  'vocabulary behind it. Stored because the two disagree on the most important fields and '
  'because an API search filter built from the wrong one is SILENTLY IGNORED, returning '
  'the unfiltered total and a capture that looks complete and is not.';


-- =====================================================================================
-- 11. plm.peanuts_asset -- one row per portal asset.
--
-- ASSET IDENTITY IS THE LICENSOR''S. Every asset carries a source-issued UUID, so unlike
-- the vocabulary tables above this table is NOT keyed on anything we generated.
-- FILENAME IS NOT UNIQUE IN THIS PORTAL and must never be treated as a key; the index on
-- lower(file_name) is a lookup aid and is deliberately NOT a unique index.
--
-- style_guide_key IS NULLABLE BY DESIGN AND MOST ROWS ARE NULL. The large majority of
-- assets here are comic strips, which are a first-class asset type rather than
-- style-guide art. Any later promotion that assumes an asset belongs to a guide will drop
-- most of this licensor.
--
-- publication_date_text IS TEXT, NOT DATE: the portal puts free text in that field.
--
-- The metadata document contains nested repeating groups (creator information, the
-- asset-type/comic-type cascade, the character-angle cascade, archive information, notes).
-- They are NOT flattened into columns here; they are preserved whole in `raw`.
-- =====================================================================================
create table plm.peanuts_asset (
  capture_id            uuid    not null,
  source_object_id      text    not null,
  source_file_id        text        null,
  file_name             text    not null,
  file_ext              text        null,
  file_size_bytes       bigint      null,
  content_type          text        null,
  checksum              text        null,
  object_type           text        null,
  version_number        integer     null,
  is_current_version    boolean     null,
  style_guide_key       text        null,
  asset_type_key        text        null,
  comic_strip_type      text        null,
  initiative_key        text        null,
  era_label             text        null,
  licensing_status_key  text        null,
  title                 text        null,
  description           text        null,
  publication_date_text text        null,
  source_created_at     timestamptz null,
  source_updated_at     timestamptz null,
  metadata_template_id  text        null,
  rendition_base_url    text        null,
  raw                   jsonb   not null,

  constraint peanuts_asset_pkey primary key (capture_id, source_object_id),
  constraint peanuts_asset_capture_fkey
    foreign key (capture_id) references plm.peanuts_capture(id) on delete restrict,
  -- The four single-select vocabulary axes. MATCH SIMPLE (the default) is intended: a row
  -- whose key is NULL is exempt, which is exactly the 'no style guide' case.
  constraint peanuts_asset_style_guide_fkey
    foreign key (capture_id, style_guide_key)
    references plm.peanuts_style_guide (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_asset_type_fkey
    foreign key (capture_id, asset_type_key)
    references plm.peanuts_asset_type (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_initiative_fkey
    foreign key (capture_id, initiative_key)
    references plm.peanuts_initiative (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_licensing_status_fkey
    foreign key (capture_id, licensing_status_key)
    references plm.peanuts_licensing_status (capture_id, value_key) on delete restrict,

  constraint peanuts_asset_object_id_nonblank_chk check (btrim(source_object_id) <> ''),
  constraint peanuts_asset_file_id_nonblank_chk
    check (source_file_id is null or btrim(source_file_id) <> ''),
  constraint peanuts_asset_file_name_nonblank_chk check (btrim(file_name) <> ''),
  -- Lowercased and dot-free, so 'JPG', '.jpg' and 'jpg' can never coexist as three
  -- different extensions for the same thing.
  constraint peanuts_asset_file_ext_shape_chk
    check (file_ext is null
           or (btrim(file_ext) <> '' and file_ext = lower(file_ext) and file_ext !~ '\.')),
  constraint peanuts_asset_file_size_nonneg_chk
    check (file_size_bytes is null or file_size_bytes >= 0),
  constraint peanuts_asset_content_type_nonblank_chk
    check (content_type is null or btrim(content_type) <> ''),
  constraint peanuts_asset_checksum_nonblank_chk
    check (checksum is null or btrim(checksum) <> ''),
  constraint peanuts_asset_object_type_nonblank_chk
    check (object_type is null or btrim(object_type) <> ''),
  constraint peanuts_asset_version_number_nonneg_chk
    check (version_number is null or version_number >= 0),
  constraint peanuts_asset_style_guide_key_nonblank_chk
    check (style_guide_key is null or btrim(style_guide_key) <> ''),
  constraint peanuts_asset_asset_type_key_nonblank_chk
    check (asset_type_key is null or btrim(asset_type_key) <> ''),
  constraint peanuts_asset_comic_strip_type_nonblank_chk
    check (comic_strip_type is null or btrim(comic_strip_type) <> ''),
  constraint peanuts_asset_initiative_key_nonblank_chk
    check (initiative_key is null or btrim(initiative_key) <> ''),
  constraint peanuts_asset_era_label_nonblank_chk
    check (era_label is null or btrim(era_label) <> ''),
  constraint peanuts_asset_licensing_status_key_nonblank_chk
    check (licensing_status_key is null or btrim(licensing_status_key) <> ''),
  constraint peanuts_asset_title_nonblank_chk
    check (title is null or btrim(title) <> ''),
  constraint peanuts_asset_description_nonblank_chk
    check (description is null or btrim(description) <> ''),
  constraint peanuts_asset_publication_date_nonblank_chk
    check (publication_date_text is null or btrim(publication_date_text) <> ''),
  constraint peanuts_asset_template_id_nonblank_chk
    check (metadata_template_id is null or btrim(metadata_template_id) <> ''),
  constraint peanuts_asset_rendition_url_nonblank_chk
    check (rendition_base_url is null or btrim(rendition_base_url) <> ''),
  constraint peanuts_asset_raw_obj_chk check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_style_guide_idx on plm.peanuts_asset (capture_id, style_guide_key);
create index peanuts_asset_asset_type_idx  on plm.peanuts_asset (capture_id, asset_type_key);
-- NOT unique: filenames repeat in this portal.
create index peanuts_asset_file_name_idx   on plm.peanuts_asset (capture_id, lower(file_name));

comment on table plm.peanuts_asset is
  'LICENSED PEANUTS SOURCE EVIDENCE, NOT CANONICAL MASTER DATA. One row per portal asset '
  'in one capture. Identity is the licensor''s own object UUID; FILE NAME IS NOT UNIQUE '
  'here and is never identity. The whole metadata document, including every nested '
  'repeating group, is preserved in `raw`. Resolves nothing to dam.* or core.*.';
comment on column plm.peanuts_asset.style_guide_key is
  'NULLABLE BY DESIGN and NULL on most rows -- most assets are comic strips, not '
  'style-guide art. Anything that assumes an asset belongs to a guide will drop the '
  'majority of this licensor.';
comment on column plm.peanuts_asset.comic_strip_type is
  'Sub-axis of asset type, stored as a column rather than as its own vocabulary table.';
comment on column plm.peanuts_asset.publication_date_text is
  'TEXT, NOT DATE, deliberately: the portal puts free text in this field. Parsing belongs '
  'in a later, separate ruling, never in the landing.';
comment on column plm.peanuts_asset.raw is
  'The complete metadata document. The nested repeating groups (creator information, the '
  'asset-type/comic-type cascade, the character-angle cascade, archive information, notes) '
  'live here whole and are NOT lossily flattened into columns.';


-- =====================================================================================
-- 12-15. THE MULTI-VALUE LINK TABLES -- portal-declared, one per multi-select axis.
--
-- Each row is a value the portal itself stamped on the asset. Nothing here is inferred.
-- The reverse indexes exist because the primary key leads with the asset, while the
-- question every consumer asks first is "which assets carry this value".
-- =====================================================================================

-- 12. Asset -> art programme.
create table plm.peanuts_asset_art_program (
  capture_id       uuid  not null,
  source_object_id text  not null,
  art_program_key  text  not null,
  raw              jsonb not null,

  constraint peanuts_asset_art_program_pkey
    primary key (capture_id, source_object_id, art_program_key),
  constraint peanuts_asset_art_program_asset_fkey
    foreign key (capture_id, source_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_art_program_value_fkey
    foreign key (capture_id, art_program_key)
    references plm.peanuts_art_program (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_art_program_key_nonblank_chk check (btrim(art_program_key) <> ''),
  constraint peanuts_asset_art_program_raw_obj_chk      check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_art_program_value_idx
  on plm.peanuts_asset_art_program (capture_id, art_program_key);

comment on table plm.peanuts_asset_art_program is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED: the art-program values the portal '
  'itself stamped on the asset. Multi-select, so an asset may carry several. Nothing may '
  'pair these rows with plm.peanuts_asset_character to manufacture an '
  'art-program-to-character link -- that pairing is refused by this schema.';

-- 13. Asset -> character.
create table plm.peanuts_asset_character (
  capture_id       uuid  not null,
  source_object_id text  not null,
  character_key    text  not null,
  raw              jsonb not null,

  constraint peanuts_asset_character_pkey
    primary key (capture_id, source_object_id, character_key),
  constraint peanuts_asset_character_asset_fkey
    foreign key (capture_id, source_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_character_value_fkey
    foreign key (capture_id, character_key)
    references plm.peanuts_character (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_character_key_nonblank_chk check (btrim(character_key) <> ''),
  constraint peanuts_asset_character_raw_obj_chk      check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_character_value_idx
  on plm.peanuts_asset_character (capture_id, character_key);

comment on table plm.peanuts_asset_character is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED: the character values the portal '
  'itself stamped on the asset. Multi-select. Resolves nothing to core.character.';

-- 14. Asset -> animation title.
create table plm.peanuts_asset_animation_title (
  capture_id          uuid  not null,
  source_object_id    text  not null,
  animation_title_key text  not null,
  raw                 jsonb not null,

  constraint peanuts_asset_animation_title_pkey
    primary key (capture_id, source_object_id, animation_title_key),
  constraint peanuts_asset_animation_title_asset_fkey
    foreign key (capture_id, source_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_animation_title_value_fkey
    foreign key (capture_id, animation_title_key)
    references plm.peanuts_animation_title (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_animation_title_key_nonblank_chk
    check (btrim(animation_title_key) <> ''),
  constraint peanuts_asset_animation_title_raw_obj_chk check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_animation_title_value_idx
  on plm.peanuts_asset_animation_title (capture_id, animation_title_key);

comment on table plm.peanuts_asset_animation_title is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED: the animation-title values the '
  'portal itself stamped on the asset. Multi-select.';

-- 15. Asset -> holiday.
create table plm.peanuts_asset_holiday (
  capture_id       uuid  not null,
  source_object_id text  not null,
  holiday_key      text  not null,
  raw              jsonb not null,

  constraint peanuts_asset_holiday_pkey
    primary key (capture_id, source_object_id, holiday_key),
  constraint peanuts_asset_holiday_asset_fkey
    foreign key (capture_id, source_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_holiday_value_fkey
    foreign key (capture_id, holiday_key)
    references plm.peanuts_holiday (capture_id, value_key) on delete restrict,
  constraint peanuts_asset_holiday_key_nonblank_chk check (btrim(holiday_key) <> ''),
  constraint peanuts_asset_holiday_raw_obj_chk      check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_holiday_value_idx
  on plm.peanuts_asset_holiday (capture_id, holiday_key);

comment on table plm.peanuts_asset_holiday is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED: the holiday values the portal itself '
  'stamped on the asset. Multi-select.';


-- =====================================================================================
-- 16. plm.peanuts_asset_keyword -- portal-declared, but deliberately WITHOUT a vocabulary
--     foreign key.
--
-- Keywords are multi-select and high-cardinality, and the keyword vocabulary is OPEN and
-- only partly validated -- the portal carries a separate free-text unvalidated-keywords
-- field, which stays in plm.peanuts_asset.raw. A foreign key here would either reject
-- legitimate source rows or force us to invent vocabulary entries the licensor never
-- published. `keyword_label` therefore carries the licensor''s own spelling, because no
-- vocabulary table exists to hold it.
-- =====================================================================================
create table plm.peanuts_asset_keyword (
  capture_id       uuid  not null,
  source_object_id text  not null,
  keyword_key      text  not null,
  keyword_label    text  not null,
  raw              jsonb not null,

  constraint peanuts_asset_keyword_pkey
    primary key (capture_id, source_object_id, keyword_key),
  constraint peanuts_asset_keyword_asset_fkey
    foreign key (capture_id, source_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_keyword_key_nonblank_chk   check (btrim(keyword_key) <> ''),
  constraint peanuts_asset_keyword_label_nonblank_chk check (btrim(keyword_label) <> ''),
  constraint peanuts_asset_keyword_raw_obj_chk        check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_keyword_value_idx
  on plm.peanuts_asset_keyword (capture_id, keyword_key);

comment on table plm.peanuts_asset_keyword is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED keywords, with NO vocabulary foreign '
  'key by design: the keyword vocabulary is open and only partly validated. The portal''s '
  'separate free-text unvalidated-keywords field is NOT split out here and stays in '
  'plm.peanuts_asset.raw.';


-- =====================================================================================
-- 17. plm.peanuts_asset_relationship -- THE ONE DECLARED HIERARCHY.
--
-- The portal returns this explicitly, per asset, with a stated parent, a stated child and
-- a stated link type. It is the only true hierarchy in this source and it is FACT, not
-- inference. `link_type` is stored VERBATIM and is never assumed: a future link type we
-- have not seen must land as itself rather than be coerced into the one we know.
--
-- This table is why plm.peanuts_capture.relationship_graph_walked exists -- it is
-- populated by a per-asset call, it is the slowest part of the capture, and a partial
-- walk must be visible rather than silently short.
-- =====================================================================================
create table plm.peanuts_asset_relationship (
  capture_id             uuid  not null,
  source_relationship_id text  not null,
  parent_object_id       text  not null,
  child_object_id        text  not null,
  link_type              text  not null,
  raw                    jsonb not null,

  constraint peanuts_asset_relationship_pkey
    primary key (capture_id, source_relationship_id),
  constraint peanuts_asset_relationship_parent_fkey
    foreign key (capture_id, parent_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_relationship_child_fkey
    foreign key (capture_id, child_object_id)
    references plm.peanuts_asset (capture_id, source_object_id) on delete restrict,
  constraint peanuts_asset_relationship_not_self_chk
    check (parent_object_id <> child_object_id),
  constraint peanuts_asset_relationship_id_nonblank_chk
    check (btrim(source_relationship_id) <> ''),
  constraint peanuts_asset_relationship_parent_nonblank_chk
    check (btrim(parent_object_id) <> ''),
  constraint peanuts_asset_relationship_child_nonblank_chk
    check (btrim(child_object_id) <> ''),
  constraint peanuts_asset_relationship_link_type_nonblank_chk
    check (btrim(link_type) <> ''),
  constraint peanuts_asset_relationship_raw_obj_chk check (jsonb_typeof(raw) = 'object')
);
create index peanuts_asset_relationship_parent_idx
  on plm.peanuts_asset_relationship (capture_id, parent_object_id);
create index peanuts_asset_relationship_child_idx
  on plm.peanuts_asset_relationship (capture_id, child_object_id);

comment on table plm.peanuts_asset_relationship is
  'LICENSED PEANUTS SOURCE EVIDENCE. PORTAL-DECLARED asset parent/child edges -- the only '
  'true hierarchy this source publishes. In practice the parent is a style-guide document '
  'asset and the children are the art files cut from it, but that pattern is NOT encoded: '
  'link_type is stored verbatim so an unfamiliar edge lands as itself.';
comment on column plm.peanuts_asset_relationship.link_type is
  'Stored verbatim, never assumed and never normalised. Do not add a CHECK that pins it to '
  'the values seen so far; an unseen link type must land, not fail.';


-- =====================================================================================
-- 18. plm.peanuts_style_guide_character -- DERIVED, AND LABELLED AS SUCH.
--
-- The portal publishes no character roster per style guide. These rows are OURS.
--
-- The derivation is clean because the style-guide field is SINGLE-select (pinned by
-- peanuts_style_guide_single_select_chk above): an asset carries exactly one style guide
-- or none, so there is no ambiguity to split and no exclusion list is needed. It still
-- covers only the minority of assets that carry a guide at all.
--
-- relationship_truth is CONSTRAINED to 'derived', not defaulted to it, so no later
-- migration can quietly promote these rows to fact by inserting a different value.
-- =====================================================================================
create table plm.peanuts_style_guide_character (
  capture_id         uuid    not null,
  style_guide_key    text    not null,
  character_key      text    not null,
  asset_count        integer not null,
  relationship_truth text    not null,
  derivation_note    text    not null,

  constraint peanuts_style_guide_character_pkey
    primary key (capture_id, style_guide_key, character_key),
  constraint peanuts_style_guide_character_guide_fkey
    foreign key (capture_id, style_guide_key)
    references plm.peanuts_style_guide (capture_id, value_key) on delete restrict,
  constraint peanuts_style_guide_character_character_fkey
    foreign key (capture_id, character_key)
    references plm.peanuts_character (capture_id, value_key) on delete restrict,
  constraint peanuts_style_guide_character_asset_count_pos_chk check (asset_count > 0),
  constraint peanuts_style_guide_character_truth_chk
    check (relationship_truth = 'derived'),
  constraint peanuts_style_guide_character_note_nonblank_chk
    check (btrim(derivation_note) <> '')
);

comment on table plm.peanuts_style_guide_character is
  'DERIVED BY THIS PIPELINE, NOT STATED BY THE LICENSOR. Style guide to character, '
  'co-derived from assets that carry both. Unambiguous only because the style-guide field '
  'is single-select. Every row is pinned to relationship_truth = ''derived'' by a CHECK '
  'that permits no other value. Nothing may present these rows as source-declared fact '
  'and nothing may auto-promote them into core.character.';
comment on column plm.peanuts_style_guide_character.asset_count is
  'How many assets support this pair. Strictly positive: a derived edge with no supporting '
  'asset has nothing behind it and must not exist.';
comment on column plm.peanuts_style_guide_character.derivation_note is
  'Must state the derivation rule actually used, including that the style-guide field is '
  'single-select and that the derivation covers only assets carrying a guide.';


-- =====================================================================================
-- 19. plm.peanuts_style_guide_art_program -- DERIVED, AND MANY-TO-MANY BY REQUIREMENT.
--
-- Many-to-many is not a convenience: style guides in this source already appear under more
-- than one art programme, so a single art-program column on the guide would be wrong on
-- data we already hold. Same 'derived' pin as the table above.
-- =====================================================================================
create table plm.peanuts_style_guide_art_program (
  capture_id         uuid    not null,
  style_guide_key    text    not null,
  art_program_key    text    not null,
  asset_count        integer not null,
  relationship_truth text    not null,
  derivation_note    text    not null,

  constraint peanuts_style_guide_art_program_pkey
    primary key (capture_id, style_guide_key, art_program_key),
  constraint peanuts_style_guide_art_program_guide_fkey
    foreign key (capture_id, style_guide_key)
    references plm.peanuts_style_guide (capture_id, value_key) on delete restrict,
  constraint peanuts_style_guide_art_program_value_fkey
    foreign key (capture_id, art_program_key)
    references plm.peanuts_art_program (capture_id, value_key) on delete restrict,
  constraint peanuts_style_guide_art_program_count_pos_chk check (asset_count > 0),
  constraint peanuts_style_guide_art_program_truth_chk
    check (relationship_truth = 'derived'),
  constraint peanuts_style_guide_art_program_note_chk
    check (btrim(derivation_note) <> '')
);

comment on table plm.peanuts_style_guide_art_program is
  'DERIVED BY THIS PIPELINE, NOT STATED BY THE LICENSOR. Style guide to art programme, '
  'MANY-TO-MANY because guides already appear under more than one programme in the source. '
  'Pinned to relationship_truth = ''derived'' by a CHECK that permits no other value.';


-- =====================================================================================
-- RLS, GRANTS, AND THE IMMUTABILITY MECHANISM.
--
-- An RLS policy is not a GRANT and a GRANT is not an RLS policy (AGENTS.md section 11).
-- Both are set here. Supabase''s service_role carries BYPASSRLS, so RLS alone could NOT
-- constrain the loader -- the GRANTS are what enforce immutability.
--
--   plm.peanuts_capture -> service_role: SELECT only. See the OPEN DEPENDENCY note in the
--                          file header: the begin/finalize write path is a separate claim.
--   the other 18        -> service_role: SELECT + INSERT. No UPDATE, DELETE or TRUNCATE.
--                          Rows are immutable from the instant they land.
--   authenticated       -> SELECT only, under the established plm read predicate:
--                          PLM app access, administrator, sales or licensing.
--   anon                -> nothing, revoked explicitly.
--
-- Every statement below is written out in full, one per table, statically and
-- schema-qualified. No dynamic SQL: an auditor -- and the guard that verifies a migration
-- only touches objects its author claimed -- must be able to read exactly which table
-- receives which privilege without executing anything.
--
-- ENABLE, deliberately NOT FORCE. FORCE would apply RLS to the table owner too, which
-- locks the migration runner and every contract-test session out of its own tables for no
-- security gain -- service_role is the identity being constrained, and it is constrained
-- by the GRANTS below, not by RLS.
-- =====================================================================================

-- plm.peanuts_capture
alter table plm.peanuts_capture enable row level security;
revoke all on plm.peanuts_capture from public;
revoke all on plm.peanuts_capture from anon;
revoke all on plm.peanuts_capture from authenticated;
grant select on plm.peanuts_capture to service_role;
grant select on plm.peanuts_capture to authenticated;
create policy peanuts_capture_service_read on plm.peanuts_capture
  for select to service_role using (true);
create policy peanuts_capture_plm_read on plm.peanuts_capture
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_art_program
alter table plm.peanuts_art_program enable row level security;
revoke all on plm.peanuts_art_program from public;
revoke all on plm.peanuts_art_program from anon;
revoke all on plm.peanuts_art_program from authenticated;
grant select, insert on plm.peanuts_art_program to service_role;
grant select on plm.peanuts_art_program to authenticated;
create policy peanuts_art_program_service_read on plm.peanuts_art_program
  for select to service_role using (true);
create policy peanuts_art_program_plm_read on plm.peanuts_art_program
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_style_guide
alter table plm.peanuts_style_guide enable row level security;
revoke all on plm.peanuts_style_guide from public;
revoke all on plm.peanuts_style_guide from anon;
revoke all on plm.peanuts_style_guide from authenticated;
grant select, insert on plm.peanuts_style_guide to service_role;
grant select on plm.peanuts_style_guide to authenticated;
create policy peanuts_style_guide_service_read on plm.peanuts_style_guide
  for select to service_role using (true);
create policy peanuts_style_guide_plm_read on plm.peanuts_style_guide
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_character
alter table plm.peanuts_character enable row level security;
revoke all on plm.peanuts_character from public;
revoke all on plm.peanuts_character from anon;
revoke all on plm.peanuts_character from authenticated;
grant select, insert on plm.peanuts_character to service_role;
grant select on plm.peanuts_character to authenticated;
create policy peanuts_character_service_read on plm.peanuts_character
  for select to service_role using (true);
create policy peanuts_character_plm_read on plm.peanuts_character
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_animation_title
alter table plm.peanuts_animation_title enable row level security;
revoke all on plm.peanuts_animation_title from public;
revoke all on plm.peanuts_animation_title from anon;
revoke all on plm.peanuts_animation_title from authenticated;
grant select, insert on plm.peanuts_animation_title to service_role;
grant select on plm.peanuts_animation_title to authenticated;
create policy peanuts_animation_title_service_read on plm.peanuts_animation_title
  for select to service_role using (true);
create policy peanuts_animation_title_plm_read on plm.peanuts_animation_title
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_holiday
alter table plm.peanuts_holiday enable row level security;
revoke all on plm.peanuts_holiday from public;
revoke all on plm.peanuts_holiday from anon;
revoke all on plm.peanuts_holiday from authenticated;
grant select, insert on plm.peanuts_holiday to service_role;
grant select on plm.peanuts_holiday to authenticated;
create policy peanuts_holiday_service_read on plm.peanuts_holiday
  for select to service_role using (true);
create policy peanuts_holiday_plm_read on plm.peanuts_holiday
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_initiative
alter table plm.peanuts_initiative enable row level security;
revoke all on plm.peanuts_initiative from public;
revoke all on plm.peanuts_initiative from anon;
revoke all on plm.peanuts_initiative from authenticated;
grant select, insert on plm.peanuts_initiative to service_role;
grant select on plm.peanuts_initiative to authenticated;
create policy peanuts_initiative_service_read on plm.peanuts_initiative
  for select to service_role using (true);
create policy peanuts_initiative_plm_read on plm.peanuts_initiative
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_type
alter table plm.peanuts_asset_type enable row level security;
revoke all on plm.peanuts_asset_type from public;
revoke all on plm.peanuts_asset_type from anon;
revoke all on plm.peanuts_asset_type from authenticated;
grant select, insert on plm.peanuts_asset_type to service_role;
grant select on plm.peanuts_asset_type to authenticated;
create policy peanuts_asset_type_service_read on plm.peanuts_asset_type
  for select to service_role using (true);
create policy peanuts_asset_type_plm_read on plm.peanuts_asset_type
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_licensing_status
alter table plm.peanuts_licensing_status enable row level security;
revoke all on plm.peanuts_licensing_status from public;
revoke all on plm.peanuts_licensing_status from anon;
revoke all on plm.peanuts_licensing_status from authenticated;
grant select, insert on plm.peanuts_licensing_status to service_role;
grant select on plm.peanuts_licensing_status to authenticated;
create policy peanuts_licensing_status_service_read on plm.peanuts_licensing_status
  for select to service_role using (true);
create policy peanuts_licensing_status_plm_read on plm.peanuts_licensing_status
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_metadata_field
alter table plm.peanuts_metadata_field enable row level security;
revoke all on plm.peanuts_metadata_field from public;
revoke all on plm.peanuts_metadata_field from anon;
revoke all on plm.peanuts_metadata_field from authenticated;
grant select, insert on plm.peanuts_metadata_field to service_role;
grant select on plm.peanuts_metadata_field to authenticated;
create policy peanuts_metadata_field_service_read on plm.peanuts_metadata_field
  for select to service_role using (true);
create policy peanuts_metadata_field_plm_read on plm.peanuts_metadata_field
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset
alter table plm.peanuts_asset enable row level security;
revoke all on plm.peanuts_asset from public;
revoke all on plm.peanuts_asset from anon;
revoke all on plm.peanuts_asset from authenticated;
grant select, insert on plm.peanuts_asset to service_role;
grant select on plm.peanuts_asset to authenticated;
create policy peanuts_asset_service_read on plm.peanuts_asset
  for select to service_role using (true);
create policy peanuts_asset_plm_read on plm.peanuts_asset
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_art_program
alter table plm.peanuts_asset_art_program enable row level security;
revoke all on plm.peanuts_asset_art_program from public;
revoke all on plm.peanuts_asset_art_program from anon;
revoke all on plm.peanuts_asset_art_program from authenticated;
grant select, insert on plm.peanuts_asset_art_program to service_role;
grant select on plm.peanuts_asset_art_program to authenticated;
create policy peanuts_asset_art_program_service_read on plm.peanuts_asset_art_program
  for select to service_role using (true);
create policy peanuts_asset_art_program_plm_read on plm.peanuts_asset_art_program
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_character
alter table plm.peanuts_asset_character enable row level security;
revoke all on plm.peanuts_asset_character from public;
revoke all on plm.peanuts_asset_character from anon;
revoke all on plm.peanuts_asset_character from authenticated;
grant select, insert on plm.peanuts_asset_character to service_role;
grant select on plm.peanuts_asset_character to authenticated;
create policy peanuts_asset_character_service_read on plm.peanuts_asset_character
  for select to service_role using (true);
create policy peanuts_asset_character_plm_read on plm.peanuts_asset_character
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_animation_title
alter table plm.peanuts_asset_animation_title enable row level security;
revoke all on plm.peanuts_asset_animation_title from public;
revoke all on plm.peanuts_asset_animation_title from anon;
revoke all on plm.peanuts_asset_animation_title from authenticated;
grant select, insert on plm.peanuts_asset_animation_title to service_role;
grant select on plm.peanuts_asset_animation_title to authenticated;
create policy peanuts_asset_animation_title_service_read on plm.peanuts_asset_animation_title
  for select to service_role using (true);
create policy peanuts_asset_animation_title_plm_read on plm.peanuts_asset_animation_title
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_holiday
alter table plm.peanuts_asset_holiday enable row level security;
revoke all on plm.peanuts_asset_holiday from public;
revoke all on plm.peanuts_asset_holiday from anon;
revoke all on plm.peanuts_asset_holiday from authenticated;
grant select, insert on plm.peanuts_asset_holiday to service_role;
grant select on plm.peanuts_asset_holiday to authenticated;
create policy peanuts_asset_holiday_service_read on plm.peanuts_asset_holiday
  for select to service_role using (true);
create policy peanuts_asset_holiday_plm_read on plm.peanuts_asset_holiday
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_keyword
alter table plm.peanuts_asset_keyword enable row level security;
revoke all on plm.peanuts_asset_keyword from public;
revoke all on plm.peanuts_asset_keyword from anon;
revoke all on plm.peanuts_asset_keyword from authenticated;
grant select, insert on plm.peanuts_asset_keyword to service_role;
grant select on plm.peanuts_asset_keyword to authenticated;
create policy peanuts_asset_keyword_service_read on plm.peanuts_asset_keyword
  for select to service_role using (true);
create policy peanuts_asset_keyword_plm_read on plm.peanuts_asset_keyword
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_asset_relationship
alter table plm.peanuts_asset_relationship enable row level security;
revoke all on plm.peanuts_asset_relationship from public;
revoke all on plm.peanuts_asset_relationship from anon;
revoke all on plm.peanuts_asset_relationship from authenticated;
grant select, insert on plm.peanuts_asset_relationship to service_role;
grant select on plm.peanuts_asset_relationship to authenticated;
create policy peanuts_asset_relationship_service_read on plm.peanuts_asset_relationship
  for select to service_role using (true);
create policy peanuts_asset_relationship_plm_read on plm.peanuts_asset_relationship
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_style_guide_character
alter table plm.peanuts_style_guide_character enable row level security;
revoke all on plm.peanuts_style_guide_character from public;
revoke all on plm.peanuts_style_guide_character from anon;
revoke all on plm.peanuts_style_guide_character from authenticated;
grant select, insert on plm.peanuts_style_guide_character to service_role;
grant select on plm.peanuts_style_guide_character to authenticated;
create policy peanuts_style_guide_character_service_read on plm.peanuts_style_guide_character
  for select to service_role using (true);
create policy peanuts_style_guide_character_plm_read on plm.peanuts_style_guide_character
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

-- plm.peanuts_style_guide_art_program
alter table plm.peanuts_style_guide_art_program enable row level security;
revoke all on plm.peanuts_style_guide_art_program from public;
revoke all on plm.peanuts_style_guide_art_program from anon;
revoke all on plm.peanuts_style_guide_art_program from authenticated;
grant select, insert on plm.peanuts_style_guide_art_program to service_role;
grant select on plm.peanuts_style_guide_art_program to authenticated;
create policy peanuts_style_guide_art_program_service_read on plm.peanuts_style_guide_art_program
  for select to service_role using (true);
create policy peanuts_style_guide_art_program_plm_read on plm.peanuts_style_guide_art_program
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));


-- -------------------------------------------------------------------------------------
-- THE REVOKES THAT ACTUALLY DELIVER IMMUTABILITY.
--
-- The schema `plm` carries ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO
-- service_role, so Postgres handed every table above SELECT, INSERT, UPDATE, DELETE,
-- TRUNCATE, REFERENCES and TRIGGER at CREATE TABLE time. The `grant select, insert`
-- statements above were therefore NO-OPS against a role that already held everything.
-- This is exactly the defect that migration 20260810080000 had to correct for NBCU after
-- the fact; it is handled inside this file instead.
--
-- REFERENCES and TRIGGER are left in place. REFERENCES only allows creating a foreign key
-- that points AT these tables, which writes nothing, and no user trigger exists on them.
-- -------------------------------------------------------------------------------------
revoke update, delete, truncate on plm.peanuts_capture from service_role;
revoke insert on plm.peanuts_capture from authenticated;
revoke update, delete, truncate on plm.peanuts_capture from authenticated;
-- Capture rows are reserved for the begin/finalize security-definer pair (see the OPEN
-- DEPENDENCY note in the file header). A direct INSERT here would let a loader mint a
-- capture that skipped every validation that pair exists to perform.
revoke insert on plm.peanuts_capture from service_role;

revoke update, delete, truncate on plm.peanuts_art_program from service_role;
revoke insert on plm.peanuts_art_program from authenticated;
revoke update, delete, truncate on plm.peanuts_art_program from authenticated;

revoke update, delete, truncate on plm.peanuts_style_guide from service_role;
revoke insert on plm.peanuts_style_guide from authenticated;
revoke update, delete, truncate on plm.peanuts_style_guide from authenticated;

revoke update, delete, truncate on plm.peanuts_character from service_role;
revoke insert on plm.peanuts_character from authenticated;
revoke update, delete, truncate on plm.peanuts_character from authenticated;

revoke update, delete, truncate on plm.peanuts_animation_title from service_role;
revoke insert on plm.peanuts_animation_title from authenticated;
revoke update, delete, truncate on plm.peanuts_animation_title from authenticated;

revoke update, delete, truncate on plm.peanuts_holiday from service_role;
revoke insert on plm.peanuts_holiday from authenticated;
revoke update, delete, truncate on plm.peanuts_holiday from authenticated;

revoke update, delete, truncate on plm.peanuts_initiative from service_role;
revoke insert on plm.peanuts_initiative from authenticated;
revoke update, delete, truncate on plm.peanuts_initiative from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_type from service_role;
revoke insert on plm.peanuts_asset_type from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_type from authenticated;

revoke update, delete, truncate on plm.peanuts_licensing_status from service_role;
revoke insert on plm.peanuts_licensing_status from authenticated;
revoke update, delete, truncate on plm.peanuts_licensing_status from authenticated;

revoke update, delete, truncate on plm.peanuts_metadata_field from service_role;
revoke insert on plm.peanuts_metadata_field from authenticated;
revoke update, delete, truncate on plm.peanuts_metadata_field from authenticated;

revoke update, delete, truncate on plm.peanuts_asset from service_role;
revoke insert on plm.peanuts_asset from authenticated;
revoke update, delete, truncate on plm.peanuts_asset from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_art_program from service_role;
revoke insert on plm.peanuts_asset_art_program from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_art_program from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_character from service_role;
revoke insert on plm.peanuts_asset_character from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_character from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_animation_title from service_role;
revoke insert on plm.peanuts_asset_animation_title from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_animation_title from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_holiday from service_role;
revoke insert on plm.peanuts_asset_holiday from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_holiday from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_keyword from service_role;
revoke insert on plm.peanuts_asset_keyword from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_keyword from authenticated;

revoke update, delete, truncate on plm.peanuts_asset_relationship from service_role;
revoke insert on plm.peanuts_asset_relationship from authenticated;
revoke update, delete, truncate on plm.peanuts_asset_relationship from authenticated;

revoke update, delete, truncate on plm.peanuts_style_guide_character from service_role;
revoke insert on plm.peanuts_style_guide_character from authenticated;
revoke update, delete, truncate on plm.peanuts_style_guide_character from authenticated;

revoke update, delete, truncate on plm.peanuts_style_guide_art_program from service_role;
revoke insert on plm.peanuts_style_guide_art_program from authenticated;
revoke update, delete, truncate on plm.peanuts_style_guide_art_program from authenticated;


-- Assert the OUTCOME inside the migration, so this file cannot fail silently the way the
-- NBCU landing did. If the revokes did not take, this raises and the migration fails.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee in ('service_role','authenticated')
     and privilege_type in ('UPDATE','DELETE','TRUNCATE');
  if v_bad <> 0 then
    raise exception
      'peanuts landing: % write grant(s) survive on peanuts tables; immutability is INERT',
      v_bad;
  end if;

  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name = 'peanuts_capture'
     and grantee = 'service_role' and privilege_type = 'INSERT';
  if v_bad <> 0 then
    raise exception 'peanuts landing: plm.peanuts_capture is still directly insertable';
  end if;

  -- A revoke that overshot into SELECT or INSERT would break the loader, so prove it did
  -- not: 19 readable tables, 18 insertable snapshot tables.
  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'service_role' and privilege_type = 'SELECT';
  if v_bad <> 19 then
    raise exception 'peanuts landing: expected 19 service_role SELECT grants, found %', v_bad;
  end if;

  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'service_role' and privilege_type = 'INSERT';
  if v_bad <> 18 then
    raise exception 'peanuts landing: expected 18 service_role INSERT grants, found %', v_bad;
  end if;

  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_bad <> 19 then
    raise exception
      'peanuts landing: expected 19 authenticated SELECT grants, found %', v_bad;
  end if;

  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema = 'plm' and table_name like 'peanuts\_%'
     and grantee = 'anon';
  if v_bad <> 0 then
    raise exception 'peanuts landing: anon holds % grant(s) on peanuts tables', v_bad;
  end if;

  raise notice 'peanuts privileges: service_role SELECT x19 / INSERT x18, no UPDATE/DELETE/TRUNCATE, anon none';
end;
$$;


-- Assert the SHAPE guarantees that this landing is worthless without, so a later edit
-- that quietly drops one fails here rather than in a load six weeks from now.
do $$
declare
  v_n integer;
begin
  -- The refused relationship. No table in this schema may hold an art-program-to-character
  -- link, derived or otherwise.
  select count(*) into v_n
    from information_schema.tables
   where table_schema = 'plm'
     and table_name like 'peanuts\_%'
     and table_name like '%art\_program%'
     and table_name like '%character%';
  if v_n <> 0 then
    raise exception
      'peanuts landing: % art-program-to-character table(s) exist; that link is refused', v_n;
  end if;

  -- No media may ever be stored on the asset table.
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'plm' and table_name = 'peanuts_asset'
     and (column_name in ('bytes','media','content','blob','base64','file_bytes')
          or data_type = 'bytea');
  if v_n <> 0 then
    raise exception 'peanuts landing: plm.peanuts_asset carries % media-bearing column(s)', v_n;
  end if;

  -- Style guide must be NULLABLE on the asset: most assets carry none.
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'plm' and table_name = 'peanuts_asset'
     and column_name = 'style_guide_key' and is_nullable = 'YES';
  if v_n <> 1 then
    raise exception
      'peanuts landing: plm.peanuts_asset.style_guide_key must exist and be NULLABLE';
  end if;

  -- publication_date_text must stay text. A date column here would reject the portal''s
  -- free-text values and lose them.
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'plm' and table_name = 'peanuts_asset'
     and column_name = 'publication_date_text' and data_type = 'text';
  if v_n <> 1 then
    raise exception 'peanuts landing: publication_date_text must exist and be text';
  end if;

  -- All 19 claimed tables exist.
  select count(*) into v_n
    from information_schema.tables
   where table_schema = 'plm' and table_name like 'peanuts\_%' and table_type = 'BASE TABLE';
  if v_n <> 19 then
    raise exception 'peanuts landing: expected 19 tables, found %', v_n;
  end if;

  raise notice 'peanuts shape: 19 tables, no art-program-to-character link, no media, style guide nullable';
end;
$$;
