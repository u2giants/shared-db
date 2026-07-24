# Handoff — Phase 1 ColdLion licensor/property (revised, worktree only)

**Worktree:** `C:/tmp/shared-db-grok-neutral-taxonomy-phase1`
**Branch:** `codex/grok-neutral-taxonomy-phase1`
**Status:** Phase 1 **revised locally, not committed, not applied**

## What changed vs first draft / prior revision

| Topic | Now |
|---|---|
| Timestamp | `20260724030000` (removed future `20260724120000`) |
| Parent edge | **Enforced:** NOT NULL + `property_licensor_id_fkey` ON DELETE **RESTRICT** |
| Header meaning | Unique semantic key; mirrors FK it ON DELETE RESTRICT |
| Review IDs | Typed `proposed_*` / `resolved_*` FKs; `finding_scope` for canonical-only |
| **Active uniqueness** | **Partial** unique `plm_taxonomy_resolution_review_source_uidx` on source key **only where** `status in ('open','quarantined','conflict')`. Terminal `approved_link` / `ignored` / `dismissed` rows are history and do **not** block a later new active finding. |
| **Status/resolution matrix** | CHECK pair `status_resolution_ck` + `resolved_link_ck`: `approved_link` requires `resolution=approved_link`, typed resolved ID, nonblank `resolved_by`, nonnull `resolved_at`. Non-approved statuses null the whole resolved package and cannot carry `resolution=approved_link`. `conflict` ↛ `ignored`; `ignored` ↛ `conflict`. |
| Browser writes | No write policies; REVOKE ALL then SELECT only |
| `raw` | NOT NULL, **no default** |
| `last_seen_at` | Documented: migration default ≠ source freshness |

### Why active statuses are open | quarantined | conflict

Only these three still need operator/importer attention on the work queue.
`approved_link`, `ignored`, and `dismissed` are close-outs that must remain as
audit history; a non-partial unique index would incorrectly allow only one
finding forever per source key.

## Files

- `supabase/migrations/20260724030000_coldlion_licensor_property_phase1_mirror_schema.sql`
- `supabase/tests/coldlion_licensor_property_phase1_contracts.sql`
- `tools/coldlion-licensor-property-phase1.test.mjs`
- `docs/app-migration-notes/coldlion-licensor-property-phase1-20260724.md`
- `docs/verification/coldlion-licensor-property-phase1-20260724.md`

## Explicitly NOT done

Commit / push / PR / merge · preview/prod apply · ColdLion fetch/runner/schedule ·
canonical importer · DesignFlow disablement · credentials / 1Password

## Next actions

1. Review revised migration + contracts (especially partial unique + matrix).
2. Commit when ready.
3. Preview dry-run/apply on `rjyboqwcdzcocqgmsyel` — preflight must report 0 null parents.
4. Run SQL contracts on preview (includes second-active fail + post-dismiss/approve reopen).
5. Phase 2 mirror-only importer only after that.

## One-liner

> Phase 1 stores ColdLion licensor/property mirrors and typed review findings, and
> **enforces** every property’s exact-one licensor via `core.property.licensor_id`
> NOT NULL ON DELETE RESTRICT. Review queue allows **at most one ACTIVE finding**
> (`open`/`quarantined`/`conflict`) per source key while preserving terminal history,
> with a strict status/resolution/resolved-\* CHECK matrix. Apps still read `core.*`.
> No importer yet.
