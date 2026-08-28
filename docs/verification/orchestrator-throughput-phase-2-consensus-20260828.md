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

## Claude second-round objections and disposition

| Objection | Disposition in current plan |
|---|---|
| Required `check-migration-pr-lease.mjs` consumer was omitted | Step 2 and §10 now keep relinquished/expired claims red until guarded resume plus renewal |
| Coordination events had no explicit writers or audit CLI | Step 2 names exported writers and `coordination-audit.mjs`; no second store |
| Six-reviewer prerequisite cannot be met by the four-provider live roster | §8/§13 and handoff require Albert to approve the exact two qualified providers before cap activation |
| Kimi's durable caller-specific denial would recur after generic doctor handling | Step 6 adds narrow caller/execution-context eligibility without globally shrinking coverage |
| Existing workflow test set was incomplete | §10 names the exact nine-suite workflow baseline, including lease, events and coordination scenarios |
| A neutral wait could become a skipped required context | Step 5 requires the wait context absent from Python `REQUIRED_CHECKS` and managed branch protection |

Plan and handoff prose are explicitly non-authoritative at runtime; versioned code/config and synchronized standing instructions remain policy inputs.

## Third-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Execution-context denial could become a standing caller/provider ban | Grok, Claude | current-process doctor result only; no persisted ban/TTL; later clean contexts remain eligible |
| Preview wait could false-green a missing/skipped required check | Grok, Claude | wait only on `workflow_dispatch`; required PR jobs unchanged; live protection comparison; no lock/apply artifact |
| Undefined `idle` capacity state could bypass guarded relinquishment | Grok | removed as fence state; dashboard-only label still counts active capacity |
| Cap 8 can exceed concurrent reviewer supply | Claude | explicit `review-wait`; all-busy never returns a reserved reviewer; cap and reviewer supply are separate |
| Retired GLM label is not an independent provider | Claude | exact recommendation must contain distinct provider/wrapper identities and at least one genuinely new provider |
| Existing manager tests hard-code cap/roster | Claude | §10 explicitly updates those assertions while preserving all safety coverage |
| Static branch-protection fixture is not live truth | Claude | authenticated live read is mandatory and unreadable/inconsistent state is `UNVERIFIABLE` |
| Owner gate absent from rollout/definition of done | Claude | repeated in Step 10 rollout and definition of done |
| AGENTS/skill drift could span phases | Claude | matching skill/drift change is part of Phase A and blocks its fresh-session cut |
| `--flow-audit --json` lacked a direct test | Claude | explicit coordination-audit CLI test added |

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
