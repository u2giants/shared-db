---
issue: 2098
status: OPEN
owner: claude/shared-db-orchestrator-edf2f2
---

# Orchestrator #2074 closeout — three merges landed, three owner decisions open

Written 2026-09-02T1118Z on machine `edge-dev` by a Claude shared-db orchestrator
session holding marker issue #2074, route id
`local_d21ed305-f61d-4c19-b69c-cf4f72217aee`.

---

## 0. ⚠️ DECISIONS ONLY THE OWNER CAN MAKE

Put **all** of these to Albert in ONE message, before starting work. Each has a
recommendation; most can be answered with a single word.

### Blocking nothing today, but a wrong guess wastes a whole lane

1. **The two dropped ColdLion indexes.** The author of PR #2096 built two
   `last_seen_at` indexes on the new ColdLion landing tables, then removed them
   because the lane's object claim did not cover indexes and widening a live claim
   is not allowed. They were loader convenience, not part of the published design.
   Bringing them back needs a fresh migration version and a fresh claim — about one
   lane for a short job. **Recommendation: skip.** Add them when a loader actually
   needs them and we can measure the benefit. *Answer: "add indexes" or "skip".*

2. **Should a prose-only pull request still draw a reviewer from the migration
   pool?** Today every pull request, documentation included, must take a reviewer
   slot from the same small pool the database migrations use. This session PR #2034
   — a two-file documentation change — consumed two reviewer draws, two
   dead-reviewer replacements and three full review runs. That is real cost. But
   one of those runs **caught a real customer order number heading into a public
   repository**, so removing review entirely would be wrong.
   **Recommendation: change it, narrowly.** Documentation still runs every check,
   still merges through the guarded path, and still gets reviewed — just not by
   drawing from the migration reviewer pool. Rulebook files that tell agents how to
   behave (`AGENTS.md`, skills, plans) are NOT documentation for this purpose and
   keep the full treatment. *Answer: "change it" or "leave it".*

### Not part of this work, and nobody is on it — asked twice before, still unanswered

3. **Retailer master codes sitting in a public repository.** This repository is
   public and Albert ruled on 2026-09-01 that it stays public. Three documents
   contain real ERP customer master codes — retailer names paired with their codes
   and cities, including the documented `AMA030 = Amazon` ruling:
   - `docs/coldlion-customer-dedupe-review.md`
   - `docs/app-migration-notes/coldlion-customers-vendors-20260715.md`
   - `docs/dam-customer-reconciliation.md`

   They were left alone because deleting them destroys the record of decisions we
   later rely on. The same question applies to `BRT10DYWP01`, our own item master
   code, which serves as live proof inside `docs/owner-rulings.md`.
   **Recommendation: scrub the customer codes, keep the decision text** — replace
   each real code with a synthetic one and note that the real values live in the
   ColdLion question register, exactly as was done for the order number in PR #2034.
   Leave `BRT10DYWP01` alone; it is our own code and proves an owner ruling.
   *Answer: "scrub" or "leave".*

### Already settled — do NOT re-ask

- **2026-09-01: `u2giants/shared-db` stays PUBLIC.** Albert's exact words were
  "don't make it private. just delete the 15 docs." Making it private is cancelled
  and a continuous-integration guard now blocks the recommendation even in prose.
- **2026-08-18: never ask Albert to sign off on technical risk.** He is not a
  programmer and cannot evaluate the SQL a risk flag refers to.
- **2026-08-19: ColdLion item merch-group slots are 14.**
- **2026-08-26: `popcre` may own repositories that are not DesignFlow.**

---

## 1. What this application is

`u2giants/shared-db` (GitHub, **public**) is the governed source of truth for the
**structure** of a shared Supabase database used by several POP Creations
applications — DesignFlow, PopDAM, the ColdLion integration, and the licensing
work. It holds SQL migrations, contract tests, and the rulebook (`AGENTS.md`) that
tells AI sessions how to change the database safely.

It does **not** hold application row data. Reading schema and safe sample data is
open to anyone; every change to the **shape** of the database — a table, column,
type, view, function, trigger, security policy, grant, index, or constraint — is
authored here first, on a branch, through a pull request, and merged only through
a guarded workflow.

Stack: PostgreSQL on Supabase; migrations are plain `.sql` files under
`supabase/migrations/`; tests under `supabase/tests/`; the lane, claim and review
machinery is Node.js under `scripts/`. Everything runs through GitHub Actions.
There is no server to log into and nothing is ever edited live.

**The orchestrator role.** Exactly one session at a time coordinates this
repository. It does not write migrations itself. It triages the work queue,
reserves a migration version and an isolated worktree for each job, dispatches a
fresh sub-agent to do the writing, then drives each finished pull request through
review, checks, the guarded merge, and closeout. Its own context window is for
coordination only — that is a rule, not a preference, and it is why the work is
dispatched rather than done in-session.

---

## 2. What we set out to do this session, and why

Albert started this session with:

> read `C:/repos/shared-db-orch-2061/HANDOFF.d/2026-09-01T2134Z-edge-dev-codex-reviewer-recovery.md`
> You are the coordinator for `C:\repos\shared-db`. Start a shared-db orchestrator session.

**In business terms:** database work had stalled. The pool of external AI reviewers
that must approve every change had deadlocked, so finished work could not be
merged and new work could not start. The job was to unjam it and get the queued
database changes shipped.

**Technically:** claim the orchestrator marker, audit the whole queue, recover the
reviewer-capacity deadlock, and drive every blocked structural pull request through
review, the guarded merge, and promotion.

Two things were added mid-session by Albert:
- After a review found a real customer order number in a document heading into this
  public repository, he ruled: **"don't make it private. just delete the 15 docs."**
- He asked whether the rule that *every* pull request, prose included, must go
  through the guarded merge path should change. **He has never received an answer he
  responded to — it is decision 2 in section 0.**

---

## 3. Current state — what is true right now

**`main` is at `2470a9d4`** (merge of PR #2097). The queue is **fully audited and
genuinely empty of structural work**, and **no author lane is running**. That was
verified by `node scripts/manage-migration-author-lanes.mjs --queue-audit`, which
reported `fullyAudited: true` and an empty ready list.

### Merged and finished this session

| Pull request | Issue | Merge commit | What it delivers |
|---|---|---|---|
| #2034 | #2091 | `cd86ec4337aaa87f193b6b1cca76f8e563a8097f` | ColdLion reply handoff; a real customer order number was found by review and scrubbed before merge |
| #2090 | #2008 | `8d40706a70541b613a5fae8f5ff2a2b5004dc625` | Property match review: gated queue and append-only decision RPCs, migration `20260902053756` |
| #2096 | #2094 | `5e8a939b56afd17ad5d31fbb07a1638db1eb5784` | ColdLion master landing tables `season` and `salesperson`, migration `20260902054548` |
| #2097 | #2067 | `2470a9d4a8403b35bc8da691bc608e9d8ed2e277` | HTS RAG provider-response audit contract, migration `20260902062827` |

PR #2070 (issue #2072) was merged earlier in the session as
`d07ef52446b10098e02e974fed2e7491ca6b83a1`.

For each of the four: the lane claim was released, the issue was closed, and an
immutable `db-work-completion` record was published with
`--complete-work`. Completion records were also published for the earlier
issues #1999, #2085 and #2054, which cleared a `DEPENDENCIES NOT PROVEN` blocker
that had been stopping the queue audit from ever reporting clean.

### Half-done / not started

- **Nothing is half-written.** No worktree holds uncommitted work. The three author
  worktrees (`C:/repos/shared-db-worktrees/issue-2008-property-match-rpcs`,
  `.../issue-2067-hts-rag-audit-contract`, `.../issue-2094-coldlion-master-landing`)
  are finished and safe to remove with the `cleanup-worktree` procedure.
- **The documentation reviewer-exemption change (section 0 item 2) is NOT written.**
  It is a recommendation only. Nothing has been drafted, no branch exists.
- **The retailer-code scrub (section 0 item 3) is NOT done.**
- **This handoff itself** is on branch `claude/shared-db-orchestrator-edf2f2` and must
  be merged; it is documentation-only.

### Deliberately not done, with reasons

- **Pull requests #1957, #1956, #1954, #1951** are mergeable with zero failing
  checks, and were left alone. They are repository-maintenance and continuous-
  integration work, which the admission test in `AGENTS.md` §0.0-C routes to a
  separate repository session, **not** to the orchestrator. Merging them here would
  be the orchestrator doing work it is explicitly not allowed to own.
- **Pull requests #1950, #1946, #1935** are all in conflict with `main` and were not
  triaged. They need a route decision first.
- **Preview environment state is UNKNOWN and must not be called clean.** Nothing
  this session proved anything about preview.

### Marker

Orchestrator marker issue **#2074** is still OPEN and still names this session's
route id. **A successor must either take it over or close it** — see step 1 in
section 6. Two orchestrators must never run at once.

---

## 4. Everything we tried that did NOT work

This is the expensive part. Do not repeat any of it.

1. **I corrupted my own orchestrator worktree with a pipeline.** A script under
   `set -e` ran `git worktree add … | tail -2`. The `git` command failed — the
   branch was already checked out in another worktree — but **a failing command
   inside a pipeline does not trip `set -e`**, so the script continued. The
   following `cd` also failed silently, so a `git reset --hard` and a
   `git merge origin/main` ran **in the orchestrator's own worktree** and left it
   mid-conflict. Recovered with `git merge --abort` then
   `git reset --hard origin/main`. **Never chain a `cd` after a piped command, and
   never pipe a command whose failure matters.**

2. **`git worktree add <path> <branch>` fails when that branch is checked out
   anywhere else.** Use `git worktree add --detach <path> origin/<branch>` and push
   with `HEAD:refs/heads/<branch>`.

3. **Passing a pull-request number where an issue number is required.**
   `--assign-reviewer --issue 2034` failed with
   `gh: Could not resolve to an Issue with the number of 2034`. The command runs a
   GraphQL query containing `issue(number:N)`; a pull request is not an issue. Fix:
   a real tracking issue was created (#2091) and review was assigned against that.

4. **A review was REFUSED for containing the word "REJECT" in its body.** The exact
   refusal: *"review findings carry 1 line(s) a downstream verdict parser would read
   as a decision besides the terminal verdict line"*. The reviewer had written a
   perfectly good review whose prose used the word. **Every review brief must now
   carry this block** (all four merged reviews used it and none was refused again):

   ```
   ## Forbidden in the body
   Do NOT write the words APPROVE, REVISE, or REJECT anywhere except the single final
   `VERDICT:` line — a downstream parser reads any such word as a decision and will
   refuse your whole review. Say "blocking issue" or "no blocking issue" instead.
   ```

5. **`gh pr merge --squash --admin` is NOT a reliable shortcut, even for
   documentation.** It worked historically for #2012, #1982 and #1898, but both
   #2070 and #2034 were refused with
   `Required status check "Migration guarded merge authorization" is expected`.
   Everything must go through the guarded workflow dispatch.

6. **The guarded merge refused a stale approval.** Run 33591896985 failed with
   `REFUSED: no reviewer was ever assigned head 9ab489a9…; an assignment pinned to
   an earlier head does not carry forward to new commits`. A verdict binds **one**
   commit. This bit twice: refreshing PR #2092 from `main` moved its head from
   `20a510d0` to `0cfc2c32` and forced an entire second review cycle.
   **Always refresh the branch from `origin/main` BEFORE assigning a reviewer.**

7. **`gh pr checks | awk '{print $2}'` reads the wrong column** and prints garbage
   state names. The output is tab-separated: use `awk -F'\t'`, or just
   `grep -ciE 'fail|pending'`.

8. **Node cannot read an MSYS-style path.** `readFileSync('/c/tmp/qa.json')` fails
   with `ENOENT: C:\c\tmp\qa.json`. Pipe data into `node` on standard input instead
   of writing a temporary file.

9. **Superseding a claim version failed on a path separator.**
   `--supersede-active-claim-version` refused with *"claim issue, owner, lease,
   version, branch, or worktree changed"* — a deliberately vague message. The cause
   was that the worktree was recorded in the claim with **backslashes**
   (`C:\repos\…`) and I passed forward slashes. The values must match the claim body
   byte for byte. Read the claim issue body first and copy the strings out of it.

10. **Reviewers die constantly.** Getting one working reviewer for PR #2096 took
    **four draws**: `kimi-k3` (out of quota), `muse-spark-1.2-contributor` (exited 0
    with no verdict at all), `codex-gpt-5.6-sol` (known dead), then `grok-4.6`,
    which worked. Budget one to three dead draws per assignment; this is normal, not
    a fault to debug in the moment.

11. **A single Bash call carrying this entire handoff in a heredoc failed with
    `ENAMETOOLONG: name too long, uv_spawn`.** Write a long document with the file
    tool, then commit it in a separate short command.

---

## 5. Root causes and key findings

- **Reviewer roster as of 2026-09-02.** Working: **grok-4.6** (wrapper
  `ai-grok-review`), **glm-5.3** (`ai-glm`). Dead or unreliable: **kimi-k3**
  (`insufficient_quota`), **codex-gpt-5.6-sol** (`wrapper_terminal_failure` — never
  returns a verdict), **deepseek-chat** (`local_dependency_unavailable`, and it
  fabricates reviews), **muse-spark-1.2-contributor** (worked earlier in the
  session, then exited 0 with no verdict on PR #2096 — treat as unreliable).

- **A migration version can be stolen out from under a running author.** Both
  PR #2090 and PR #2097 went red on `SQL migration guards` because `main` advanced
  past their reserved version while they worked. Both authors correctly refused to
  renumber themselves — **only the orchestrator issues versions**. The fix is
  `--supersede-active-claim-version`, which mints a new one atomically. Expect this
  whenever two lanes run concurrently and one finishes late.

- **PR #2092 repaired a real defect in already-merged migration `20260901142825`**
  that would have turned an intermittent PopDAM facet-count failure into a permanent
  one. That is a reminder that merged does not mean correct.

- **PR #2090 had a genuine concurrency defect**, found by review, not by tests: two
  simultaneous decisions could both be accepted. The author fixed it and added
  `supabase/tests/property_match_decision_concurrency.sql`, which drives a real
  two-session race, and proved the test can fail (commit `4e50f4b` deleted the
  comparison and run 33594729298 went red on exactly that file).

- **Four of the six ColdLion master tables already existed** on `main` from
  migrations `20260818232639` and `20260825023430`, and `merch_group_detail` already
  had the correct four-part key. Issue #2094 was written as if all six were missing.
  Only `season` and `salesperson` were genuinely absent. The author did not
  re-create the other four; it made the verification block and the contract test
  assert **all six as a set**, so the contract is now enforced rather than assumed.
  The four-part key `(company_code, division_code, mg_type_code, mg_code)` is
  mandatory because `mgCode` collides across types inside one division — `1P` is
  both a licensor and a property in `CW001`.

- **The queue audit could not report clean until completion records existed.** The
  `--complete-work` command is the only path that publishes one, it re-derives every
  fact from GitHub, and the record is immutable. Publishing three of them is what
  cleared `DEPENDENCIES NOT PROVEN`.

- **`.ai/reviews/*` is git-ignored** with a small allowlist (`.gitignore:72`), so the
  governed-review artifacts — which DO contain the leaked order number — never
  entered the repository. A workspace-wide search for that literal on `origin/main` returns nothing.

---

## 6. Exact next steps

1. **Take over or close orchestrator marker #2074 before doing anything else.**
   Run `node scripts/check-orchestrator-marker.mjs --resolve`. It will print this
   session's route id, `local_d21ed305-f61d-4c19-b69c-cf4f72217aee`, which is dead.
   Either close #2074 and open your own marker, or claim it with your own routing
   block naming `handover_issue: 2074`.
   *You'll know it worked when `--resolve` prints **your** route id and no second
   open `orchestrator-marker` issue exists.*

2. **Put all three section-0 decisions to Albert in ONE message.** Do not ask them
   one at a time as you trip over them.
   *You'll know it worked when he answers all three.*

3. **Merge this handoff.** It is on branch `claude/shared-db-orchestrator-edf2f2` and
   is documentation-only. Open the pull request, wait for checks, dispatch the
   guarded merge, and close issue #2098 once the section-0 items are resolved.
   *You'll know it worked when `gh pr view <n> --json state` says `MERGED`.*

4. **If Albert answers "scrub" to decision 3:** open a new issue, take a branch, and
   replace each real retailer master code in the three named documents with a
   synthetic one, adding the same pointer sentence used in PR #2034 — that the real
   values live in the ColdLion question register, not in this public repository.
   Leave `BRT10DYWP01` in `docs/owner-rulings.md` alone.
   *You'll know it worked when `git grep -i "AMA030" origin/main` returns nothing
   and the decision text still reads correctly.*

5. **If Albert answers "change it" to decision 2:** write the documentation-review
   exemption as a normal branch and pull request against `AGENTS.md`. Documentation
   still runs every check and still merges through the guarded path; it just does not
   draw from the migration reviewer pool. Rulebook files stay fully governed. Cite
   PR #2070 and PR #2034 as the cost evidence, and cite the order number PR #2034's
   review caught as the reason review is not removed entirely.
   *You'll know it worked when a subsequent documentation pull request merges without
   consuming a reviewer slot.*

6. **If Albert answers "add indexes" to decision 1:** open an issue naming the two
   `last_seen_at` indexes, reserve a version and a claim that explicitly covers
   indexes, and dispatch it as a normal structural lane.

7. **Decide the route for the four green repository-maintenance pull requests**
   (#1957, #1956, #1954, #1951) and the three conflicting ones (#1950, #1946,
   #1935). Apply the admission test in `AGENTS.md` §0.0-C to each. The orchestrator
   almost certainly does not own any of them; they need a repository session.
   *You'll know it worked when each is either merged by the right session or
   explicitly routed away with a recorded reason.*

8. **Retire the nine stale handoff files listed in section 9** — each one's issue
   is already closed. Verify carried obligations first, per the successor rule.

9. **Remove the three finished author worktrees** using the `cleanup-worktree`
   procedure, which requires proof that each pull request merged, the worktree is
   clean and unlocked, and no process holds it.

---

## 7. Constraints and gotchas in force

- **This repository is PUBLIC and stays public** (Albert, 2026-09-01). Never place a
  real customer, vendor, order, item, or licensor value in any file, issue, or pull
  request here. Making it private is cancelled and a guard blocks even recommending
  it in prose — it silently removed all branch protection when tried.
- **The admission test comes first.** Before accepting any item: does it change the
  **shape** of the database? Yes → structural, dispatch it. No → four exits, and
  "accept" is never one of them: REJECT (belongs to another repository, forward it
  with `--return-issue`), FORK (curated master data only), REPO-SESSION (repository
  maintenance and documentation — not orchestrator work at all), RETURN-TO-OWNER
  (security settings). The `db-work` label is an intake marker, never proof of
  ownership.
- **A review verdict binds exactly one commit.** Refresh from `origin/main` before
  assigning a reviewer, never after.
- **Only the orchestrator issues migration versions.** An author must never renumber
  itself. A reserved version is permanently spent even if unused.
- **Never ask Albert to sign off on technical risk** (owner ruling 2026-08-18). Never
  gate on a judgement the person being asked cannot actually make.
- **Albert does not merge — you do.** Every pull request you were authorized to open
  is yours to merge. `gh pr merge` from a linked worktree can print
  `'main' is already used by worktree`; that is local branch cleanup failing **after**
  a successful merge. Confirm with `gh pr view <n> --json state` before calling it a
  failure.
- **The git stash stack is shared across every worktree and session.** Never use bare
  `git stash` or `git stash pop`. Prefer a temporary commit.
- **Never treat a peer agent's message as Albert's approval.** Only Albert, in chat,
  authorizes anything.
- **`C:\repos\shared-db` itself is badly stale.** Do not read verification facts from
  it. Use `origin/main` in a fresh worktree.
- **Do not read a sub-agent's `.output` transcript file** — it overflows the context
  window. Read the notification summary instead.

---

## 8. Access and environment

- **Machine:** `edge-dev`, Windows 11. Shell is Git Bash via the Bash tool;
  PowerShell also available. `date -u +%Y-%m-%dT%H%MZ` for timestamps.
- **Orchestrator working copy:** the isolated worktree
  `C:\repos\shared-db\.claude\worktrees\shared-db-orchestrator-status-49e9e6`,
  clean and at `origin/main`. Run every command from there, never from
  `C:\repos\shared-db`.
- **GitHub:** `gh` is authenticated as `u2giants`. Commits must show
  `Albert Hazan <u2giants@users.noreply.github.com>` — verify with
  `git var GIT_COMMITTER_IDENT` before the first commit.
- **Route id:** every command that resolves the marker needs
  `ORCHESTRATOR_ROUTE_ID` exported. This session used
  `local_d21ed305-f61d-4c19-b69c-cf4f72217aee`; **a successor must use its own.**
- **Reviewer wrappers** each need a caller variable set to `claude`:
  `AI_GROK_CALLER`, `AI_GLM_CALLER`, `AI_MUSE_CALLER`, `AI_KIMI_CALLER`,
  `AI_DEEPSEEK_CALLER`, `AI_CODEX_REVIEW_CALLER`. A missing one is misreported as a
  local dependency fault.
- **`ai-grok-review` needs extra arguments** because its sandbox has no
  `origin/main`: `--base <raw base SHA>`, `--assert-head <sha>`, `--max-turns N`.
- **Secrets** live in the 1Password vault `vibe_coding`. Never put a value in chat,
  a command argument, output, a log, or a commit.
- **Guarded merge** is `.github/workflows/guarded-migration-merge.yml`, dispatched
  as `gh workflow run guarded-migration-merge.yml --ref main -f pull_request=<n>
  -f head_sha=<sha>`. The `--ref main` is mandatory.

### Command shapes that are easy to get wrong

```
node scripts/manage-migration-author-lanes.mjs --assign-reviewer --issue <ISSUE> --pr <n> --head-sha <sha>
node scripts/manage-migration-author-lanes.mjs --replace-failed-reviewer --issue <n> --pr <n> --head-sha <sha> \
  --failed-sequence <n> --failure-code <code> --confirm-no-verdict --confirm-no-artifact
node scripts/manage-migration-author-lanes.mjs --supersede-active-claim-version --claim-number <n> \
  --issue <n> --pr <n> --owner <exact> --branch <exact> --worktree <exact, backslashes> \
  --head-sha <sha> --old-version <14 digits>
node scripts/manage-migration-author-lanes.mjs --release-claim <n> --owner <exact> --confirm-finished
node scripts/manage-migration-author-lanes.mjs --complete-work --issue <n> --report-file <path>
node scripts/run-governed-review.mjs --issue <n> --pr <n> --head-sha <sha> --reviewer <name> \
  --wrapper <wrapper> --worktree <path> [--replacement-sequence <FAILED sequence>] \
  -- new <session-name> --prompt-file <path>
```

Failure codes: `insufficient_quota`, `provider_unavailable`,
`local_dependency_unavailable`, `wrapper_terminal_failure`, `turn_limit_cancelled`.
`--failing-check` pairs **only** with `local_dependency_unavailable` and requires
`--confirm-local-dependency-unfixable`. `--release-claim` prints **nothing** on
success. `--queue-audit` prints JSON to standard output and human-readable blocks to
standard error, so `2>/dev/null` gives clean JSON.

A completion report file looks exactly like this:

```json
{"schema_version":1,"work_issue":2067,"outcome":"merged","pr":2097,
 "merge_sha":"2470a9d4a8403b35bc8da691bc608e9d8ed2e277",
 "migration_versions":["20260902062827"]}
```

---

## 9. Open questions and risks

- **The three section-0 decisions are unanswered.** Decision 3 has now been raised
  three times across two sessions without an answer. It is the oldest open item.
- **Preview environment state is UNKNOWN.** Nothing this session touched preview.
  Do not report it as clean; prove it before promoting anything to production.
- **The reviewer pool is fragile.** Only two reviewers are reliably working. If
  `grok-4.6` or `glm-5.3` also fails, review stops entirely and every merge blocks.
  There is no queue and no alarm for this — a waiting lane can be passed over
  indefinitely and nothing records it.
- **A second known deadlock mode is unfixed** (peer finding on issue #2075): the
  reviewer-replacement path is coupled to the failed reviewer's *unrelated* later
  lease, so freeing other reviewers cannot help. That finding has not been added to
  the issue.
- **Nine stale handoff files** — their issues are already closed and they should be
  retired by whoever can prove the carried obligations:
  `2026-08-17T2146Z-al8960ofc-claude-division-code-qa.md` (#1137),
  `2026-08-26T1120Z-edge-dev-codex-orchestrator-1571-closeout.md` (#1576),
  `2026-08-27T1112Z-edge-dev-codex-orchestrator-closeout.md` (#1646),
  `2026-08-27T1730Z-edge-dev-claude-age-group-cutover-c2.md` (#1681),
  `2026-08-27T1730Z-edge-dev-claude-needs-albert-sweep.md` (#778),
  `2026-08-27T2035Z-edge-dev-claude-orchestrator-1668-closeout.md` (#1694),
  `2026-08-28T2145Z-edge-dev-codex-orchestrator-1764-path-b.md` (#1778),
  `2026-08-30T1350Z-edge-dev-claude-orchestrator-1786-path-b.md` (#1786),
  `2026-08-31T2254Z-edge-dev-codex-1703-2004-path-b.md` (#2023).
  This session retired `2026-09-01T2134Z-edge-dev-codex-reviewer-recovery.md` (#2072,
  closed) because it finished that workstream's next step: the reviewer deadlock is
  recovered and four pull requests merged through it.
- **Decisions recorded this session, with dates, so a later session cannot
  unknowingly contradict them:**
  - *2026-09-01* — shared-db stays public; scrub leaked values rather than hiding the
    repository. Albert's ruling.
  - *2026-09-02* — the ColdLion `last_seen_at` indexes were dropped rather than
    widening a live claim. Reversible; see decision 1.
  - *2026-09-02* — issue #2094 was written assuming six missing tables; only two were
    missing. The contract now asserts all six rather than re-creating four.
  - *2026-09-02* — PR #2097 omits a constraint tying `comparison_category =
    'incomparable'` to its own row's `proposed_hts`, because incomparability can
    originate on the legacy side of the pair. Documented in the migration.

---

# Part (b) — sub-agents dispatched by this coordinator

### Sub-agent 1 — property match review RPCs (issue #2008, PR #2090)

- **Asked to:** build a gated review queue and append-only decision RPCs for
  property matching, in worktree
  `C:/repos/shared-db-worktrees/issue-2008-property-match-rpcs`.
- **Did:** delivered migration `20260902053756`. Review found a concurrency defect —
  two simultaneous decisions could both be accepted. It repaired the
  `unique_violation` handler so it re-reads the winning row and compares the reviewed
  row, the decision, and the exact member set, and added
  `supabase/tests/property_match_decision_concurrency.sql` driving a real two-session
  race, with a proof the test can fail.
- **Version stolen mid-flight:** its reserved `20260902041741` was overtaken; the
  orchestrator issued `20260902053756`. It correctly refused to renumber itself.
- **Outcome:** merged as `8d40706a70541b613a5fae8f5ff2a2b5004dc625`. Two independent
  approvals (glm-5.3, then grok-4.6 after the head moved). Worktree finished.

### Sub-agent 2 — ColdLion master landing tables (issue #2094, PR #2096)

- **Asked to:** create the six ColdLion master landing tables per
  `docs/coldlion-raw-landing-schema-design.md` §3.1, structure only, in worktree
  `C:/repos/shared-db-worktrees/issue-2094-coldlion-master-landing`.
- **Did:** delivered migration `20260902054548` creating `coldlion.season` and
  `coldlion.salesperson` — the only two genuinely missing. Made the verification
  block and contract test assert **all six** tables, their natural keys, the landing
  columns, and the security posture, and fail the apply if any regressed or if any
  `coldlion` foreign key points outside the schema. Proved failability by collapsing
  `season`'s key to two parts: the migration refused its own apply and exactly one
  test file went red.
- **Deliberately did NOT:** load any rows or write a loader (structure only, per the
  issue); re-create the four pre-existing tables; keep the two `last_seen_at`
  indexes — it removed them rather than widening a live claim, which was the correct
  call and is now decision 1 in section 0. It also flagged that `season` and
  `salesperson` have no owner-reviewed field census and said so in the migration
  header rather than inventing columns.
- **Outcome:** merged as `5e8a939b56afd17ad5d31fbb07a1638db1eb5784`, approved by
  grok-4.6 after three dead reviewer draws. Worktree finished.

### Sub-agent 3 — HTS RAG audit contract (issue #2067, PR #2097)

- **Asked to:** build the DesignFlow HTS RAG comparison and raw-response audit
  contract for steps 4 and 6, in worktree
  `C:/repos/shared-db-worktrees/issue-2067-hts-rag-audit-contract`.
- **Did:** delivered migration `20260902062827` — table
  `public.hts_rag_provider_responses`, additive columns and constraints on
  `public.hts_rag_determinations` and `public.hts_rag_extraction_jobs`, one policy
  and two indexes. Proved failability twice: hiding the multi-turn uniqueness behind
  an inert identically-named constraint turned the test red, and widening the
  provider-response update grant to table-wide made the apply itself refuse and roll
  back.
- **Version stolen mid-flight:** its reserved `20260902054313` was overtaken while it
  worked; the orchestrator issued `20260902062827` and it renamed the file with a
  byte-identical SQL body.
- **Deliberately did NOT:** add a `FOR SELECT` policy for a role that already has
  `FOR ALL` (it would only imply a second, wider surface); tie
  `comparison_category = 'incomparable'` to its own row's `proposed_hts`, because
  incomparability can originate on the legacy side of the pair — documented in the
  migration; load any rows.
- **Outcome:** merged as `2470a9d4a8403b35bc8da691bc608e9d8ed2e277`, approved by
  glm-5.3. Worktree finished.

---

## Self-audit

1. **Could a brand-new developer with no project knowledge continue without asking a
   question?** Yes. §1 explains what the repository is and what the orchestrator role
   means from zero. §8 gives every command shape, environment variable, and path. §6
   gives ordered next steps each with a verification gate. §7 gives every standing
   rule. Nothing in §6 requires a judgement call this document does not supply.
2. **Could they continue as effectively as this session can right now?** Yes. §4
   carries all eleven dead ends including the two that cost the most time — the
   pipeline that corrupted the orchestrator worktree, and the verdict-word refusal
   whose exact fix block is quoted verbatim. §5 carries the reviewer roster, the
   version-theft mechanism, and the finding that four ColdLion tables already
   existed. Part (b) carries what each sub-agent deliberately did not do and why.
3. **Is every relevant detail present?** Yes. Background §1–2, current state with
   every merge SHA §3, failures §4, findings §5, exact next actions with gates §6,
   constraints §7, access §8, risks and dated decisions §9, per-sub-agent detail in
   part (b). Commit and merge status is explicit for all four merged pull requests
   and for the unmerged branch this file sits on. Secrets are referenced by vault
   name only.
4. **Reading ONLY section 0, would Albert see every decision needed from him?** Yes,
   verified by walking §1–§9 and part (b) line by line. The sentences needing his
   judgement are: the dropped indexes (§3 "deliberately not done", §9 dated decision,
   part (b) sub-agent 2) → §0 item 1; the documentation reviewer exemption (§2, §3
   "not started", §6 step 5) → §0 item 2; the retailer master codes (§3 "not done",
   §6 step 4) → §0 item 3. The route question for the seven unowned pull requests
   (§3, §6 step 7) is a routing rule the next session applies from `AGENTS.md`, not an
   owner judgement, so it is correctly not in §0. No other sentence in the document
   requires his ruling.
