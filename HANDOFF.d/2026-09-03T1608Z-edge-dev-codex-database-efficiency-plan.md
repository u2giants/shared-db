---
issue: 2209
status: OPEN
owner: codex/database-efficiency-plan-20260903
---

# Database efficiency and Data API security plan handoff

## 0. Decisions only the owner can make

### Blocking later irreversible actions

1. **Each production structural promotion needs Albert's authorization for that exact reviewed change.** Recommendation: approve in bounded batches only after preview, exact-head review, rollback proof, and application smoke evidence. This blocks production portions of plan Steps 5–6, not read-only investigation or preview work.
2. **Leaked-password protection needs explicit authorization as an Auth platform change.** Recommendation: enable it only if the live plan supports it and the protected test-account flow proves no enrollment/reset surprise. This blocks only that setting in Step 6.

### Raise immediately if discovered

If Step 2 proves unauthorized anonymous or ordinary-user access, present the whole reproduced access list to Albert in one message with the recommended containment; do not wait for the performance phases.

### Already settled — do not re-ask

- 2026-09-03: no index on the four #1966 tables is dropped before its observation window closes on 2026-09-17.
- 2026-09-03: no statistics privilege escalation; baseline-plus-delta replaces the refused reset.
- Standing: structural changes route through the shared-db orchestrator; application batching/scheduling changes remain in their application repos.
- No owner decision is needed for read-only Steps 1–3 or ordinary authorized application fixes.

The next session must consolidate any newly discovered owner decisions into one message and add them here and in the plan rather than asking one at a time.

## 1. What this system is

`u2giants/shared-db` is the canonical structure and contract repository for the shared POP Supabase/PostgreSQL backend used by CRM, DAM, PM/PIM, DB Data Admin, and PLM. The implementation plan is [`../plan_database_efficiency_and_api_security.md`](../plan_database_efficiency_and_api_security.md). Structural work uses migrations and the live orchestrator; application write-path fixes use their owning repositories.

## 2. What this session set out to do

Albert asked for a comprehensive implementation plan covering the Supabase dashboard AI's performance, resource-use, and security recommendations. The objective was to make the work executable by fresh sessions without turning generic advisor output into unsafe bulk changes.

## 3. Current state

- Plan, router entry, tracking issue #2209, and this handoff were created in isolated worktree `C:\repos\shared-db-plan-db-efficiency-20260903`. PR #2210 passed every check, received an exact-head Muse approval, and merged through guarded run `33778748037` as `5c3bf67e767b6fcd85062f9cb98805535498d17f`.
- Production target was re-verified read-only as `https://qsllyeztdwjgirsysgai.supabase.co`.
- Relation sizes, tuple/maintenance counters, expensive function statistics, advisor census, RLS state, and direct browser-role table privileges were read. No rows, schema, grants, settings, counters, infrastructure, or application code were changed.
- The planning deliverable is committed, pushed, reviewed, and merged. No deployment applies to documentation. The open implementation begins at plan Step 1; issue #2209 stays open until the program is completed or every obligation is transferred to a separately owned issue.

## 4. What did not work

1. Querying `pg_stat_statements_info` without its installed schema failed because the unqualified relation does not exist. The useful statement statistics were recovered read-only from `extensions.pg_stat_statements`; no capability was removed.
2. SQL `current_setting('pgrst.db_schemas', true)` returned NULL, so SQL alone cannot prove the exposed API schema list. The plan requires Management API/dashboard configuration plus bounded HTTP tests.
3. The dashboard AI's “127 RLS-disabled exposed tables” conclusion did not reproduce in the current advisor census. Treating it as fact was rejected; the plan distinguishes RLS flags, grants, exposed schemas, and actual HTTP behavior.
4. The shared checkout is 588 commits behind and contains extensive untracked work from other sessions. It was left untouched; this task uses an isolated current-main worktree.

## 5. Root causes and key findings

- Live size and expensive-function figures substantially reproduce, including cumulative totals for rebuild, clear, count, and materialized-view refresh operations.
- Cumulative counters do not provide incident causality or comparable savings without a timestamped baseline/delta.
- Current advisors report 426 unindexed foreign keys, 763 unused indexes, 22 duplicate indexes, 68 RLS auth-init notices, 125 overlapping permissive-policy notices, and a large privileged-object security worklist—not the alleged 127-table notice.
- Several large named tables have fresh vacuum/analyze activity, while other statistics counters are visibly unreliable. “Autovacuum is broken” is not established.
- #1966, #2196, and #2043 already own important pieces and must be reused, not duplicated.

## 6. Exact next steps

1. Start a fresh isolated repo-maintenance session at plan Step 1. Capture the privacy-safe reproducible baseline and reconcile every claim. **Worked when:** every claim is confirmed, not reproduced, unknown, or superseded with rerunnable evidence.
2. Execute plan Step 2 before performance mutations. Prove API reachability by catalog plus bounded HTTP behavior. **Worked when:** every alleged exposure has positive/negative evidence without returned row contents.
3. Follow the plan's phase boundaries and owner routing. **Worked when:** the STATUS table stays current and every change has one owner, evidence gate, rollback, and live acceptance.

## 7. Constraints and gotchas

- Read `AGENTS.md`, then the plan STATUS table. Do not load unrelated handoffs.
- The plan authorizes no database or platform change.
- Re-resolve the live orchestrator marker before routing structural work.
- Never use the dirty shared checkout, edit applied migrations, reuse versions, reset counters, or disturb #1966's window.
- No private/licensed rows, secret values, or raw access responses in this public repo or external reviews.
- Preserve capabilities; disabling Realtime, policies, rebuilds, search, or projections is not a fix.
- Rulebook files require the repository's normal review path even though the diff is prose.

## 8. Access and environment

- Worktree/branch: `C:\repos\shared-db-plan-db-efficiency-20260903`, `codex/database-efficiency-plan-20260903`.
- GitHub CLI is authenticated for `u2giants/shared-db`; issue #2209 exists with `db-work` and a documentation/repo-maintenance scope block.
- Supabase connected read-only tools are production-bound; call `get_project_url` each read session.
- Protected refs and Supabase CLI credentials are resolved via `ai-private-config` and 1Password vault `vibe_coding` item titles named in the `codex-shared-db-change` skill. Never output values.

## 9. Open questions and risks

The open technical questions are collected in plan §13. The main risks are access outage/escalation, removal of a rare-workflow index, worsened write amplification, projection staleness, lock/storage growth, and incomparable before/after windows. The plan supplies a forward rollback and acceptance requirement for each. No additional owner decision is hidden in this section.

## Handoff self-audit

1. **Can a new developer continue without context? Yes.** §§1–3 define system, goal, worktree, branch, target, evidence, and landing state; §6 gives ordered next actions and gates.
2. **Can they continue as effectively as this session? Yes.** §§4–5 preserve failed checks, corrected conclusions, live census, counter limitations, and existing issue ownership; the linked plan carries full implementation detail.
3. **Are all execution details present? Yes.** §§6–9 cover actions, verification, constraints, access, risks, and open questions; commit/push/merge status is explicit.
4. **Would Albert see every decision from §1–§9 by reading §0? Yes.** The only decisions are exact production promotion, Auth leaked-password protection, and immediate handling of a reproduced exposure; all are consolidated in §0 with recommendations and blocking scope. The remaining items are already settled or technical evidence questions.
