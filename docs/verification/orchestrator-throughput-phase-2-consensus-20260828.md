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
| Kimi's execution-context denial would recur after generic doctor handling | Step 6 uses only the current assigning process's doctor result for one attempt, never a persisted ban |
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

## Fourth-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Live PR contexts, Python production checks and YAML jobs are different sets | Grok | live protection is authoritative only for PR requirements; no set equality; wait is forbidden from both enforcing sets |
| Early wait could still run `if: always()` apply-artifact upload | Claude | separate short-lived dependency job; preview job never starts while waiting |
| Waiting dispatch could hold the global workflow concurrency group | Claude | wait job emits metadata and exits immediately; reconciliation redispatches later |
| `review-wait` lacked durable order and independent waker | Claude | immutable wait refs; release plus Step 8 reconciliation re-enter guarded allocator |
| Context doctor had only a post-assignment entry point | Claude | factor read-only doctor-only function; run per candidate outside mutex before reservation |
| Process-local rule contradicted leftover durable/caller prose | Claude | root cause and Step 6 compatibility prose now consistently process-local |
| Manager `--flow-audit --json` still untested | Claude | manager CLI delegation and output contract test added |
| Reviewer names can alias one serialized wrapper | Claude | reservations keyed by canonical provider/wrapper execution identity, with display reviewer in payload |
| Cap test timing could assert eight before approval | Claude | production remains five until gate; parameterized fixtures test proposed eight beforehand |

## Fifth-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| A wait inside the existing workflow still holds its workflow-level concurrency group | Claude | new preview-only entry workflow; waiting never dispatches the shared preview/production workflow |
| Repeated waits could displace a pending real preview/production run | Claude | waits never enter that concurrency group; only ready state dispatches it |
| Production could accidentally use the wait route | Claude | entry workflow accepts preview targets only and rejects production |
| Wait wake could bind a stale PR head/bundle | Claude | every waker revalidates live head/bundle/eligibility; drift terminally supersedes and requeues current content |
| Immutable waits lacked atomic claim, terminal lifecycle and ref-safe ordering | Claude | mutex-allocated ref-safe sequence, create-if-absent claim, append-only outcome, fenced dead-claim recovery |
| Overflow reviewer policy was absent from the new eligibility seam | Claude | active tier first; approved overflow only with immutable proof all active keys unavailable; arbitrary inactive names fail |
| Phase C operator semantics were not synchronized to docs/skill | Claude | Phase C cut now requires same-phase AGENTS/docs/skill/drift updates |
| Default CI cannot read admin branch protection | Claude | live read is operator activation only; CI uses mocked fixtures |

## Sixth-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Workflow-to-workflow dispatch mechanism/ref/permissions were undefined | Claude | removed intermediary workflow; authenticated operator CLI dispatches exact current ref with readback |
| Preview input passthrough could drop recovery inputs | Claude | closed adapter covers every target input; discovery test fails on either-side drift |
| Preview wait wake had no owner | Claude | Step 8 invokes guarded dispatcher after dependency satisfaction |
| Automatic ready dispatch could replace a pending preview/production run | Claude | shared dispatch-admission ref plus zero queued/in-progress proof; preview and production use same guarded admission |
| Verdict landed but dead releaser could strand a reservation | Claude | verdict/PR-close/head-move are normal release proof; dead terminal releaser is recoverable separately from no-verdict recovery |
| Unreadable reservation truth had no shadow/activation rule | Claude | legacy derived state controls shadow; unreadable new truth never triggers paid overflow and fails closed after activation |
| Refreshed PR could lose its queue position | Claude | new bundle/head becomes next generation under the same primary sequence |
| Wait cycles could accumulate PR check runs | Claude | waiting is operator coordination only and creates no Actions/check run |
| New dispatcher was outside preview custody | Claude | corrected later: operator scripts are untrusted proposers; the workflow-side admission validator is the pinned enforcing producer |

## Seventh-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Run-state check would include continuous pull-request validation | Claude | admission checks queued/in-progress `workflow_dispatch` runs only |
| Production did not own the same dispatch admission path | Claude | shared dispatcher owns both sanctioned preview and production; preview front end calls it |
| Shared admission lock lacked allowlist/recovery | Claude | both recognized-kind lists updated; exact-payload terminal/dead fenced recovery specified |
| Operator local bytes were not proven by producer custody alone | Claude | clean worktree plus exact `origin/main` blob proof, immutable admission record and explicit executable discovery |
| Stale workflow-wait wording contradicted operator-state redesign | Claude | all waiting language now says no run/check/artifact |
| Crash between superseded outcome and successor wait could lose issue | Claude | successor-first rollover under mutex plus two-generation recovery/failure injection |
| Ready preview and reconciliation dispatch tests were missing | Claude | exact one-lock ready-preview test and reconcile dispatch/busy/recovery cases added |

## Eighth-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Editing concurrency could collapse PR validation groups | Claude | existing expression and `cancel-in-progress: false` preserved verbatim and statically tested |
| Unauthorized dispatch isolation could weaken serialization | Claude | no concurrency regrouping; first dispatch guard fails before target/lease work |
| Admission record had no namespace/lifecycle | Claude | immutable `refs/db-dispatch-admissions/<id>` plus terminal outcome; lock remains separate/recoverable |
| Operator-executable inventory had no file | Claude | `config/orchestrator-operator-executables-v1.json` created and discovery-tested |
| Local script cannot securely attest its own bytes | Claude | scripts are untrusted proposers; enforcing workflow revalidates all target/ref/inputs; no false producer-custody claim |
| Production caller/procedure was missing | Claude | shared helper supports both targets and Phase C updates the manual production procedure |
| New config files would fail completeness gate | Claude | each is pinned or precisely exempted and filesystem-completeness test stays required |
| Second head drift could leave no current wait generation | Claude | recovery snapshots newest live state and exits only with exactly one current generation |

## Ninth-round objections and disposition

| Objection | Source | Disposition in current plan |
|---|---|---|
| Four target jobs had no shared admission-gate location | Claude | first workflow-dispatch-only step in existing shared `validate` job; all target jobs already depend on it |
| New gate job would break literal production `needs` invariant | Claude | no new job/needs edge; existing literal list remains and is tested |
| Admission check could displace deliberately-first target steps | Claude | upstream validate step; target-ref and exact-confirmation remain first in their own jobs |
| Empty unauthorized dispatch could stall/replace sanctioned group | Claude | empty admission gets unique unauthorized group; PR branch and sanctioned global group preserved |
| Ambiguous dispatch lost `UNVERIFIABLE` rule | Claude | unreadable/ambiguous dispatch, admission or validation is explicit exit 2 |
| Production procedure file was unnamed | Claude | `docs/production-promotion-procedure.md` is a Phase C deliverable using the shared helper |
| Ledger contradicted operator trust boundary | Claude | older disposition corrected; workflow validator, not operator script, is pinned authority |
| Admission validator file/tests were unnamed | Claude | named validator and test plus existing production guard test cover all four target paths/concurrency |

## Rejected alternatives

- Release blocked claims, raise the cap as a substitute for decoupling, parallelize database writes, reuse SQL-only evidence, trust path names alone, time-delete mutexes, add exclusive-stage heartbeat, build a general SQL analyzer, or accept production apply without verification.

## Unresolved objections

- Pending fresh Grok 4.6 and Claude Opus 5 review of the replacement design. The user explicitly authorized a new Grok session after the prior session's rebuttal ceiling.

## Evidence still needed

- Same-head Grok and Claude approval of the read-only selector/manual-dispatch boundary before final merge.

## Last verified path state

- Initial external reviews read commit `1eacdacd52a5d6bbd212f718967391df1381138d` and rejected it.
- Grok's prior-session last approved head was `18cdcba`; Claude's latest rejected head was `1302d03`. The automatic-dispatch design has now been removed; the replacement revision is pending fresh same-head review.

## Replacement design after the exhausted first Grok debate

The user explicitly authorized a fresh Grok session. Codex replaced, rather than patched, the disputed automatic dispatcher. Phase 2 now ends at a read-only route selector and idempotent `PREVIEW_READY` work item. It creates no Actions run/check, changes no workflow concurrency/permissions/inputs, and leaves the incident-derived manual preview/production dispatch procedure intact. Automatic behavior is limited to dependency detection and waking the live sole-orchestrator task with exact current evidence.
