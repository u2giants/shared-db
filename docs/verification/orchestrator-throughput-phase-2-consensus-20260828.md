# Orchestrator throughput Phase 2 — consensus ledger

**Plan:** [`../../plan_orchestrator_throughput_phase_2.md`](../../plan_orchestrator_throughput_phase_2.md)
**Issue:** #1738
**Starting commit:** `1eacdacd52a5d6bbd212f718967391df1381138d`
**Reviewers:** Codex, Grok 4.6, Claude Opus 5
**Status:** debate in progress; initial revision rejected by both external reviewers

## Agreed decisions

- The transcript's root cause is coupling between claim protection/capacity, reviewed content/integration head, preview order/failure state, and route shape/late enforcement.
- Protected claims must never be released merely to free author capacity.
- Preview, merge and production writes remain single-holder.
- Review reuse requires a content-addressed bundle plus successful current-head integration proof; SQL-only or filename-only reuse is unsafe.
- Ambiguous/unavailable classification is `UNVERIFIABLE` and repeats full evidence.
- `WAITING` is coordination state, never GitHub success or apply/rebind proof.
- Required reviewer coverage is unchanged; `REVISE` is never replaced.
- Exclusive-stage heartbeat/renewal remains rejected.
- Phase 1 remains the truth/measurement foundation; Phase 2 does not duplicate it.

## Initial material objections and disposition

| Objection | Source | Disposition in revised plan |
|---|---|---|
| Wrong/nonexistent function anchors and fixed-five queue geometry | Claude, Grok | corrected §5/Step 2 with real functions and >cap protected-claim tests |
| Existing `db-author-lease` semantics could be confused with capacity | Claude, Grok | capacity state is explicit; clock expiry frees neither claim nor capacity |
| New locks omitted stale-recovery allowlist and duplicate test | Claude | Step 2/6 and tests require both updates |
| Existing `db-coordination-events.mjs` omitted | Claude | reused as sole lifecycle store in Steps 1/2/8/9 |
| Node qualification could duplicate Python risk/catalog rules | Claude | Step 7 specifies thin Node/Python diagnostic boundary and exit 2 |
| Five-to-eight owner instruction conflicted with Phase 2 | Claude | instruction incorporated: eight active leases after six-reviewer prerequisite |
| `updateRef` is not compare-and-swap; heartbeat does not exist and is unsafe | Grok | Steps 6/8 use create-if-absent or short mutex; no exclusive heartbeat |
| Global invalidator set and evidence-reuse authorization were open-ended | Grok | versioned discovered inventory plus closed current-head CI/merge-base/bundle contract |
| #1713 disjoint merge evidence was unspecified | Grok | real `ddcdd5da` file set embedded in plan and fixture requirement |
| Preview `WAITING` could accidentally satisfy required checks | Grok | explicitly non-success/non-artifact; consumer tests required |
| Doctor-before-assignment could shrink reviewer coverage | Grok | local doctor remains post-assignment local-dependency path |
| Auto-refill relied on nonexistent heartbeat/stale marker | Grok | explicit live-orchestrator reconciliation; no marker means no mutation |

## Rejected alternatives

- Release blocked claims, raise the cap as a substitute for decoupling, parallelize database writes, reuse SQL-only evidence, trust path names alone, time-delete mutexes, add exclusive-stage heartbeat, build a general SQL analyzer, or accept production apply without verification.

## Unresolved objections

- Pending Grok and Claude re-review of the revised plan.

## Evidence still needed

- Re-review verdicts on the current revised tree.
- Focused existing manager/exclusive-lease test baseline before final merge.

## Last verified path state

- Initial external reviews read commit `1eacdacd52a5d6bbd212f718967391df1381138d` and rejected it.
- Revision is on branch `codex/issue-1738-phase2-consensus`; reviewers must re-read the plan, handoff and this ledger on every rebuttal.
