---
issue: 2596
status: OPEN
owner: codex/handover-latency-plan
---

# Bounded shared-db handover implementation

## 0. Decisions only the owner can make

None are required to finish the requested planning deliverable. Implementation has not been requested in this planning session. When implementation is requested, follow the [standalone plan](../plan_bounded_session_handover.md). Do not treat a plan as authorization to change production, transfer the repository, alter branch protection, or take over a live orchestrator. If later proof establishes a settings change is necessary, prepare its exact diff and request that authorization at that point.

Already settled: preserve database safeguards; remove multi-hour handover waits; do not rebuild the document exemption already merged in PR #2592. No credential action is part of this work.

## 1. Application

POP Creations' canonical shared-database schema/coordination repository is `u2giants/shared-db`. This is repository maintenance, not schema-orchestrator work. GitHub main is authoritative.

## 2. Session objective

Review the latest named Codex and Claude sessions and produce an evidence-based plan to eliminate roughly two-hour handovers. Private transcripts were read in place; none were copied into this public repository. The plan identifies sources, timings, code, existing repairs and proposed acceptance.

## 3. Current state

Investigation completed against fetched main `bc4caafa`. Plan and this handoff are the deliverables on `codex/handover-latency-plan`; publication commit is the commit introducing these files. No implementation, runtime policy, database or infrastructure changes were made. #2596 tracks pending implementation. The canonical checkout's unrelated changes and local handoff commits were preserved. No sub-agents were used.

The specific contract/document contradiction is already fixed by `7325005b` / PR #2592. The remaining document closeout took 9m12s PR-open to merge; the final merge job was 87s. Codex's request-to-finished interval was 1h58m58s; Claude's request-to-handoff-merged interval was 1h33m56s. See plan sections 3–6 for timestamps, limitations and live GitHub evidence.

## 4. Failed approaches

The prior sessions added compulsory evidence JSON that invalidated their document exemption, cycled through reviewers, refreshed heads after main movement, and expanded closeout into repairs. The predecessor left an open marker pointing at a closed task. Do not repeat those approaches. The planning investigation initially saw a truncated app view; local structured transcript messages established the complete timeline. Live GitHub timing corrected an initial approximate twelve-minute statement to 9m12s.

## 5. Findings

Plan sections 5–6 contain code references. In particular, `evaluateWithoutRequiredList` waits on all reported checks even though the ephemeral database test is not in GitHub's eleven required contexts. The final merge is manual-dispatch-only. Ownership transfer is coupled to handoff merge, and checkpoint reconstruction is not yet bounded. Existing #1738/#1680 mechanisms are already landed and must be reused.

## 6. Exact next steps

After implementation is requested, read plan STATUS and sections 9–13. Start with whole-path classification fixtures; then truthful applicable CI plus automatic guarded dispatch; then durable checkpoint/fencing; then reviewer lifecycle/evidence reuse and cross-tool procedures; finally fault-injected and live timed acceptance. Each step has its gate in section 9. Re-resolve current main, #2596, #2318 and matching PRs before authoring; do not duplicate another session's repair.

## 7. Constraints

Separate current rules from proposed rules. In particular, transfer-before-document-merge is proposed, not currently permitted by this document. Use a fresh worktree, stage only owned files, preserve protected claims and production freezes, and keep exact-head authorization. Never rename operative plans as ordinary docs to evade classification. Do not create an orchestrator marker for this repository-maintenance work.

## 8. Access

Authenticated GitHub reads and Git were verified. Node tests and normal GitHub CI cover initial implementation. No database access is necessary. Cross-tool procedure/reviewer work belongs in ai-devops with its own worktree and instructions. No secret values or raw transcript exports are required.

## 9. Risks and completion

Risks and rollback are in plan section 13: event permissions, stale classification, crashes, old clients, active DB stages and service outage. The five-minute target is not a claim that external services can never fail. Planning is complete on commit/push; implementation and its live acceptance remain open under #2596. Delete this handoff only when the implementation obligation is completed or all obligations are preserved by a verified successor under the handoff retention rules.

## Handoff audit

1. A new developer can continue: sections 1–3 identify the system, request and baseline; section 6 links the executable phased plan.
2. Relevant context is preserved: sections 4–5 and plan sections 3–8 carry failed attempts, verified timings and already-landed fixes.
3. Execution detail is available: plan sections 9–13 specify files, tests, deadlines, access, risks and acceptance; this handoff does not pretend implementation is done.
4. Owner-decision sweep passed: section 0 explicitly distinguishes planning from future implementation and lists the conditional settings permission boundary also referenced in sections 7–9. No pending credential or production decision was inherited from the source transcripts.
