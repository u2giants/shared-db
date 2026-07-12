# DesignFlow segregation classify — review handoff

**Status:** Artifacts prepared; classifier **not run** yet (awaiting owner review).

**Date prepared:** 2026-07-12

## What was prepared (no DB execution, no commits)

| Artifact | Path |
|---|---|
| Always-on Cursor gatekeeper | `popcre/.cursor/rules/shared-db-gatekeeper.mdc` + same file in six `designflow-*` repos |
| 103-table map | `popcre/scripts-superbase/designflow-segregation-map.json` |
| Classifier (review outputs only) | `popcre/scripts-superbase/Classify_Designflow_Segregation.ps1` |
| Apply wrapper (DryRun default) | `popcre/scripts-superbase/Apply_Designflow_New_Moves.ps1` |

## After you approve and run the classifier

1. Run `.\scripts-superbase\Classify_Designflow_Segregation.ps1` (writes under `C:\db-backups\Prod_Backup_<date>\`).
2. Review:
   - `segregation_merge_review_*.md` — MERGE / TYPED_IMPORT (manual)
   - `segregation_new_moves_*.sql` — NEW only (rename + SET SCHEMA candidates)
3. Prefer promoting NEW moves as a timestamped migration in this repo (`supabase/migrations/`) against **preview** first, per `AGENTS.md` — not a one-off production apply.
4. Update this note (or `designflow-schema-segregation.md`) with live NEW vs MERGE counts from the CSV.

## Gatekeeper note

The rule file already existed on `origin/sandbox-albert` in the six DesignFlow repos. It was also copied into the workspace root and local checkouts for always-on Cursor loading. Merging that rule onto `main`/`develop` in those app repos is still a separate git step (not done here).
