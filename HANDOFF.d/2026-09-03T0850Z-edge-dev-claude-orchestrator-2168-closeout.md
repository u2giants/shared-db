---
issue: 2189
status: OPEN
owner: claude/orchestrator-2168-closeout
---

# Orchestrator marker #2168 — closeout

All facts below were re-verified against `git`/`gh` at **2026-09-03T08:50Z**. Anything
in this repo goes stale within the hour; re-derive before you act on it.

- `origin/main` tip: `70a372f3e09113aed56a8a4f38e19ac55fa496b0`
- Highest migration version on main: `20260903083204_sample_workflow_factory_customer_direct_path.sql`
- Orchestrator marker: issue **#2168**, closed as the final action of this session.
- Handover issue for this file: **#2189**

---

## 0. ⚠️ DECISIONS ONLY THE OWNER CAN MAKE

Put this whole list to Albert in **one message, before starting work**. Do not
trickle it out one item at a time.

### Read this first

**You named four priority issues at the start of the previous session — #2127,
#1966, #1984, #1987 — and three are still open.** That session merged seven other
changes instead and never reached them. Nothing blocked them; it was a sequencing
failure on our side, not a decision. #1987 was already closed on 2026-09-02. The
other three are now the first three steps in §6, ahead of every queued PR. Only
#1984 needs anything from you — item 1 below; #2127 and #1966 are ours to do.

### Nothing else is blocking right now

No other item below stops the next session from working.

### A wrong guess is recoverable, but rework is wasteful

1. **The three unanswered decisions on the merch-group reclassification tracker
   (#1984) are still unanswered, across several sessions.** They were not raised
   this session either. Recommendation: raise them as the first message of the
   next session, or explicitly retire them if the plan has moved past them.
   Read the tracker before asking, so Albert is not asked to re-load context a
   fourth time.

### Not part of this work, and nobody is on it

2. **DesignFlow cannot use the factory-direct route that now exists in the
   database.** Tonight's change lets a sample ship straight from the factory to
   the customer, but the DesignFlow app has no such option — nobody can pick it
   until DesignFlow is updated. Written up as `popcre/designflow-tracking#39`.
   Recommendation: schedule that work, or accept the database sitting ahead of
   the app indefinitely. This is a scheduling call, not a technical one.
3. **DesignFlow's own consistency check cannot detect the gap above.** It
   compares its two halves to each other and never to the database, so the two
   can agree while both disagree with reality. By that file's own comment this
   has already happened once. Recommendation: fix it as part of #39.
4. **The governed reviewer pool is down to three usable reviewers out of five.**
   `kimi-k3` fails instantly on provider quota; `codex` structurally cannot
   produce a recordable verdict (0 of 55 attempts, ever). Every draw of either
   burns a replacement and roughly ten minutes. Tracked as **#2162**.
   Recommendation: authorise topping up the kimi quota, or retire both from the
   rotation so the pool honestly reports three.

### Already settled — do NOT re-ask

- **ColdLion `/vendors` field dispositions** — settled 2026-08-19. 10 ingest,
  19 ignore. We do not want vendor addresses, zip, state, email or phone.
- **ColdLion `/seasons` fields** — settled 2026-09-03. All eight currently
  unstored fields are DECLINED; nothing is to be added to the seasons table.
- **`plm.source_resolution` has no foreign keys, deliberately** — owner ruling
  recorded in `20260902024541_source_resolution_supported_home.sql`. A foreign
  key there would either block a target's lifecycle or destroy a durable human
  resolution decision. Do not file work to "restore" them; a reviewer raised
  exactly this on 2026-09-03 and it was correctly refused.
- **Never ask Albert to sign off on technical risk.** He is not a programmer.
  Owner ruling 2026-08-18.

---

## 1. What this application is

`u2giants/shared-db` is the governed home for the **structure** of POP Creations'
shared PostgreSQL database, hosted on Supabase. It holds no application logic. It
holds migrations, schema contracts, and the tooling that decides whether a change
to the database's shape is allowed to land.

Several separate applications read and write that database — DesignFlow (sample
and factory workflow), PopDAM (digital asset management), PLM (product/licensing
master data), and the ColdLion vendor-feed landing area. Each owns its own rows.
None of them may change the database's shape except through this repository.

**The repository is PUBLIC.** No customer identifiers, personal data, licensed row
data, or credential values may be committed or pasted into an issue or PR. Check
every diff for this before sending it anywhere, including to a reviewer.

Environments: production Supabase project `qsllyeztdwjgirsysgai` (read-only to AI
sessions, always), shared preview project `mvpkijzfmfcxhnzqogzs` (rehearsal only,
one PR at a time, locked by a workflow).

---

## 2. What we set out to do this session, and why

**In business terms:** database changes had stopped landing. The tool that assigns
an independent reviewer to each change was refusing to run at all, which blocked
every review in the repository, which blocked every merge. The session's job was to
unblock it and then work through the backlog of queued changes.

**Technically:** merge PR #2155 (the reviewer pagination fix), then take each
queued structural PR through review → preview rehearsal → guarded merge, strictly
one at a time.

**What triggered it:** issue #2152 — `git/matching-refs` ignores `page=N`, so the
reviewer-ref pager looped on page one and refused rather than returning an answer.

Two owner questions arrived mid-session and were answered in full: the ColdLion
`/vendors` and `/seasons` field rulings, and a written problem report for the
ColdLion vendor about the unfiltered-seasons defect.

---

## 3. Current state — what is true right now

### Merged this session (seven), all through the guarded path, in order

| PR | What it does | Merge commit |
|---|---|---|
| #2155 | Reviewer ref pager refuses truncated GitHub answers instead of trusting them (#2152) | `8cd0e9c8d3aa5b379c3130f9a8e91609600d0fea` |
| #2187 | ColdLion `/vendors` + `/seasons` rulings made conspicuous; unfiltered-seasons defect warning (#2081) | `bdf2301ee682453e401e27994a998273c92c2de7` |
| #2170 | Records the 2026-09-03 read-only live re-verification as §9.2 (#1984) | `af929d8df2a2da49f36f4b9efea8ae38a48301eb` |
| #2158 | Adds `wildbrain` to the `plm.source_resolution` vocabulary (#2147) | `d3c961f9b5da414c3bd2b5d859255ce1d77302fc` |
| #2156 | Restores `core.character` foreign keys on the three Tier-1 character tables (#2146) | `121afd60e715919e77f0e7f0caffea0968ea8ec6` |
| #2150 | Restores LIMIT-bounded row fetching in `filter_effective_assets` (part of #2138) | `32449a9f5afb67db360945460e94f2ff7d25b449` |
| #2149 | Allows a make-request sample to ship direct from the factory (#2136) | `70a372f3e09113aed56a8a4f38e19ac55fa496b0` |

Every one was rehearsed on preview (except the two prose-only PRs, #2187 and
#2170, which have no migration) and carries a durable exact-head reviewer
approval. Issues #2152, #2147, #2146 and #2136 are closed with the merge commit
recorded. #2138 is **deliberately left open** — see §9.

### Open PRs, and the order to take them

Take them **one at a time**. Each needs: rebase onto current main → re-run the
guards from the moved base → preview lock via the workflow → apply → read-back
proof → exact-head external review → guarded merge → release the claim.

| PR | Branch | Issue | Note |
|---|---|---|---|
| #2186 | `claude/2173-coldlion-sales-history` | #2173 | ColdLion sales-history redesign + stage/page completion ledger. Largest of the four. |
| #2185 | `claude/2175-coldlion-unit-5a` | #2175 | ColdLion unit 5a landing tables for `/inventory` and `/prodtracking`. |
| #2183 | `claude/2177-coldlion-cust-sp` | #2177 | ColdLion `/customers` full projection + owner-ruled narrow `/salespersons`. |
| #2145 | `claude/2123-tier2-core-character-id` | #2123 | `core_character_id` promotion contract on the two Tier-2 character tables. |

**Not orchestrator work — do not touch:** PR #2166 (Disney property autocomplete,
handover issue #2169) and PR #2134 (source labels on the match screen). Both are
application work owned by other sessions.

### Preview state

**Clean, and verified clean.** Every rehearsal this session took and released its
lock through the workflow; no lane ref remains held. The last apply was PR #2149's
migration `20260903083204` on `mvpkijzfmfcxhnzqogzs`.

Preview holds a full production data clone. Nothing was written to it beyond the
four rehearsed migrations and their own verify blocks.

### Production

**Untouched.** Read-only queries only, all through the Supabase Management API
with `read_only: true`. No migration was promoted. Measurements taken (all
read-only, `qsllyeztdwjgirsysgai`):

- `plm.nbcu_character` 190 rows, `plm.opa_character` 9,613, `plm.pmt_character` 124
  — zero unresolvable character references in all three, and `core.character`
  itself holds 0 rows.
- `plm.source_resolution` 0 rows, 0 foreign keys.
- DesignFlow: 20 workflow rows, 20 revision rows, 4 make-request rows, zero rows
  on either newly permitted path.

### This worktree

Branch `claude/orchestrator-2168-closeout` off `70a372f3`, holding only this file
and the deletion of the predecessor's closeout. Nothing else is dirty.

---

## 4. Everything we tried that did NOT work

This is the section that saves the next session hours. Read it.

1. **Patching the Link-header parser one hole at a time — four rounds, four
   holes.** PR #2155's parser was written to accept anything it did not
   specifically object to. Round 1 found a param with no `=` and an unquoted value
   swallowing a quote; round 2 a link value with no relation at all; round 3 an
   unterminated bracket swallowing the next value, plus a trailing comma. Each
   patch was correct and each round found another. **The fix was to invert the
   parser** — prove the header is well-formed and refuse everything else. Do not
   patch a permissive scanner hole by hole; turn it around.
2. **A counterfeit control test.** A test claiming to prove the old pager returned
   duplicates built the duplicates in its own catch block. It passed for the wrong
   reason. Every control must be shown failing for its own stated reason before
   you trust it passing.
3. **Hand-reverting code to produce a "before" state.** Take the pre-fix code from
   `git show <sha>:<path>`. A scripted reversion went red for the wrong reason and
   read as a completed proof.
4. **Blaming the codex reviewer for out-of-scope findings.** It twice returned
   REJECT over a file not in the PR. The cause was not the reviewer: the review
   sandbox's clone drops branch pointers, so `resolve_base()` in `ai-review-packet`
   fell back to `HEAD~1`, and because the head was a merge commit, `HEAD~1` was the
   pre-merge branch — **so the wrong diff was being reviewed, in every repository**.
   Fixed in `popcre/ai-devops` PR #237, merged as `7b39f006`. The identical
   `source digest` across both runs was a red herring; it excludes branch pointers.
   **Always confirm the packet's base and its against-main file list before you
   trust any verdict.**
5. **Trusting a stale local `main`.** The shared checkout was ~500 commits behind
   and could not fast-forward because another session's untracked files blocked the
   checkout. Those files were **not** deleted. Read verification facts from
   `origin/main` in a temporary worktree instead.
6. **Stating a reviewer brief's file list from the previous head.** After a rebase,
   the head-to-head delta and the against-main diff are different answers. A brief
   built from the former under-reported the change; the reviewer caught it. State
   the list from the diff **against main**, always.
7. **Fencing the verdict line in a reviewer brief.** The recorder needs it bare.
   A reviewer copied the backticks faithfully and a perfectly good approval was
   discarded. Fix the brief template, not each copy.
8. **Filing a follow-up on a reviewer's observation without checking it.** A
   reviewer correctly noted a dropped foreign key on `plm.source_resolution` that
   nothing had restored — but stopped one migration short of the one that removed
   all four **deliberately, on an owner ruling**. Filing it would have queued work
   to reverse a ruling, with production measurements attached as apparent support.
   **Check whether a later migration already settled it.**
9. **`gh pr merge --admin` cannot merge anything here**, docs-only included. It
   cannot satisfy the required "Migration guarded merge authorization" check. The
   `guarded-migration-merge.yml` workflow dispatch is the only merge path.
10. **The Microsoft Store Python stub** shadows the real Python 3.13 on the Git
    Bash PATH, so reviewer wrappers die with "Python 3.10 or newer is required".
    Put `C:\Program Files\Python313` ahead of it for that one call. Nothing was
    installed or replaced.
11. **The `ai-glm` / `ai-grok` wrappers need their `new <session>` subcommand.**
    Omitting it looks like a provider failure and is not.

---

## 5. Root causes and key findings

- **Two guards fought each other on PR #2155.** The current-tip rule (a PR must be
  based on the current main tip) and the pinned-head rule (an approval is void if
  the head moves) mean a slow review gets invalidated by the rebase that satisfies
  the other guard. Run rebase → review → merge back to back.
- **A migration's reserved version can be backdated by a merge you yourself
  dispatch.** PR #2156's version sorted before the WildBrain migration merged an
  hour earlier, so the ordering guard refused it. The fix is a governed
  supersession to a fresh version — a pure rename, SQL untouched. This will keep
  happening as you merge down a queue; expect it, and do not treat it as a defect.
- **The supersession tool refuses on a claim title missing the `#`.** Its refusal
  names six things that are all fine and stays silent about the seventh that
  actually failed. Filed as **#2188** (repo-maintenance, not orchestrator work).
  Any claim whose title omits the `#` cannot be superseded at all.
- **A stale worktree looks exactly like live work.** `lane-2136`'s index held the
  exact inverse of its own PR, from a checkout predating a main move. Before
  clearing another session's worktree: confirm its HEAD is not the PR head,
  preserve the staged diff as a patch, and **verify any unique-looking file exists
  on a remote branch**. The one file that looked unique was already committed on
  eight branches.
- **Widening a CHECK constraint permits a state; it does not create one.**
  Schema-first is the safe order for an additive change — an app that emits a
  value the database refuses fails in front of a user, while a database permitting
  a value no app emits simply sits idle. That is why #2149 was merged ahead of
  DesignFlow.
- **`ADD CONSTRAINT` without `NOT VALID` is its own proof.** Postgres scans every
  existing row, so the migration fails loudly rather than installing a rule the
  data breaks. And because it has no drop-if-exists, a predecessor's same-named
  constraint would have aborted the apply — so a successful apply proves the
  constraint is this migration's, not an inherited one.

---

## 6. Exact next steps

1. **Open your own orchestrator marker** with your OWN `route_id` — never the
   predecessor's. Then run `node scripts/check-orchestrator-marker.mjs --resolve`.
   *You'll know it worked when* it prints your own `route_id` and reports exactly
   one active marker. Dispatch nothing until it does.
2. **Put §0 to Albert in one message.** *You'll know it worked when* he has
   answered, or explicitly deferred, every numbered item.
3. **FIRST, before any queued PR: the owner named four priority issues at the start
   of the previous session — #2127, #1966, #1984, #1987 — and three are still open.
   The previous session did not get to them; it spent itself on the merge queue.
   Do NOT repeat that.** #1987 is closed (2026-09-02). Take the other three in this
   order, ahead of every PR below:
   - **#2127** — reviewer assignment is frozen repository-wide whenever no orchestrator
     marker is open, and the refusal blames GitHub rather than naming the real cause.
     Structural-adjacent tooling; it blocks every future session that starts cold.
   - **#1966** — high-churn tables cannot do HOT updates, plus ~1.4 GB of indexes whose
     usage counters cannot be trusted. Read its own correction section first: the
     repack ask from #1722 was withdrawn, and the real finding is different and larger.
   - **#1984** — the merch-group reclassification tracker, which needs the owner's three
     answers before implementation can move. Raise those in the §0 message.
4. **Then take PR #2183** (smallest of the four ColdLion PRs), then #2185, then
   #2186, then #2145. For each, in order: rebase onto the current main tip →
   re-run version, object-collision, SQL and contract checks from the moved base →
   acquire the preview lock **through the workflow only** → apply → read the
   resulting objects back from the live catalog → get an exact-head external
   review → release preview → dispatch `guarded-migration-merge.yml` with the
   pull request number and head SHA. *You'll know each one worked when*
   `gh pr view <n> --json state` reports `MERGED` and the run concluded `success`.
5. **After each merge, release the author claim** and record that the reserved
   version stays permanently spent — including any superseded version that was
   never applied.
6. **Expect a version-ordering refusal on at least one of the four**, for the
   reason in §5. Supersede through the tool, never by hand-editing a claim fence.
   *You'll know it worked when* `check-sql.sh` exits 0 from the moved base.
7. **Retire the finished worktrees** with `scripts/reap-merged-worktrees.mjs`
   (dry run first). Note it refuses while any orchestrator marker is open, which is
   correct — do it during your own closeout. *You'll know it worked when* the dry
   run lists only worktrees whose PRs GitHub reports as merged.

---

## 7. Constraints and gotchas in force

- **Every structure change is authored here, on a branch, through a PR.** The
  guarded merge workflow is the only merge path.
- **Production is read-only to AI sessions**, always, unless Albert names the exact
  resource and action in the current chat.
- **The repository is PUBLIC.** Check every diff for customer identifiers, personal
  data, licensed rows and credential values before sending it anywhere.
- **Preview is shared.** One PR at a time; take and release the lock through the
  workflow. Taking it by hand makes the run refuse itself, and an abandoned preview
  version blocks the lane for everyone afterwards.
- **Never bare `git stash` / `git stash pop`** — the stack is shared across
  worktrees. Prefer a WIP commit.
- **Never delete another session's untracked files**, and never `git clean` in a
  worktree you do not own.
- **Never resolve a full-body `CREATE OR REPLACE` conflict mechanically.**
  Re-derive the later change from the newly merged body.
- **A reviewer verdict is void if any decision word (APPROVE/REVISE/REJECT)
  appears anywhere but the final line**, and the verdict line must carry the head
  SHA and be bare — not fenced, not inline-quoted.
- **Never gate on a judgement Albert cannot make.** He is a business owner, not a
  programmer.
- **Claude merges PRs, never Albert.**

---

## 8. Access and environment

- `gh` authenticated as `u2giants`. **No `popcre` credential exists on this
  machine** and none is in the vault — `popcre/designflow-tracking#39` was
  therefore filed into the popcre-owned repository under the `u2giants` login. No
  identities were mixed. Left as is deliberately; re-filing would lose its history.
- Supabase Management API reachable for both production (read-only) and preview.
- Secrets live in **1Password vault `vibe_coding`**. Values move only through pipes
  or protected files — never chat, arguments, output, logs or commits. Serialize
  `op` calls; never fan them out in parallel.
- Reviewer wrappers live in `/c/repos/ai-devops/bin/`. See §4 items 10 and 11 for
  the two traps.
- Rescued `lane-2136` index preserved in this session's scratchpad under
  `lane-2136-rescue` — `staged-index.patch`, the original HEAD, and the one file
  that looked unique (since confirmed present on eight remote branches). It is
  scratch, not durable; nothing depends on it.

---

## 9. Open questions and risks

- **#2138 is deliberately left open.** PR #2150 fixed only the
  `filter_effective_assets` timeout. The tag-facet half lives on a different
  function and is tracked as **#2151**. Close #2138 only when #2151 lands.
  (Decided 2026-09-03.)
- **The `filter_effective_assets` timing improvement was never reproduced.**
  Results are proven identical before and after — 126,790 rows on the empty filter,
  40,591 on a licensor filter, against a corrupted control that diverged by 10,240 —
  but the read-only role cannot execute the function, so the speed claim rests on
  the query plan alone. **Do not let anyone upgrade "same rows" into "faster".**
- **PR #2149's verify block is data-dependent.** Its trigger half needs an existing
  workflow row, so a from-empty replay stops at that file rather than silently
  skipping the proof. Fail-closed, but worth knowing.
- **Two cosmetic count errors left in the ColdLion plan**, deliberately: it says
  "four feeds have a complete structural destination" where it now reads five, and
  "the five stored columns" is ambiguous between source and provenance columns.
  Both harmless in direction. Fixing them would have moved the head and voided a
  standing approval. (Decided 2026-09-03.)
- **The reviewer pool's real capacity is three, not five** (§0 item 4). Budget
  roughly ten extra minutes per PR for a dead draw and its governed replacement.
- **A rehearsal is void once a later migration replaces what it validated.** None
  of tonight's are stale, but the next session inherits that rule.

---

# (b) Sub-agent work, separated by agent

### Agent: `a881cfe4a3ca1ab28` — "Get valid review for PR 2155" (the review/rehearsal lane)

- **Asked to do:** originally to obtain a valid in-scope review for PR #2155;
  extended across the session into the single review-and-rehearsal lane for
  every PR merged tonight.
- **Actually did:** diagnosed the `resolve_base` mis-scoping defect and fixed it
  in `popcre/ai-devops` PR #237 (`7b39f006`); took PRs #2155, #2187, #2170, #2158,
  #2156, #2150 and #2149 through rebase, guard re-runs, preview rehearsal,
  read-back proof and exact-head external review; rewrote the Link-header parser
  strictly after four rounds of holes; performed the governed supersessions for
  #2156 (`20260903014958` → `20260903072252`) and #2149 (`20260903002322` →
  `20260903083204`); filed **#2188** and `popcre/designflow-tracking#39`; released
  claims #2153 and #2143.
- **Found:** the review sandbox drops branch pointers, so every review in every
  repository was scoped against `HEAD~1`; three fail-open variants in the PR #2155
  parser plus two more after the rewrite request; the supersession title-format
  defect; the DesignFlow vocabulary lag; and that the "missing" fourth
  `source_resolution` foreign key was removed deliberately on an owner ruling.
- **PR / branch:** no branch of its own; worked on each PR's branch in turn.
- **Worktree:** finished. Its per-PR worktrees are safe to reap once the marker
  is closed.
- **Deliberately did NOT do, and why:** never merged and never dispatched the
  guarded merge workflow — those stayed with the orchestrator throughout. Did not
  clean or reset any worktree without explicit authority, and refused to file the
  `source_resolution` follow-up after checking the premise. Correctly refused an
  orchestrator instruction on evidence; that refusal was right.

### Agent: `aba180eea8553a5d3` — "Fix third link parser finding"

- **Asked to do:** fix the third fail-open variant found in the PR #2155 Link
  parser, with red-then-green proof.
- **Actually did:** commit `2bca5d8f` — refused a link value carrying no relation
  through the existing refuse path, with tests covering a bare `<url>`, a
  `title=`-only value, and a two-value header whose second value has no rel.
  Corrected 21 stale line numbers in the throughput truth audit.
- **Found:** nothing beyond its brief.
- **PR / branch:** `claude/2152-matching-refs-pagination`, merged as part of #2155.
- **Worktree:** finished.
- **Deliberately did NOT do, and why:** no review, no merge, no dispatch — out of
  its remit by instruction. Its fix was superseded by the strict rewrite two rounds
  later, which is the correct outcome and not a failure of this agent.

---

## Closeout record

- **Secrets sweep: swept, nothing new.** No credential appeared in chat, in any
  diff, or in an untracked file this session. The scratchpad rescue files hold a
  git patch and a handoff document, no secrets. Nothing was added to `vibe_coding`.
- **Docs pass:** the ColdLion rulings and the seasons defect warning were the
  documentation work of this session and shipped in PR #2187 — `AGENTS.md`,
  `docs/coldlion.md`, `docs/coldlion-open-questions.md`, the endpoint reference and
  the landing-schema plan. Nothing else outside this handover is now stale.
- **Sweep:** issues #2152, #2147, #2146 and #2136 closed with their merge commits;
  #2138 commented and deliberately left open; the predecessor's closeout file for
  marker #2121 retired under the successor rule (its issue #2160 is closed with the
  outstanding items carried into §3 and §6 above).
- **Queue seeded:** issue **#2189** carries the outstanding work; #2186, #2185,
  #2183 and #2145 each retain their own open issue (#2173, #2175, #2177, #2123).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
