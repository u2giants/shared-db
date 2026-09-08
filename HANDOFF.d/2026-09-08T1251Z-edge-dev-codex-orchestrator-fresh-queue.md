---
issue: 2552
status: OPEN
owner: shared-db.orch/agent-2449
---

# 0. Owner decisions

- Blocking: confirm whether #2403 may proceed only as a DesignFlow-owned test target; recommendation: keep it out of shared-db deployment until DesignFlow owner acknowledgement.
- Blocking: #2179 remains blocked on source/field decisions; recommendation: leave queued until those decisions exist.
- Already settled: #2449 production promotion completed 2026-09-08; #2509 production promotion completed 2026-09-08; #2550 is repository-maintenance only and merged.

# 1. Application

`u2giants/shared-db` is the governed source for shared Supabase database structure used by POP Creations applications. This coordinator session routes structural work to isolated agents; it does not directly author migrations or perform ad-hoc database writes.

# 2. Goal

The owner requested completion through highest-priority issue #2449 / PR #2452, the eight inherited structural items listed in transfer #2552, and the three queued priorities that remain after them.

# 3. Current state

- Live orchestrator marker is issue #2559, route_id `01a07e3d-df78-7ed0-bd62-d675f000158b` on EDGE-DEV.
- #2449 / PR #2452 is merged and production-complete. Production run `34224860332`; version `20260907200221`; issue and claim #2451 closed.
- #2509 / PR #2513 is merged and production-complete. Production run `34227235157`; version `20260907131728`; claim #2511 and issue #2509 closed; merge freeze released.
- #2550 / PR #2565 merged at main `6b516fd0224cddb44da6351c0ae3f3ecbcceb528`; no database or production action.
- #2356 / PR #2523 is refreshed at head `c4f0c50d9a3531304131c3ebbda0372bbc66ceb6`; its structural SQL is unchanged. Minimal restoration prerequisite #2573 / PR #2575 is open at `c3841f8dc0642e213cc3239ad83e718457b076d7`, all substantive checks green; guarded merge authorization/merge remain pending at closeout.
- #2503 is already claimed externally as #2574; read-only findings show seven sample relations are bootstrap omissions and `licensor_id` is an application-contract defect. Do not create a competing claim.
- Queue audit after #2449: 7/8 author leases occupied, 4 expired leases remain locked; expiry does not release protection.
- Active child agents: #2356/#2575 refresh worker and #2503 observation worker (the latter has finished). #2509 worker finished.

# 4. Failed attempts

- Preparing #2509 from stale canonical checkout was refused because the Muse verdict appeared unreadable. Repeating reviewer replacement was wrong; a fresh current-main worktree showed the verdict admissible after #2550 merged.
- Reviewer replacement commands with failed sequences 1786 and 1787 were refused; do not retry or mutate refs.
- #2356 initial refreshed structural PR hit the backdated-version guard because no approved historical-restoration entry existed; this led to #2573/#2575, which contains only evidence/registry and focused tests.
- #2503 first dispatch was refused because all eight author lanes were occupied; a later retry found claim #2574 already owned it.

# 5. Findings

- Current-main re-resolution is mandatory after every merge or production apply.
- Historical preview rebind is valid only with the manager-produced PREVIEW_READY record and original run map.
- Production apply evidence is immutable and must be passed to the workflow; never substitute a green CI run.
- #2503 canonical source locations are `supabase/ci-bootstrap/010_pre_adoption_baseline.sql` for the seven relations and migration `20260829004145` for the existing association table.

# 6. Exact next steps

1. Let the #2356 worker merge #2575 through its guarded path. Verify merge commit and current main.
2. Re-run manager selector/prep for #2356 from a fresh current-main worktree, then obtain exact-head review, preview, production apply, claim release, and issue closure. Gate: production ledger and catalog verify version `20260907152838`.
3. Recompute queue audit. Resume each inherited claim before work: #2493, #2501, #2506, #2439, and #2403 (owner acknowledgement required; no shared-db deployment for its separate DesignFlow test target).
4. After inherited work, recompute the three transfer priorities (#2543, #2357, #2179) from live queue state; process only dispatchable structural items and leave #2179 blocked if decisions remain absent.
5. At every phase end, re-read downstream plan phases and record drift before dispatching the successor.

# 7. Constraints

Use isolated current-upstream worktrees, preserve expired claims and refs, do not hand-delete reviewer or author refs, and do not bypass preview/review/production gates. Production and shared preview are serialized. Never expose the Supabase token; retrieve it through 1Password item `3t2xoqk5luyz7ffgdhj24gvtpq` in vault `vibe_coding`.

# 8. Access

GitHub CLI is authenticated as `u2giants`. Supabase access is available only by the protected 1Password pipe above. Manager mutations require the route_id in the marker. Current branch in the canonical checkout is `main`; pre-existing dirty files were not touched.

# 9. Risks

Counts, main SHA, queue ranking, and PR statuses are live and stale quickly. #2356 is blocked until #2575 is merged and its historical registry is accepted. #2503 may be owned by another coordinator agent. Do not assume the transfer document's old three-item ranking still matches the current queue.

## Agent reports

### issue_2509_prod_gate
- Asked to promote #2509 through governed production.
- Actually did: production run `34227235157` succeeded; version `20260907131728` verified; claim #2511 and issue #2509 closed; freeze released.
- Deliberately did not touch other streams.

### issue_2509_refresh
- Asked to resume inherited #2356, refresh onto current main, and take it through all gates.
- Actually did: opened #2573 / PR #2575 at `c3841f8d`; structural PR #2523 remains unchanged; CI was green except the then-pending ephemeral DB check, now reported complete by the worker.
- Worktree live/resumable; deliberately did not merge during #2509 freeze, now released.

### issue_2503_bootstrap_retry
- Asked to dispatch #2503 without conflicting with existing ownership.
- Actually did read-only contract analysis and found claim #2574 already owns it; made no files or database changes.
- Finished; deliberately did not create a competing claim.

Self-audit: sections 0–9 cover decisions, purpose, exact live state, dead ends, findings, gated next actions, constraints, access, risks, and each dispatched agent. The reciprocal instruction to re-read downstream phases is in step 6.5. This handoff is comprehensive for a fresh coordinator.
