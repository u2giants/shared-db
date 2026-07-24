# App migration note — ColdLion licensor/property Phase 2A (mirror-only importer)

**Date:** 2026-07-24
**Migrations:** `20260724060000_coldlion_licensor_property_phase2a_mirror_importer.sql`
and `20260724061000_coldlion_licensor_property_phase2a_guard_corrections.sql` (additive)
**Status:** implemented, independently reviewed, and applied to preview only; **no ColdLion pull** run.
**Audience:** any app/session reading licensor/property master data (DAM, PM/PIM, CRM, PopSG,
DesignFlow, DB Data Admin).

## TL;DR for app teams

- A new **mirror-only** ColdLion importer exists. It populates the Phase 1 tables
  `plm.erp_licensor` / `plm.erp_property` (and `plm.merch_group_header`, `ingest.raw_record`,
  `plm.taxonomy_resolution_review`) from ColdLion `/merchGroupHeaders` + licensed
  `/merchGroupDetails`. **It does not touch `core.licensor` / `core.property` at all** — not their
  UUIDs, status, parent (`core.property.licensor_id`), aliases, or `core.taxonomy_source_ref`.
- Apps should keep reading the canonical `core.*` contract or the Phase 1 `api.coldlion_*`
  reconciliation views. No app query, FK, view, or picker needs to change for Phase 2A.
- There is **no schedule** in Phase 2A (no Edge Function, no `pg_cron`). The importer runs on demand
  via `tools/sync-coldlion-licensors-properties.mjs`. Scheduling is Phase 6.

## New database objects

- `plm.sync_coldlion_licensors_properties(snapshot jsonb, mode text default 'mirror_only')` —
  internal SECURITY DEFINER importer. `mirror_only` only; other modes raise.
- `public.sync_coldlion_licensors_properties(snapshot jsonb, mode text)` — thin SECURITY DEFINER
  wrapper so a serverless/service-role caller does not need a raw DB password. Execute granted to
  `service_role` only (revoked from `public`); `authenticated` cannot call it.
- `api.coldlion_licensor_property_run_list(limit int default 50)` — read-only, admin-gated
  (`app.has_role('administrator')`) run-accounting surface for DB Data Admin.

## What app teams should know

- **Meaning is per-division.** Licensors/properties are CW001/SP001 `05`/`06` only. EH001 `05`
  (Big Theme) and EP001 `05` (Product Line) are never treated as licensor/property by the importer.
- **Codes are not globally unique.** `plm.erp_*` rows are keyed by
  `(company_code, division_code, mg_type_code, mg_code)` — never `mg_code` alone (e.g. `1P`/`FR` can
  be both a licensor and a property).
- **Cross-entity collisions** (same `mg_code` as both licensor and property in one division) open a
  `conflict` review finding; they are never auto-cross-linked. Phase 3 reconciles them.
- **Mirror rows start `resolution_status='unresolved'`.** Matching/linking to canonical UUIDs is
  Phase 4. Nothing in Phase 2A creates or changes a canonical row.

## Rollback

Additive only. Operational rollback (plan §13): do not schedule the importer; leave the mirrors in
place as evidence; the DesignFlow master-record refresh remains the only promoter. A later schema
cleanup (dropping the functions) needs its own migration and is not the emergency rollback.

## Verification pointer

Local static + unit checks passed (35/35). The rolled-back SQL contract
(`supabase/tests/coldlion_licensor_property_phase2_contracts.sql`) passed independently against
preview after the final review corrections. Full detail:
`docs/verification/coldlion-licensor-property-phase2a-20260724.md` and
`fix_coldlion_licensor_property_phase2a_handoff.md`.
