---
issue: 2118
status: OPEN
owner: claude/orchestrator-2109-closeout
---

# Orchestrator marker #2109 — closeout

**Session:** `shared-db.orch edge-dev 14be64`, route_id `local_2632c743-a238-49c0-b467-cfdf9fdeaee2`
**Predecessor:** marker #2074 (`HANDOFF.d/2026-09-02T1118Z-edge-dev-claude-orchestrator-2074-closeout.md`)
**Closed:** 2026-09-02T17:09Z

## Moving facts, re-checked at write time

| Fact | Value | Checked |
|---|---|---|
| `origin/main` tip | `af919ec5ab15fd6c40044dc413c8f1dc66beca0f` | 2026-09-02T17:07Z |
| Max migration version on main | `20260902062827` | 2026-09-02T17:07Z |
| Author lanes | 0 of 8 occupied, 0 protected claims, 0 expired leases locked | 2026-09-02T17:08Z |
| Preview lock | free (no `refs/db-preview-lock/*`) | 2026-09-02T17:08Z |
| Merge lock | free | 2026-09-02T17:08Z |
| Queue audit | `fullyAudited: true`, `malformed []`, `unclassified []`, `dispatchable []`, `emptyLanes 8` | 2026-09-02T16:55Z |
| Worktrees under `.claude/worktrees/` | ~200 | 2026-09-02T17:07Z |
| Open PRs | 7, all repo-maintenance (#1957 #1956 #1954 #1951 #1950 #1946 #1935) | 2026-09-02T17:07Z |

**The empty lane is PROVEN, not assumed.** No structural work exists in this repository right now. Every open item is repo-maintenance, documentation, curated master data, owner-only, or structural-but-blocked (#1671, #2045, #2110).

## 1. What this session was doing, and why

Opened as successor to marker #2074 with three standing instructions from Albert: work the open HANDOVER issues, do not re-ask him about #2101 (skip), #2102 (change it) or #2103 (scrub), and prove preview state before any promotion because #2108 recorded it as unknown.

## 2. What was actually done

**PR #2114 — merged.** `af919ec5ab15fd6c40044dc413c8f1dc66beca0f`, via guarded merge run `33654323886`. It fixed SQL quoting in the catalog verifier and, more importantly, an honesty defect: a behavioural query that *errored* was being rendered as `MISSING`, which reads back as a proven absence of the contract. It now distinguishes `ERROR` from `MISSING`.

Three heads, three APPROVEs, each bound to its exact head SHA:

| Reviewer | Head |
|---|---|
| muse-spark-1.2 | `ad8e180d` |
| grok-4.6 | `13724ad7` |
| glm-5.3 | `d8092295` (durable ref `refs/db-review-verdicts/2115-2114-d8092295...` to `91ed1cc3d036a68655cac4c9794a4cb0a009c3e7`) |

Two guard files were re-pinned as part of it, each only after proving the re-pin was safe rather than convenient:

- `docs/verification/throughput-guard-truth-baseline-20260828.json` — `detector_source_sha256` changed from `107078d8...` to `f659e6b0...`. **Safety proven first:** the detector was re-run live across 603 migrations and reproduced all 88 recorded matched paths with identical version and marker count, zero mismatches. Nothing else in the file was touched.
- `docs/verification/throughput-guard-truth-audit-20260828.json` — two enriched call sites added, one superseded entry dropped, `call_site_count` 232 to 233, `call_site_sha256` `4652270f...` to `e7fc0c17...`. Minimal 16-insert/9-delete diff.

**Issues closed:** #2115 (with full evidence), #2098 (all three owner decisions answered and acted on), #1864 (already done — see section 9).

**Issues filed:** #2116, #2117, #2118 (see section 7).

**Queue repaired.** #2104 and #2106 carried `route: repo-session`, which is not a valid route and made the audit refuse to certify the queue; #2116 and #2117 had no scope block; #2110's structural block listed no write. All five fixed. `EMPTY LANE NOT PROVEN` is gone for the first time in several sessions.

**Owner ruling recorded on #1353** — see section 9.

## 3. Preview and production

**Preview:** proof run `33646808518` succeeded (digest `sha256:1ae69ac2f3d3f26404a2c6aba61f5d0f26444c6c1c1fbfde17cc854bc5ba5758`). The preview lock is free and was never taken by hand. Preview is **not** clean in the sense of empty — it holds a full production clone plus whatever the ColdLion parallel-run and alert-monitor workflows put there today (runs `33642036064`, `33645666327`, both green).

**Production: NOTHING WAS APPLIED.** This is the single most important fact in this handover.

Albert authorized a nine-version promotion in chat at main tip `912419b4fee0dbb4077e657aae0fb120f69b908a`. The first version, `20260901142825` (PR #2057), was refused twice by the business-risk gate — runs `33646585228` and `33647019780` — and the batch stopped there. Preview proof and review evidence were both green; only the gate refused, and it refused for a reason that has nothing to do with the migration. Full analysis in **#2118**.

The owner's authorization covered exactly that batch at that tip. **It is spent and does not carry forward.** Any future promotion needs Albert naming the exact resource and action again, in chat.

## 4. Half-finished or abandoned

Nothing is half-applied. The promotion stopped cleanly *before* touching production, which is the correct failure mode. No migration is partially applied anywhere.

## 5. What this session owns

- **Branch `claude/orchestrator-2109-closeout`** — this file and nothing else. Docs-only. Merged before the marker closes.
- **Worktree `.claude/worktrees/shared-db-orchestrator-14be64`** — finished, safe to clean once this merges.
- **Worktree `.claude/worktrees/fix-catalog-verif-quoting`** — finished; its PR #2114 is merged into `main`. Safe to clean. It was reset to `origin/<branch>` mid-session because it was stale at `61cba94f`.
- **No open PRs, no held locks, no author lane, no live sub-agent.**

## 6. What was about to happen next

Nothing structural — there is nothing to dispatch. The next orchestrator's first real decision is whether to treat #2118 as its own blocker or wait for the repo session to clear it, because until it clears, **no production promotion of any kind can succeed.**

## 7. Blocked on

**Blocked on engineering, not on Albert:**

- **#2118** — production promotion permanently blocked by the business-risk gate. Highest-consequence open item.
- **#2116** — a production apply revokes guarded-merge authorization on every open PR head and never restores it.
- **#2117** — one reviewer wrapper takes fixed subcommands and no prompt file, so the governed runner's universal invocation shape can never brief it. This is the real cause of that reviewer's "never returns a verdict" reputation.
- **#2075, #2076, #2078, #2106** — reviewer-pool defects, four distinct deadlock and mis-attribution modes.
- **#2104** — seven repo-maintenance PRs, four green and mergeable, three conflicting.
- **#1868** — the worktree reap. ~200 worktrees. `scripts/reap-merged-worktrees.mjs` refuses while any `orchestrator-marker` issue is open, so **closing marker #2109 unblocks it.** Run it dry first.

**Blocked on Albert (all carry `needs-albert`):**

- **#2110** — drop the frozen `designflow_frozen_20260710` schema, or leave it frozen indefinitely. 1,385 rows, two live inbound foreign keys, and the only backup is a machine-local gitignored file on EDGE-DEV containing real email addresses. If that machine is lost, the backup is lost; #778 recorded that as an accepted trade.
- **#1693, #870, #718, #696** — security-settings, owner-only.
- **#1353** — reduced to a future authorization only; no longer urgent. See section 9.

**Curated master data, dispatched but session-local — see section 8.**

## 8. Sub-agents dispatched

No sub-agent ran to completion inside this session. Four FORK/repo items were handed to fresh sessions as background task chips, which are **session-local**: if Albert did not click them, they are gone when this session ends, and their issues are the durable record.

### Agent: chip `task_4001e781` -> issue #2104
- **Asked to do:** merge or close the seven untouched repo-maintenance PRs.
- **Actually did:** unknown — chip issued, no completion observed.
- **Worktree:** none created.
- **Deliberately did NOT do:** the orchestrator did not touch these PRs itself. Repo-maintenance routes away from the orchestrator under the AGENTS.md admission test; four are green and mergeable and it would have been easy and wrong to just merge them.

### Agent: chip `task_0e97873d` -> issue #640
- **Asked to do:** reconcile the four licensor source extracts against `core.property` and `core.licensor`.
- **Briefed with:** the ID-collision trap (two different licensors both use small integers, so a plain ID join misattributes and that is a royalty error) and the three conflated figures #640 explicitly forbids carrying forward.
- **Actually did:** unknown — chip issued.

### Agent: chip `task_2d0be9a0` -> issue #1941
- **Asked to do:** technical preparation for Laura and Ilona's licensed-Property review, then the controlled ColdLion update.
- **Briefed with:** the authority rules verbatim — contracts and schedules are authoritative, creative-library folder position is not — plus the recorded rulings that a "character" here is an appearance and that the property list contains two distinct kinds.
- **Actually did:** unknown — chip issued.

### Agent: chip `task_d8f554a1` -> issue #562
- **Asked to do:** decide the source for the empty `core.character`, record Laura's round-2 answers, fix the question-generator defect with refusal tests.
- **Briefed with:** the licensing question stream is CLOSED, there is no round 4, do not open new questions to Laura.
- **Actually did:** unknown — chip issued.

**None of these consumed a migration-author lane, which is correct: FORK items must not.**

## 9. What was tried that did NOT work — MANDATORY

**The reviewer pool cost this session three full rotations, and all three were our own plumbing or a genuine quota limit. Not one was a "dead reviewer".**

1. **kimi-k3** — genuinely out of quota. The raw wrapper log said `Terminal reason: usage-limit` and that the account usage limit was reached. Real, external, nothing to fix.
2. **codex-review** — refused with exit 2. Probed directly and it printed only its usage text. Root cause: that wrapper takes fixed subcommands (`plan-review|diff-review|security-review|visual-review|final-check`) and **no prompt file at all**, so the governed runner's universal `new <session> --prompt-file` shape can never work. Retrying with `-- diff-review` ran (exit 0) but still could not bind a head SHA. Filed as #2117.
3. **grok (earlier)** — our review brief omitted the head-SHA requirement, so its verdict line was discarded and the runner blamed the reviewer.

**The runner suppresses all wrapper stdout.** A refusal message you see is therefore never evidence about the reviewer. Read the raw wrapper output before calling any reviewer dead.

**Reviewer replacement flags — the shapes are not what they look like.** `--replace-failed-reviewer` needs `--issue --pr --head-sha --review-slot --failed-sequence --failure-code --confirm-no-verdict --confirm-no-artifact`. Passing `--replacement-sequence` gets you `REFUSED: reviewer replacement requires exact issue, PR, 40-character head SHA, and failed sequence` — that flag belongs to `run-governed-review.mjs`, where it names the FAILED sequence, not the replacement.

**Regenerating the truth audit wholesale was wrong and was reverted.** The first attempt refreshed every recorded `site` line-number label and churned 124/117 lines, burying the two real changes. The audit's own disposition field says line movement alone does not require regeneration. Redone preserving the recorded labels: 16 inserts, 9 deletes.

**Guarded merge said "base branch policy prohibits the merge" five times.** That message does not mean what it says. It means a required check is red. It was `Tools offline tests` reporting `truth-audit semantic inventory drift ... (found 233, recorded 232)`.

**`git worktree add -B` failed** with `already used by worktree` — the worktree existed and was stale at `61cba94f`. Use the existing one and `git reset --hard origin/<branch>` first.

**Three Node scratch-script dead ends on Windows:** `ERR_AMBIGUOUS_MODULE_SYNTAX` from mixing `require` with top-level await; `ERR_MODULE_NOT_FOUND` because the git-bash temp path maps to a different real directory so relative imports resolve somewhere else entirely; `ERR_UNSUPPORTED_ESM_URL_SCHEME` because a Windows absolute path needs a `file:///` URL. Python called from git-bash has the same temp-path problem — it cannot open a path git-bash wrote to.

**`No module named pytest`.** Use `cd scripts && python -m unittest test_production_catalog_verification`, then grep for `^(OK|FAILED|Ran )` — run from the repo root it prints report output instead of a summary. Result was `Ran 163 tests in 0.494s / OK`.

**Issue #1864 was finished work that looked dispatchable.** It asked to unblock PR #1823. That PR merged on 2026-08-30 (`d60f75b1ada51c1ed1b78b51bca54c6edfb0e33a`, an ancestor of current `main`), its migration `20260830195655_licensors_external_id_canonical_codes.sql` is on `main`, and issue #505 is closed. Both the head SHA and the reserved version quoted in #1864's body were stale and never merged. Closed with evidence. **Check the merged tree before dispatching any inherited issue.**

**#1353's title was false and its body was correct.** The title claimed dev, staging and sandbox all write into the production Supabase project. Asked directly, Albert answered that DesignFlow dev, staging and sandbox have their own supabase.com database. Production runs on Cloud SQL. The three non-production names share one Supabase project and one `dflow` schema — a hygiene problem among themselves, not a path into live data. Retitled, repriced 550 to 200. **An alarming title outranks a careful body; reconcile the two before escalating an inherited issue.** This nearly became a request to fund a multi-day environment separation for a risk that does not exist.

## 10. Facts that may already be stale

- **Production's applied migration set is UNVERIFIED at handover.** The Supabase MCP server was unavailable at closeout (`Server supabase unavailable`, twice, around 17:05Z), so no live read was possible. What *is* certain is that this session applied nothing — the gate refused before any apply step. Re-derive production state from a live read before trusting any list of pending versions, including the "nine versions" figure quoted above, which comes from the promotion attempt and was never independently confirmed.
- Every SHA, run ID and count in this file was checked between 16:00Z and 17:10Z on 2026-09-02. Documents in this repo have gone stale within the hour.
- The four background chips may have been started, ignored, or dismissed. Their issues, not this file, are the durable record.
- The ~200 worktree count is a `git worktree list` line count taken at 17:07Z, not a reap dry-run result.

## 11. Secrets sweep

**Swept, nothing new.** No credential appeared in chat, no connection string was written to a scratch file, no `.env` was created, and the diff and untracked files carry no secret material. The only identifiers recorded anywhere in this session are GitHub run IDs, commit SHAs and Supabase project refs, none of which is a credential. Nothing was added to or changed in the `vibe_coding` vault.

## 12. Documentation pass

`AGENTS.md` is not wrong about anything this session touched, and no rehearsal or evidence artifact was voided — the two guard files that were re-pinned were each re-derived from a live run first, which is the opposite of voiding them. **Docs pass: nothing outside this handover is stale.**

Four durable lessons were recorded in session memory rather than sprayed across repo docs: that reviewer wrapper takes no prompt file; a verdict line needs the head SHA; DesignFlow production is Cloud SQL; and finished work looks dispatchable.
