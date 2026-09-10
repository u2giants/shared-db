---
issue: 2326
status: OPEN
owner: codex/issue-2326-step3-phase
owner_branch: codex/issue-2326-step3-phase
handoff_branch: codex/issue-2326-step3-closeout
created_at: 2026-09-10T19:32:49Z
---

# Database efficiency and Data API security — Step 3 continuation

## 0. Purpose and current stop point

This handoff closes the session without starting new database work. The next session must finish the existing evidence-only Step 3 pull request, then continue the programme only through its stated gates. No database, preview, or production action occurred in this session.

The active deliverable is PR #2684, `codex/issue-2326-step3-phase`:

- https://github.com/u2giants/shared-db/pull/2684
- current PR base at handoff: `4bffc3894c6fa446a7853276f4a62b31ef3315a1`
- current PR head at handoff: `bba1b6c19c53ce8db81bc2e9fd234c6f3ddcddff`
- PR state: OPEN and BLOCKED.

It updates the Step 3 STATUS row and supplies `docs/verification/database-efficiency/20260910T140913Z/step-3-closeout.md`. It does not make a structural database change, does not close issue #2326, and must keep issue #2662 open and unscheduled.

## 1. Live evidence at handoff

The current `Agent work contract` check is the only failed automated check. Its exact cause is mechanical: the completion report says the changed files are the contract, plan, and Step 3 evidence document, but Git correctly also sees `.agent/completion.json`. Add `.agent/completion.json` to the report's `files_changed`, validate, amend the existing implementation-head evidence as the contract requires, and force-push only after re-checking `origin/main` and the PR head.

All other listed automated checks for `bba1b6c19c53ce8db81bc2e9fd234c6f3ddcddff` passed. Database preview and production jobs were skipped because this is evidence-only work. No durable review approval exists on that exact head.

The currently recorded reviewer assignments are Gemini 3.8 Flash High, sequence 2214, and Grok 4.6, sequence 2215. Grok was started for the current head. Gemini refused to start because an earlier active/recovery-required repository session exists. Diagnose that active wrapper session before replacing or redrawing anything. Never count a review on a prior head after an amend or rebase.

## 2. Required reading and lane

Before acting, read in this order:

1. `AGENTS.md`.
2. `HANDOFF.d/2026-09-10T0450Z-edge-dev-claude-five-oldest-issues.md`, especially sections 8 and 9.
3. `plan_database_efficiency_and_api_security.md`, STATUS table first. Step 1 and Step 2 are authoritative and must not be re-derived.

Then run `node scripts/check-orchestrator-marker.mjs` before any other work. At handoff the marker is held by issue #2669 (`shared-db.orch EDGE-DEV succ-2629`), so this remains repository-maintenance work, not an orchestrator task. Work only in the existing dedicated worktree or a new current-upstream worktree; never edit the landing checkout at `C:\repos\shared-db`.

## 3. Exact Step 3 completion procedure

1. Fetch `origin/main`, inspect PR #2684 base/head/checks/reviews, and inspect the existing worktree status before editing.
2. Correct the one completion-report file-list mismatch, run only the targeted contract validation and relevant documented checks, amend/push the evidence pair according to the contract protocol.
3. If main changed, follow the guarded-merge race sequence from the predecessor handoff: rebase current main; resolve `.agent` carefully (during rebase, `--theirs` is this branch's commit); rebind the contract/completion evidence to the new base and exact head; force-push; then acquire two reviewer slots and run both reviews concurrently.
4. Obtain two durable reviewer approvals on the final exact PR head. A stale review is not an approval.
5. Re-read `origin/main` immediately before dispatching the guarded merge. If it moved, repeat the rebase/evidence/reviewer cycle; do not merge against a stale base.
6. Guarded-merge PR #2684, confirm merged state and merge commit, then confirm the Step 3 STATUS row and evidence artifact are on `main`.

Keep the PR body as `Tracks #2326 Step 3 evidence delivery`; do not change it to `Closes #2326`, because #2326 remains the umbrella programme and the handoff guard then adds unrelated retirement obligations.

## 4. What Step 3 proves and what it deliberately does not

The Step 3 document reconciles the previously captured call graph with separate landed outcomes. It treats the 181-second `asset_effective_tags` population as a one-off event and identifies recurrent effective-tag churn as trigger delete/insert activity. It preserves unresolved measurements instead of claiming completion: changed-row count for `clear_style_group_batch`, the embedding lease/error path, WAL delta and transaction duration, write-side plans rejected by the read-only identity, and materialized-view per-statement/reader-lock timing.

The document records related outcomes for #2213, #2214 and #2408. Issue #2215 relied on #2212 / PR #2339 and has no standalone migration. It is evidence closure for the declared Step 3 scope, not a claim that the entire programme is production-complete.

## 5. Programme work still open after Step 3

Steps 4 through 8 remain open. Follow the plan in order and do not collapse the gates:

- Step 4: baseline and maintenance evidence.
- Step 5: each structural remedy must be a separately scoped `db-work` issue and governed structural delivery; no bulk fix.
- Step 6: privileged API and Auth validation. Changing the leaked-password setting requires Albert's separate explicit authorization.
- Step 7: replication attribution.
- Step 8: final reconciliation.

Production is not 100% resolved or live merely because Step 3 merges. Structural promotion requires the normal preview, exact-head review, and a separate current-chat owner authorization for each exact production action/resource. Do not perform a production write based on this handoff.

## 6. Issue #2662 boundary

Issue #2662 contains a live, unremediated cross-application read path that the Step 2 report names publicly. Albert authorized publication and explicitly directed that remediation be dealt with later. Do not close it, schedule it, or begin work on it without asking Albert.

## 7. Prior failures worth avoiding

- Use task class `reviewer-safety` for the Step 3 plan/evidence PR; `repo-maintenance` was rejected by the gate.
- Do not rely on a no-output local test invocation as success proof; use targeted validation and current CI results.
- Do not reuse stale reviews after any rebase or amended head.
- `--replace-failed-reviewer` is non-idempotent. Capture and inspect output once; do not repeat it casually.
- Main moves frequently. Current facts in this document are a snapshot, not authority; refresh them before each consequential action.
- The canonical checkout has unrelated concurrent changes. It is landing-only.

## 8. Owner decisions needed later

No owner input is needed to complete the existing Step 3 evidence PR once the normal gates clear.

For the request to make the full programme live in production, Albert must authorize each exact future production action/resource in the current chat after preview and review evidence exists. The next session must not infer blanket production mutation permission from this handoff.

Albert also needs to choose when issue #2662 becomes active work. Until then, leave it open and unscheduled.

## 9. Session audit and safe cleanup

No database interaction or database mutation was performed. No secrets, row data, licensed material, preview credentials, or production credentials were copied into this handoff. The session's changes were limited to the existing evidence PR and this handoff record.

The original dedicated worktree `C:\repos\shared-db-worktrees\issue-2326-step3-phase` must be retained because PR #2684 is still open. The handoff worktree may be removed only after this documentation PR is confirmed merged and through the repository cleanup procedure.

Audit answers: the delivery is not complete; the exact blocker is the PR #2684 completion-report file-list mismatch plus pending exact-head reviews; #2662 remains open by owner instruction; no production claim is made; and the next safe action is the targeted PR repair described in section 3.
