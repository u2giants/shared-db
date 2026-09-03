---
issue: 2160
status: OPEN
owner: claude/shared-db-orchestrator-priorities-bf651f
---

# Orchestrator marker #2121 — closeout

**Session:** `shared-db-orchestrator-priorities-bf651f-b2 [869201]`, route_id `local_7b61df8f-dabd-43d0-a1c2-019580845f08`
**Worktree:** `C:/repos/shared-db/.claude/worktrees/shared-db-orchestrator-priorities-bf651f`, branch `claude/shared-db-orchestrator-priorities-bf651f`
**Predecessor:** marker #2109 (`HANDOFF.d/2026-09-02T1709Z-edge-dev-claude-orchestrator-2109-closeout.md`, read end to end, deleted by this session)
**Closed:** 2026-09-03T02:35Z

## 0. DECISIONS ONLY THE OWNER CAN MAKE

Nothing in this list can be moved by a successor session. Do not re-ask the owner about them casually; raise them only when the work in front of you is actually blocked on one.

| Issue | Decision needed |
|---|---|
| #2110 | Production apply of the nine held migration versions. The earlier authorization was pinned to tip `912419b4` and is **SPENT**; it does not carry forward to any new tip. A fresh authorization naming the exact versions is required. |
| #1693 | Owner-only. |
| #870, #718, #696 | `security-settings`, route `owner-only`, all three blocked on an owner decision. |
| #1353 | Reduced to a future authorization: the `dflow_prod` cutover (row copy, secret rebinding, Cloud Run switch) needs the owner naming the exact resources in chat at the time it runs. The alarming original title was wrong and has been corrected — dev/staging/sandbox share one Supabase project; production is Cloud SQL. |

## Moving facts, re-checked at write time

| Fact | Value | Checked |
|---|---|---|
| `origin/main` tip | `bd00aaa796aac5949f04332b5748748644392aaf` | 2026-09-03T02:30Z |
| Max migration version on main | `20260902222649` | 2026-09-03T02:30Z |
| Author lanes | **5 of 8 occupied, 5 protected claims, 0 relinquished, 0 expired leases locked** | 2026-09-03T02:30Z |
| Concurrency cap | **FIVE** concurrent authors (AGENTS.md numbered rule 2, raised 2026-08-25). Lanes are therefore **AT CAP**, not idle. | 2026-09-03T02:30Z |
| Preview lock | free (0 refs) | 2026-09-03T02:30Z |
| Merge lock | free (0 refs) | 2026-09-03T02:30Z |
| Queue audit | no `REFILL REQUIRED` line — **no dispatchable migration-author work is waiting** | 2026-09-03T02:31Z |
| Open PRs | 7 (#2158 #2156 #2155 #2150 #2149 #2145 #2134) | 2026-09-03T02:30Z |
| Reviewer ref namespaces | assignments 728, verdicts 101, failures 235, replacements 229 | 2026-09-03T02:14Z |

## 1. What this session was doing, and why

Opened as successor to marker #2109 to run the orchestrator queue: classify open issues, dispatch structural work into migration-author lanes, and shepherd each resulting PR through governed two-reviewer review and Guarded Merge.

Two things dominated it. First, **the governed reviewer system was broken** and no PR in the repository could be reviewed at all — that had to be fixed before anything else could move. Second, once it was fixed, five author lanes were filled and five PRs were produced, none of which reached merge before the session ended.

## 2. What was actually done

**The reviewer system was repaired and proven live.** Issue #2152 to PR #2155. `listReviewRefsPaged` walked `git/matching-refs` with `?page=N`, but that endpoint **is not paginated at all** — it ignores `page` and `per_page` and sends no `Link` header, so every namespace over 100 refs threw and reviewer assignment was dead. Independently confirmed: `?per_page=5` on `db-review-assignments` returned all 726 rows, and `gh api -i` showed no `Link` header. The fix reads one request per call, refuses on a `Link` `rel="next"` if GitHub ever starts paginating, and caps at `REVIEW_REF_ROW_LIMIT = 1000` (floor 726 = today's largest namespace; ceiling 1000 = smallest hard REST result cap). Live before/after: OLD threw on both `db-review-assignments` and `db-review-verdict`; NEW returned 726/726 unique and 100/100 unique. **I verified it by using it** — drew both reviewer slots from the fixed worktree, which had been impossible an hour earlier.

**Five author lanes filled** (the cap). Issues #2123, #2136, #2138, #2146, #2147 all have open PRs. Two of those were dispatched only after I discovered my own stale belief that the cap was three (see section 9).

**Issues filed:** #2157 (reviewer-capacity fail-open), #2159 (`plm.source_resolution` accepts a bare `warner:` with an empty namespace because `%` matches zero characters), #2160 (this handover, with the outstanding-work checklist), #2161 (object-collision extractor exempts `create temporary table` but not the matching `drop table`), #2162 (reviewer pool down to three), #2163 (26 unclaimed staged files in the orchestrator worktree), #2164 (root `HANDOFF.md` pointer marker plus one stale `HANDOFF.d` file).

**Nothing was merged and nothing reached production.** No preview run, no promotion, no production write.

## 3. Preview and production

Preview lock free, never taken by hand. Merge lock free. No preview run was dispatched this session and no production apply was attempted.

**Re-derived at write time, and it corrects the predecessor:** issue #2118 (the production business-risk gate) is **CLOSED**, not open — the marker #2109 handover was written while it was still open and a successor reading only that file would inherit a block that no longer exists. The live owner-blocked promotion item is **#2110**, and the owner's nine-version authorization pinned to tip `912419b4` is **spent** and does not carry forward.

## 4. Half-finished or abandoned

**Six PRs are open and none is merged.** All six read `mergeStateStatus: BLOCKED` — that is normal and not a fault. The required status context `Migration guarded merge authorization` is posted **only** by the `workflow_dispatch` Guarded Merge workflow, which itself requires a durable APPROVE in **both** review slots at the exact head. So a PR sits BLOCKED until the two reviews exist, including a script-only PR.

| PR | Issue | Claim | Head at close | State |
|---|---|---|---|---|
| #2155 | #2152 | — | `6e2ed99759ccffb71e747b82e3fffe74ece134ee` | Fresh head. **Both slots must be drawn fresh at it before any review runs.** |
| #2156 | #2146 | #2153 | `b8ad9faec090a68fad5f1b5767c70ece30408ee0` | All 13 required checks pass. Needs two reviews. |
| #2158 | #2147 | #2154 | `87304ef3176c332a2a0f3a0821375c57ac167e7d` | All 13 required checks pass, `MERGEABLE`. Needs two reviews. |
| #2150 | #2138 | #2143 | `740491616c5dca9b1479903d9530dceaf220a492` | Revised. Needs two reviews. |
| #2149 | #2136 | #2142 | `0ec2e234d7b271796d0e9cb9359a498fbbc53371` | Revised. Needs two reviews. |
| #2145 | #2123 | #2144 | `003756fe559963bb5d2af3c938ee0ed4ee33b941` | **Jammed.** See section 7. |

#2134 is a repo-session PR, not this session's work. Do not touch it.

## 5. Queue seeded — every outstanding item has an open issue

| Outstanding item | Issue | Waiting on owner |
|---|---|---|
| Reviewer pager fix, PR #2155 | #2152 | no |
| Tier-1 character FKs, PR #2156 | #2146 | no |
| WildBrain vocabulary, PR #2158 | #2147 | no |
| `filter_effective_assets` regression, PR #2150 | #2138 | no |
| Factory-customer business path, PR #2149 | #2136 | no |
| Tier-2 promotion contract, PR #2145 (jammed) | #2123 | no |
| Reviewer-capacity fail-open | #2157 | no |
| `warner:` empty-namespace hole | #2159 | no (blocked on #2147) |
| Object-collision drop-table asymmetry | #2161 | no |
| Reviewer pool down to three | #2162 | no |
| 26 unclaimed staged files | #2163 | no |
| `HANDOFF.md` marker + stale handoff file | #2164 | no |
| This handover's own checklist | #2160 | no |
| Production apply of nine held versions | #2110 | **yes** |
| `dflow_prod` cutover authorization | #1353 | **yes** |
| Owner-only security settings | #870, #718, #696 | **yes** |
| Owner-only | #1693 | **yes** |

All five `needs-albert` rows already carry that label; none was added or removed by this session. Nothing outstanding exists only in this file's prose.

## 5a. What this session owns

Claims #2142, #2143, #2144, #2153, #2154 and orchestrator marker #2121. Each claim must be released with `--release-claim <n> --owner <owner> --confirm-finished` and a completion report (`--complete-work --issue <n> --report-file`) only after its PR merges. The marker must be closed at the end; closing it also unblocks the #1868 worktree reap (~200 worktrees).

## 6. What was about to happen next

Draw both reviewer slots at PR #2155's new head `6e2ed997…`, run two reviews, dispatch the Guarded Merge workflow, then repeat for #2156, #2158, #2150, #2149 — one merge at a time, since merge and promotion are serialised. #2145 last, after another merge moves main.

## 7. Blocked on

**PR #2145 is jammed by a head-wide verdict.** Slot 2 holds an APPROVE; slot 1 was drawn by `codex-gpt-5.6-sol`, which is structurally incapable of returning a verdict. `--replace-failed-reviewer` refuses with *"an existing verdict for the exact head forbids reviewer replacement"* — `hasVerdictForHead` is **HEAD-wide, not slot-wide**, so once any reviewer records a verdict at a head, no second slot can be drawn *or* replaced there. The only legitimate escape is to move the head: merge some other PR to main, run `gh pr update-branch 2145`, then draw both slots fresh at the new head. **Never hand-delete a `refs/db-review-active/*` ref and never post a synthetic verdict to free capacity.**

**The reviewer pool is down to three (#2162).** `codex-gpt-5.6-sol` is structurally unusable (fixed subcommands, no `--prompt-file`, can never be told the head SHA the verdict line must carry). `kimi-k3` is out until roughly 2026-09-08 on a genuine 7-day provider quota — `403 You've reached your weekly (7-day) usage limit` — while `ai-kimi doctor` still reports `auth OK`, because doctor does not test quota. Usable: `glm-5.3`, `grok-4.6`, `muse-spark-1.2-contributor`. **Review one PR at a time**; two concurrent PRs exhaust the pool.

**#2159 is correctly blocked** — its dependency #2147 is still open.

## 8. Sub-agents dispatched

### Agent `a2696bcf961285eda` — issue #2152 to PR #2155

- **Worktree:** `C:/repos/shared-db/.claude/worktrees/shared-db-2152-refs-pager`, branch `claude/2152-matching-refs-pagination`. **LIVE** — do not reap.
- **Asked to:** fix the broken reviewer ref pager described in #2152.
- **Did:** replaced the `page=N` walk with a single request per call plus a `Link` `rel="next"` refusal and a 1000-row ceiling. Then, in a second pass, hardened the `Link` parser itself: repeated header lines are now joined per RFC 9110 instead of being collapsed by `Object.fromEntries`, `title="rel=next"` no longer false-positives, and an unparseable `Link` value throws instead of reading as "no further pages". Head moved `25b5eebd…` to `6e2ed997…`. Tests 392 to 400, all pass.
- **Found:** it **corrected the issue's own premise.** #2152 prescribed walking the `Link` header; the endpoint has no `Link` header, so that prescription would have shipped dead code. It also proved that duplicated rows **never** reached a decision on the old code — the early return fired only on a short page, which against a page-1-repeating endpoint happens only under 100 refs, where one request already held everything; at 100+ it always threw. Raising the ceiling alone would have made duplicates reachable.
- **Deliberately did NOT:** touch issue #2157 (the fail-open bare `catch` in `reviewerCapacityReport`), because that is a separate defect with its own issue and folding it in would have widened an already-reviewed diff. Note `classification` does not consume `verdictPresent`, so the automatic classifier was never misled — the hazard is to a human reading the report.

### Agent `a5450879fa198af30` — issue #2146 to PR #2156

- **Worktree:** `C:/repos/shared-db/.claude/worktrees/shared-db-2146-tier1-character-fk`. Claim #2153, owner `claude-lane-2146-tier1-fk`, version `20260903014958`. **FINISHED.**
- **Asked to:** restore the missing `core.character` foreign keys on the three Tier-1 character tables.
- **Did:** restored all three with `on update cascade on delete restrict`. Nine mutation tests, all caught.
- **Found three contradictions and reported every one:** (1) the ORIGINAL declarations carried only `on delete restrict`, defaulting to `ON UPDATE NO ACTION` — so "same shape as the surviving tables" and "keep the original names" are **not** the same shape; it adopted the neighbour shape deliberately and flagged it for the reviewer rather than quietly picking one. (2) Three contract tests (`nbcu_landing_contracts.sql`, `opa_normalized_sync_contracts.sql`, `opa_property_character_landing_contracts.sql`) asserted the **opposite** and had to be inverted; the issue never mentioned them, and there is no equivalent assertion for `plm.pmt_character`. (3) `execute format(...)` was refused by the hash-bound production verification sidecar guard and was rewritten as static SQL.
- **Caveat it stated itself:** the fixture is a local PostgreSQL 18 cluster, so production RLS, grants and the `*_resolution_immutable` triggers were never exercised. Production read at the time: 190 / 9,613 / 124 rows, zero populated `core_character_id`, `core.character` empty.

### Agent `a6c122c2ad8dab64a` — issue #2147 to PR #2158

- **Worktree:** `C:/repos/shared-db/.claude/worktrees/2147-source-resolution-wildbrain`. Claim #2154, owner `claude-opus5-wildbrain-vocab-2147`, version `20260903015023`. **FINISHED.**
- **Asked to:** add `wildbrain` to the `plm.source_resolution` source vocabulary; then, in a second pass, clear a CI lease failure.
- **Did:** chose the plain token `wildbrain` over a namespaced form, on four lines of evidence — no `source_namespace` column exists on any of the eleven `plm.wildbrain_*` tables; `capture_id` is a snapshot identifier, not a namespace; there is one property through one portal; and `api.source_capture_inventory` already uses the bare token. Eight mutation tests, all caught, each failing for its own reason. Head at close `87304ef3176c332a2a0f3a0821375c57ac167e7d`; **all 13 required checks pass** and the PR reads `MERGEABLE`.
- **Found (1):** the `warner:` empty-namespace hole — `plm.source_resolution` accepts a bare `'warner:'` because `%` matches zero characters. Pre-existing on main, filed as **#2159** with `depends_on: 2147`.
- **Found (2) — it corrected my diagnosis of its own CI failure.** I sent it back believing the `create temporary table … source_resolution_vocabulary_probe` was the undeclared object. It is not: `check-pr-object-collisions.mjs` **already exempts temp tables deliberately**, with a comment explaining that session-local scratch is not a shared object. The claimed key came from the explicit `drop table` at the end of the verification block — **the exemption is written into the `create table` pattern only, and the `drop table` pattern matches regardless of temp.** The drop was redundant (the probe is `on commit drop`), so removing it leaves the extracted objects as exactly `table plm.source_resolution` and `column plm.source_resolution.source_system`, both covered by the one declared write. The verification block is otherwise unchanged. **This asymmetry is a real guard gap** — any author who cleans up explicitly hits it, and the refusal points at the claim rather than at the drop, which makes the obvious-but-wrong fix "widen the claim". Filed as **#2161**.
- **Deliberately did NOT:** narrow the #1285 verify-cost guard. That guard matches `into` beside a `plm` object, so `insert into plm.source_resolution` is refused outright, even though its own stated rationale is scan cost and a single-row `insert … values` is not a scan. Narrowing it would have meant editing a check script from inside a claim, which is banned. Worth its own issue if the successor agrees.
- **Also did NOT:** add the probe to the claim, or modify any check script — both were explicitly forbidden when it was sent back.

## 9. What was tried that did NOT work — MANDATORY

- **I believed the concurrency cap was three.** It is **five** (AGENTS.md numbered rule 2: *"SUPERSEDED 2026-08-14, RAISED 2026-08-25"*). I left two lanes idle while `--queue-audit` was printing `REFILL REQUIRED NOW: dispatch issue(s) #2146, #2147`. **Trust the audit's refill line over any remembered cap.** Memory written: `author-cap-is-five-not-three`.
- **I nearly ended a turn reporting "nothing needed from you"** while dispatchable work existed. The stop hook caught it.
- **kimi-k3, first refusal — my fault, not the provider's.** `REFUSED: review wrapper did not produce a recordable terminal verdict (exit 1)`, while `ai-kimi doctor` passed everything. Running the wrapper directly gave exit 126 and `kimi: Argument list too long`: **`ai-kimi` inlines the whole `--prompt-file` as an argv element**, and my prompt was 36 KB. This is the **fourth** distinct cause hiding behind that one generic refusal string. Keep review prompts under ~8 KB and tell the reviewer to take the diff from the checkout it is already sitting in — it is at the exact head anyway. A reusable 7.8 KB template was written this session as `review-2155-short.md` in the session scratchpad.
- **kimi-k3, second refusal — genuine.** Same generic string; `stream.jsonl.err` showed `provider.auth_error: 403 You've reached your weekly (7-day) usage limit`. **Always read the newest job's `stream.jsonl.err` under `~/.local/state/ai-devops/kimi/jobs/<job>/<caller>--<session>/` before recording any reviewer as failed** — the runner's refusal string never names the cause; that file always does.
- **`--replace-failed-reviewer` on PR #2145 slot 2 refused** with *"an existing verdict for the exact head forbids reviewer replacement"*. There is no way around it at that head. **Draw every reviewer slot BEFORE running any review** — the first recorded verdict locks the second slot permanently at that head.
- **PR #2158's temp-table workaround backfired.** Working around the #1285 verify-cost guard with a temporary table created a *different* CI failure in the lease check. Two guards, opposite requirements.
- **The orchestrator worktree's git index is not mine.** 26 files are staged there. The index matches neither `HEAD` (`42f84942`) nor `origin/main` (`bd00aaa7`) — 12 files differ from main, 368 insertions / 1436 deletions. **I left it completely untouched** and did not commit, reset, checkout or stash any of it, per the rule against broad staging or destructive git over unreviewed work. This handover was written from a clean separate worktree instead. A successor should identify the owning session before touching a single one of those files. Filed as **#2163**.

## 10. Facts that may already be stale

- All six PR head SHAs move the moment anyone pushes or runs `update-branch`. Re-read them.
- `origin/main` tip `bd00aaa7…` moves on the first merge.
- Reviewer ref namespace counts (728/101/235/229) grow with every assignment.
- kimi-k3's quota resets around 2026-09-08; re-test rather than assuming it is still out.
- Lane occupancy 5/8 changes as claims are released.

## 11. Secrets sweep

No credential, token, password or connection string appeared in this session's work, logs, commits or issue bodies. Nothing to store. The 1Password vault `vibe_coding` was not touched.

## 12. Documentation pass

No repository `.md` file needed a durable change: everything this session learned is either operational state (captured above) or reviewer-tooling behaviour, which belongs in session memory rather than in the repo. Memory files written or extended: `author-cap-is-five-not-three` (new), and `wrapper-caller-env-and-dead-reviewers` (the kimi argv limit and the weekly quota).

Root `HANDOFF.md` is the pointer form in content but **carries no `handoff-pointer: v1` marker on line 1**. It was deliberately not rewritten — that is a shared file and another session may be mid-edit. Filed as **#2164** together with the stale file below.

**Deleted:** `HANDOFF.d/2026-09-02T1709Z-edge-dev-claude-orchestrator-2109-closeout.md` — issue #2118 is CLOSED, the file was read end to end, and every live obligation in it is carried forward above.

**STALE, not mine to delete:** `HANDOFF.d/2026-09-02T1118Z-edge-dev-claude-orchestrator-2074-closeout.md` — its issue #2098 is CLOSED, but it runs 592 lines and I did not read it end to end, so I cannot certify that nothing live remains in it. Owner: `claude/shared-db-orchestrator-edf2f2`. Filed as **#2164**.
