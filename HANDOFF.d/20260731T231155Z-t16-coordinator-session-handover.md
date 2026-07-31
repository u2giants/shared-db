# COORDINATOR HANDOVER — `u2giants/shared-db` — 2026-07-31 23:11 UTC

- **Machine:** `t16` (Windows 11, user `ahazan2`, PowerShell 7 primary)
- **Agent:** coordinator session (Claude Opus 5), plus 19 dispatched sub-agents
- **Repo:** `u2giants/shared-db` — the canonical repository for the ONE shared
  Supabase Postgres database
- **This file is WRITE-ONCE.** Do not edit it. If you need to correct something in
  it, write your own new file in `HANDOFF.d/` and say what you are superseding.
  The shared root `HANDOFF.md` was deliberately NOT rewritten by this handover.
- **`HANDOFF.md` remains authoritative** for backlog detail, findings, and history.
  This file is the coordination state of ONE session. Where the two disagree about
  a durable fact, `HANDOFF.md` wins — except for the re-verified facts in §3 of
  this file, which were checked live at write time and are newer.

> **STRUCTURE.** Part (a) is the 9-section standard handover. Part (b) is one
> clearly headed block per sub-agent — 19 of them. A coordinator handover missing
> part (b) is incomplete. Read both.

---
---

# PART (a) — THE 9-SECTION HANDOVER

---

## 1. What this application is

There is no "application" in this repo. `u2giants/shared-db` is the **single
canonical source of truth for one shared Supabase Postgres database**, project ref
`qsllyeztdwjgirsysgai` (production). Four separate applications read and write that
one database at the same time:

| App | What it is | Who uses it |
| --- | --- | --- |
| **Poppim** (`poppim-web`) | Product Information Management | Internal product/merch team |
| **PopCRM** (`popcrm-web`) | Customer relationship management | Sales |
| **PopDAM** (`popdam3`) | Digital Asset Management — artwork, style guides, licensed property assets | Design + licensing |
| **DesignFlow PLM** ("dflow") | Product Lifecycle Management, Angular + AG-Grid | Product development, factories, sales |

Because four apps share one schema, **every schema change is a cross-app data
contract**. That is why this repo exists and why the rules below are strict.

**The absolute rule (from Albert's global instructions):** any schema/DDL change to
the shared Supabase backend — column, table, view, RPC, trigger, RLS policy, seed,
migration, or cross-app data contract — is authored **here**, on a branch, with a
PR, applied to **preview first**, and merged by the AI session itself. **Never** add
an inline migration in an app repo (e.g. a Sequelize `models/db.js` startup
`ALTER`). **Never** run a direct `ALTER` / `CREATE` / `DROP` via psql or the
Supabase MCP against the shared database. If an app repo's docs still teach the
inline-migration pattern, those docs are stale — shared-db wins.

**Environments:**

- **Production:** Supabase project ref `qsllyeztdwjgirsysgai`. Migration ledger is
  `supabase_migrations.schema_migrations`.
- **Preview:** Supabase project ref `rjyboqwcdzcocqgmsyel`. This is where every
  change is rehearsed. It is **not** a clean room right now — see §3.
- **Migrations:** `supabase/migrations/<version>_<name>.sql`, version =
  `YYYYMMDDHHMMSS`. 386 files as of this handover.
- **CI:** `.github/workflows/shared-supabase-migrations.yml`. It contains a step
  literally named **"Refuse production apply"** — CI **cannot** apply to production
  by design. Production promotion is a **local, bounded, manual** procedure
  prescribed by `AGENTS.md` §5.1. See §7.

**The operating model this session ran under:** ONE coordinator session that does
no work itself and dispatches every task to an isolated sub-agent in its own git
worktree under `.claude/worktrees/`. That model is defined by the
`shared-db-orchestrator` skill. Anyone who is NOT the coordinator files a request
in the `## REQUEST QUEUE` of `COORDINATOR_INTAKE.md` instead of starting work.
That file also holds intake handovers from sessions that were told to stop.

**The `ColdLion` workstream** — which dominates this repo's backlog — is the
ingestion of the **ColdLion ERP** (the company's system of record for licensors,
licensed properties, vendors, and merchandising groups) into the shared database,
so all four apps agree on one taxonomy. It is being switched on in numbered steps;
**Step 8 is the production switch-on and it is NOT yet switched on.**

---

## 2. What we set out to do this session, and why

**Business goal:** clear enough of the ColdLion backlog that Step 8 (production
switch-on of the licensor/property feed) becomes an answerable question for Albert,
and unblock the DesignFlow RFQ-groups request that Sales needed.

**Technical objectives, in the order they were taken:**

1. Establish ground truth — the docs in this repo were suspected stale.
2. Re-run the ColdLion 18-case promotion rehearsal against the **current** function
   body (the celebrated "14/14 passed" evidence described an older function).
3. Re-derive the **true** production migration manifest (the plan claimed 4 pending
   migrations; nobody had verified that).
4. Deliver the `rfq_groups` column on `public.style_tracker_rows_with_bridge`.
5. Close the highest-value backlog items that block Step 8 (B8, B14).
6. Record Albert's rulings so they cannot be relitigated.
7. Hand over cleanly, with the `REQUEST QUEUE` seeded.

**What triggered it:** a prior session left `HANDOFF.md` and `COORDINATOR_INTAKE.md`
with empty queues, and a fresh coordinator read them and reported "there is no
pending work" — wrong by about twenty jobs. That failure is why seeding the queue is
now a **required completion criterion** of every coordinator handover
(`COORDINATOR_INTAKE.md` §B2.0).

---

## 3. Current state — what is true right now

### 3.1 Facts re-verified at write time (2026-07-31 ~23:11 UTC)

Every one of these was re-checked live by this handover agent, not copied:

| Fact | Value | How verified |
| --- | --- | --- |
| `origin/main` tip | `c10167e48845d1e08211d3f130f74cd31c0dfcc5` | `git fetch origin --prune` then `git rev-parse origin/main` |
| Tip commit subject | `fix(coldlion): bound the cycle-state probe and stop a client tooling fault tripping the breaker (B14) (#367)` | worktree checkout of that SHA |
| Migration files | **386** | `ls supabase/migrations \| wc -l` |
| Max migration version | **`20260731230000`** | sorted version list, tail |
| Duplicate versions | **0** | `sed \| sort \| uniq -d \| wc -l` |
| Open PRs | **#365** and **#366** | `gh pr list --state open` |
| Commit identity | `Albert Hazan <u2giants@users.noreply.github.com>` | `git var GIT_COMMITTER_IDENT` |
| Git worktrees registered | **33** entries in `git worktree list` | `git worktree list \| wc -l` |

**CORRECTIONS TO THE COORDINATOR'S OWN REGISTER (drift found at write time):**

1. **PR #366 is now `MERGEABLE`.** The register recorded its mergeability as
   `UNKNOWN` at 23:09 UTC — GitHub had simply not finished computing the merge
   commit yet. It has now. **This does not change the instruction: do NOT merge it.**
   It is an un-ingested intake handover, not reviewed work.
2. **Worktree count is 33, not 21.** The recon agent (block 1) counted 21 clean
   worktrees earlier in the session; `git worktree list` now returns 33 entries.
   The delta is this session's own dispatched agents, several of which finished but
   left their worktree registered. **No sweep was performed — see §9 / the
   deliberate decisions.** Do not treat 33 as a problem to fix reflexively; read
   B11 first.
3. **`HANDOFF.d/` did not exist before this file.** This is the first file in it.
   The convention (one write-once file per session, named
   `<UTC>-<machine>-<agent>-<slug>.md`) is introduced here so concurrent sessions
   stop fighting over the single root `HANDOFF.md`.

Everything else in the coordinator's register re-verified as stated.

### 3.2 ⚠️ HAZARD — FIX THIS FIRST, BEFORE ANYTHING ELSE

**The shared checkout `C:\repos\shared-db` is parked on branch
`intake/coldlion-comparison-handover-20260731`, NOT `main`.**

It is clean (`git status --porcelain` empty), so nothing is at risk of being lost.
But the next session that opens that directory and assumes it is on `main` will
read stale files, branch from the wrong base, or commit to someone else's intake
branch. **This is the single most likely way tomorrow's session goes wrong.**

That branch is the head of **open PR #365**. Do not delete it. Do this:

```bash
cd C:/repos/shared-db
git status --porcelain          # MUST be empty before you switch
git fetch origin --prune
git switch main
git merge --ff-only origin/main
git rev-parse HEAD              # expect c10167e… or newer
```

**You'll know it worked when** `git rev-parse --abbrev-ref HEAD` prints `main` and
`git status` reports up to date with `origin/main`.

### 3.3 Production database state

Verified read-only at ~22:45 UTC by a dedicated verifier agent (part (b) block 16),
which confirmed the project ref via `get_project_url` before reading anything:

- Migration ledger: **359 rows**, head **`20260731230000`**.
- **Exactly 27 migrations are pending** (present as files, absent from the ledger).
  This is 18 ColdLion + 9 unrelated. **The "~15 unrelated" figure that appears in
  older docs is WRONG.** The authoritative list is
  `docs/coldlion-production-migration-manifest-20260731.md` (PR #360, independently
  re-derived and confirmed CORRECT by a second agent).
- **Production was NOT mutated** by any migration this session other than the one
  deliberate promotion below. Evidenced four ways: ledger count and max unchanged
  across the window, zero orphan rows, four objects belonging to pending migrations
  probed and confirmed **absent**, and the only dispatch run in the window logged a
  **dry run** that failed at the `--include-all` refusal.
- **ONE migration was promoted to production this session:** `20260731230000`
  (RFQ groups). Bounded, dry-run-listed-exactly-one-file, post-verified. See part
  (b) blocks 12 and 13.

**The 442-row `DELETE FROM ingest.raw_record` hit PRODUCTION.** Proved three ways:
97 survivors matching the reported post-delete count; `pg_stat_all_tables.n_tup_del`
= exactly 442; and migration `20260722171500` explicitly states it left `raw_record`
untouched. The deleted rows are raw payloads from the pre-2026-07-22 buggy
`/vendors` endpoint and are **NOT recoverable by re-import**. Derived data survived
intact: `plm.vendor_exclusion` 435 rows, `plm.erp_vendor` 97, `core.factory` 93.

**➡️ Albert has ruled this was INTENDED AND CORRECT. It is NOT an incident. Do NOT
propose a restore, PITR, or corrective migration.** See §9 decision 1.

**What could NOT be determined**, and is unlikely ever to be: the wall-clock time of
either the delete or the promotion (the ledger carries no timestamp and commit
timestamps are disabled in this repo), the preview's exact state at the time, and
whether any out-of-ledger DDL ran — that last one is **undetectable in principle**.

### 3.4 Preview database state — NOT clean

Preview `rjyboqwcdzcocqgmsyel` carries the ColdLion rehearsal's residue. Do not
assume a blank slate:

- Two **committed** idempotent promotion cycles.
- Append-only quarantine rows, scoped to their own `sync_run_id`s (so they will not
  contaminate a new run that uses a fresh `sync_run_id` — but they WILL show up in
  unscoped counts).
- `ingest.sync_run` failure rows and circuit-breaker events left by the ENOBUFS
  defect described in §4/§5.
- The circuit breaker was **reset twice by an agent**, so `reset_by` names a
  sub-agent, not a human. Anyone auditing "who reset the breaker" will otherwise
  reach a wrong conclusion.
- The RFQ view migration `20260731230000` is applied there too.

### 3.5 Open PRs — DO NOT MERGE EITHER

- **#365** — `intake/coldlion-comparison-handover-20260731` — "docs: intake handover
  — ColdLion comparison session stopping". MERGEABLE.
- **#366** — `intake/coldlion-mg07-styleguide-readonly-20260731` — "docs: intake
  handover — ColdLion MG07 Style Guide doc lookup (read-only)". MERGEABLE (was
  UNKNOWN 2 minutes earlier).

**Both are INTAKE HANDOVERS from uncoordinated sessions. They have NOT been
ingested.** They were left open **deliberately** — ingesting an intake block means
verifying every claim in it against the live repo and live schema, and this session
ran out of runway to do that honestly. Merging them without verification would
launder unverified claims into `main`.

**Next coordinator: ingest them properly** — read each block, verify each claim,
then either dispatch the work or explicitly drop it, and move the block to
`## TAKEN OVER` in `COORDINATOR_INTAKE.md` with a line saying what you did.

### 3.6 🔴 LIVE ALARM — unactioned

**The preview ColdLion alert monitor has failed every hour since 20:02 UTC.** The
message is:

> An undelivered ColdLion taxonomy alert exists. Human response owner: Albert Hazan.

It is **almost certainly residue** of the ENOBUFS circuit-breaker trip in preview
(§5, defect 1) — i.e. a false alarm about a defect that has since been fixed. But it
has not been proven to be residue, it names Albert as the response owner, and it is
red right now. **Do not silence it without establishing what it is.** The right
first move is read-only: find the undelivered alert row in preview, check whether
its `sync_run_id` matches one of the failed rehearsal runs, and only then decide.

### 3.7 What is committed / pushed / deployed

- All 11 merged PRs listed in §5.6 are on `origin/main` at `c10167e`.
- The single production promotion (`20260731230000`) is applied and verified.
- The mirror sync reached **all 9 consumer repos** after that promotion.
- This handover itself: on branch `agent/coordinator-handover-20260731-2330`, in a
  worktree at `.claude/worktrees/coord-handover-2330`, opened as a PR and **not
  merged** — this session does not merge on the way out.

---

## 4. Everything we tried that did NOT work — MANDATORY SECTION

**This is the most valuable section in the file.** Every entry cost real time. Read
it before you start; several of these will bite you within the first hour.

### 4.1 Trusting `HANDOFF.md`'s own ground-truth table

`HANDOFF.md` carries a table of "current facts" — main SHA, PR states, counts. **It
was stale about the very commit that contained it.** A document cannot record the
SHA of the commit that adds it. It also states in **two places** that `ai-devops`
PR #1 is open; **it is MERGED**.

**Rule going forward:** re-derive `git rev-parse origin/main`, `gh pr list`, and the
max migration version yourself at the start of every session. Never quote the
table.

### 4.2 Resuming a sub-agent that died mid-task

The C2 production-manifest agent died once (connection drop), was resumed, and
**died a second time** (600-second stall). Resuming a dead agent produced a second
death and, worse, an agent that could not say which project ref it had read or
whether it had mutated anything.

**What worked instead:** superseding it with a **fresh, independent, read-only
verifier** that re-derived the answer from scratch and could state its evidence.
That verifier confirmed the output was CORRECT. **Prefer supersede-with-verifier
over resume.**

### 4.3 `SET LOCAL ROLE anon` as a privilege test — IT LIES

Over a superuser pooler connection, `SET LOCAL ROLE anon` does **not** reliably
constrain privilege the way you expect, so a query that "succeeds as anon" proves
nothing. The RFQ promotion agent caught this itself.

**Use `has_table_privilege('anon', '<relation>', '<privilege>')` instead.** That is
what actually proved `anon` is denied on the RFQ view.

### 4.4 `grep` on `tools/promote-coldlion-source-owned.mjs` returns NOTHING

That file contains **deliberate NUL separators**. `grep` therefore classifies it as
a binary file and prints nothing (or "Binary file matches"). This produced a **false
"missing function" alarm** during the #367 review — someone concluded a function had
been deleted when it was present the whole time.

**Use `grep -a`** (treat binary as text) on that file. The coordinator verified
independently that no content was lost.

### 4.5 Estimating the probe page size instead of measuring it

Sized the cycle-state probe page from an estimate — **wrong twice**. The coordinator
guessed 870–1,300 bytes/row; the implementing agent guessed ~700 B/row.

**The real answer, measured from 570 real records already sitting in the repo:
mean 496 B, p95 536 B, max 581 B.** The data to measure was there the whole time.
**Measure; do not estimate, and do not accept an estimate in review.**

### 4.6 Loading the `mcp__visualize__read_me` tool as coordinator

That tool returns **79,689 characters**. Loading it into a coordinator's context —
whose entire job is to hold the register of 19 sub-agents — would have destroyed the
register outright.

**A coordinator must not load large-payload tools.** Use a markdown table. This
generalises: as coordinator, before calling any unfamiliar tool, consider its output
size.

### 4.7 A mutation-testing harness that clobbered its own source file

The #367 agent's mutation harness (originally shell-based) **overwrote a source file
mid-sweep**. It caught the damage itself, rebuilt the file from git plus its own
patches, and **rewrote the harness in Node**. It then self-reported the incident.

The coordinator independently verified nothing was lost: files distinct by SHA-256,
no cross-contamination between sources, and every named function present on main
still present on the branch. **Write mutation harnesses in Node, not shell**, and
always restore + prove byte-identical with a hash.

### 4.8 Byte-comparing a file full of em dashes by character index

The conditions-closer agent produced a **false negative** by comparing a character
index against a byte offset in a UTF-8 file containing em dashes (3 bytes each). It
self-corrected. **Compare bytes to bytes, or hashes to hashes — never mix units.**

### 4.9 Believing the "66 unmatched property codes" premise

The brief said 66 unmatched ColdLion property codes. **It is 33.** ColdLion now
offers 285 property codes, not 322. Acting on the stale number would have produced a
table twice the size of reality and a correspondingly wrong ask to Albert.

### 4.10 Using PopDAM asset counts as a measure of property importance

Discarded, correctly. **PopDAM's property codes are a colliding code space** — its
`BB` is Big Bird, ColdLion's `BB` is The Brady Bunch. Presenting PopDAM volumes
alongside ColdLion codes would have silently misled Albert about which properties
matter.

### 4.11 The aggregate/hash design for the cycle-state probe

Rejected **with evidence**, not on taste: the planner decides row by row and
consumes all 14 probe keys, so no aggregate or hash preserves what it actually
needs. Do not re-propose it.

### 4.12 Assuming "no GitHub Actions run" means a promotion did not happen

A reviewer challenged the RFQ production promotion because no Actions run existed
for it. **That is the expected state for every production promotion this repo has
ever done** — the workflow contains a step named "Refuse production apply".
`AGENTS.md` §5.1 prescribes the local procedure that was used. The challenge was
right to make; the conclusion was wrong.

### 4.13 A worktree sweep — tried on a previous occasion, caused harm

A sweep earlier today **deleted a live agent's workspace**. That is the origin of
backlog item **B11**: a paused agent is indistinguishable from a finished one. No
sweep was performed this session as a result. See §9.

---

## 5. Root causes and key findings

### 5.1 The four tooling defects that had left the ColdLion lane completely dead

Found by the rehearsal agent (block 5). This is the headline technical finding of
the session — the lane had been dead and everyone thought it was a logic problem.

1. **`runSql` had no `maxBuffer`.** A 1,305,075-byte probe overflowed Node's default
   1 MiB child-process buffer. The failure surfaced as **failure with EMPTY stderr**,
   which the caller recorded as a durable fault and which **auto-tripped the circuit
   breaker**. Scored 2/18 until diagnosed. This is an ENOBUFS-class defect.
2. **`supabase db query` defaults to a box-drawing table, not JSON.** 16 of 18 cases
   scored FAIL **while the database was answering correctly**. The test harness was
   misreading correct answers.
3. **`parsePhase6FunctionResult` could not unwrap `--output json`** — the fix for
   defect 2 was not sufficient on its own.
4. **Cases 3, 11 and 12 were stale** against the `20260731200000` tie-break change,
   so the guard they were supposed to exercise **was never reached**.

**Result after fixing all four: 18/18 PASS, including cases 10a–10d for the first
time ever executed.** All four post-rehearsal migrations (`20260731163000`,
`20260731180000`, `20260731190000`, `20260731200000`) were confirmed present in the
live `pg_proc.prosrc` — **read from the function body, not inferred from the
ledger.** That distinction matters: the ledger says a migration was applied, the
function body proves what is actually running.

### 5.2 The ENOBUFS fix moved the cliff rather than removing it — B14

An independent review of PR #362 established that defect 1 **is a production risk**,
by tracing `runSql` → `tools/promote-coldlion-source-owned.mjs` → the production
workflow, and confirming there is **no separate production client**. The same code
path serves production. And the first fix only **raised** the buffer: an ENOBUFS
still throws, still records a durable failure, still auto-trips the breaker.

That became backlog **B14**, and B14 was then **fixed properly** in PR #367 by
paging + spawn-fault classification:

- Bounded single retry from page 0 (`CYCLE_STATE_MAX_ATTEMPTS = 2`).
- A snapshot race → **exit 5, recording nothing** (previously a benign snapshot
  overlap was recorded as a failure).
- A duplicate key surviving a clean restart still counts as a **REAL recorded fault**
  — the retry does not swallow genuine errors.
- One `SPAWN_MAX_BUFFER_BYTES` applied to **both** spawn paths (round 1 had it on
  only one of two, leaving the psql path at the original 1 MiB cliff).
- Page size **measured** (§4.5), not estimated.
- **22 of 22 mutations killed.** CI 428/428 on Linux.

**B14 is RESOLVED and is no longer a Step 8 blocker.**

### 5.3 The production lane cannot produce a plan today — NEW Step 8 blocker

**6 of the 14 promotable ColdLion migrations sort OLDER than production's ledger
head.** The Supabase CLI refuses out-of-order migrations unless passed
`--include-all`, and **the workflow does not pass it**. The one production dispatch
run in the window logged exactly this: a dry run that failed at the `--include-all`
refusal.

**This needs a WORKFLOW CHANGE, not a retry.** It is not a transient failure and it
will not resolve itself. Nobody has designed the fix yet. Note the safety tension:
`--include-all` is exactly the flag that makes out-of-order application possible,
which is also how you apply something you did not intend — whatever is designed must
be bounded to an explicit file list.

### 5.4 The migration ordering trap is real

`20260729120000` sorts **after** `20260728174500` but depends on objects the latter
creates. Against production — where neither is applied — the unguarded `GRANT` in
`20260729120000` targets functions that do not exist, raising **`undefined_function`
(SQLSTATE 42883)**. Confirmed by the C2 verifier. This is a live hazard for any
production apply of the pending 27.

Two related **false alarms were cleared** and should not be re-raised: a function
name that appears only as a **string literal in an allowlist**, and a migration
version referenced only in a **prose comment**.

### 5.5 The RFQ groups view — findings

- **The brief contained a spec error.** It said to read the group link from
  `RFQGroup_id` on the item table. **That column does not exist.** The real foreign
  key is `rfqItem_rfq_group`. An agent that had followed the brief literally would
  have shipped a broken migration.
- **Three designs were measured, not guessed:** correlated subquery ~91 s;
  correlated + index ~250 ms; **pre-aggregate join ~118 ms — shipped, no index
  required.**
- A reviewer proved **from the SQL, not from a row count**, that the pre-aggregate
  join cannot change the view's row count under **any** data condition: the
  `GROUP BY` guarantees a unique join key, the `LEFT JOIN` preserves unmatched rows,
  and blank/NULL codes are excluded on both sides. This is the right standard of
  proof for a view change — a matching row count is evidence, not proof.
- Four review findings, all confirmed against the file: a **dead assertion** (a
  second `v_fuzzy_hit` computed and never asserted); **hard-coded 1900–2200 count
  bounds** that would have **aborted a production apply on ordinary data drift**;
  a **missing `notify pgrst, 'reload schema'`**; and the **definer-rights view
  extending `dflow` readability to all authenticated users across all four apps**.
  All four fixed.
- **The hard-coded bounds decision was vindicated within hours:** production measured
  **15,534** rows where preview measured **15,533**. The data had already drifted. A
  hard-coded bound would have aborted the promotion.
- Post-promotion verification: ledger row present; live view has `rfq_groups`;
  **48 → 49 columns with nothing lost**; `MFZ88KMSC01` → "Family Dollar July 2023";
  multi-group values deduped newest-first; unmatched rows `[]`; row count 15,534
  unchanged; `anon` denied via `has_table_privilege`.
- Before promoting, the live production view definition was read and confirmed to
  match base migration `20260721143000` **exactly (48 columns)** — this is what
  closed the silent-column-loss risk. **Do this before any view replacement.**

### 5.6 What merged this session

**11 PRs landed on `origin/main`:** #355, #356, #357, #358, #359, #360, #362, #363,
#367, #369, #370.

Of those, **this coordinator merged**: #358, #360, #362, #363, #367, #369, #370.
**#356, #357 and #359 came from other sessions**; #355 also landed in the window.

### 5.7 The unmatched ColdLion property codes — the premise was stale

**33 unmatched codes, not 66.** Table now exists at
`docs/coldlion-unmatched-properties-by-licensor-20260731.md` (PR #369).

- **27 of the 33 were created in ColdLion on 2026-07-30.** A licence created
  yesterday cannot be lapsed — which dissolves most of the "lapsed licence" worry.
- **NASA, ZAG and Frida Kahlo — the three named lapsed-licence risks — are NOT in
  the unmatched set.** NASA is a *licensor*, and Frida Kahlo already matches.
- Breakdown by licensor: **Viacom/Paramount 27, Warner Bros 2 (`EX`, `LB`),
  NBCUniversal 2, Peanuts 1, DC 1.**
- **Recommendation: admit all 33.** Only **5 rows genuinely need Albert** — `AM1` /
  `AM2` (Anchorman), `MGM` (Mighty Mouse), `WND` (It's a Wonderful Life), `EP`
  (Emily in Paris).
- **Data-quality flag for PopDAM:** it files 8 Exorcist assets under NBC when
  **Warner Bros** is correct.

### 5.8 The owner ruling needed a scope guard nobody had thought of

Albert's ruling "ColdLion ERP data is canonical, follow it" could be read as licence
to **delete audit and evidence tables** when the ERP no longer lists something. The
recording agent added an explicit exclusion list to `AGENTS.md` §6.3:

`plm.coldlion_promotion_audit`, `plm.coldlion_promotion_quarantine`,
`plm.taxonomy_parallel_observation`, `plm.taxonomy_circuit_breaker_event`,
`app.db_data_admin_audit_event`.

It also found **5 more places** beyond the 2 already known that still assert the
bronze layer is immutable. **Two of them are LIVE documents a future session could
act on and still need a supersession pointer: `HANDOFF.md:5381` and
`fix_schema_for_api.md:40,159`.** The other three are lower risk.

It deliberately did **not** edit the two applied migrations carrying stale comments
(`20260722171500`, `20260722213000`) — editing an applied migration changes nothing
in the database and desynchronises the file from the ledger.

### 5.9 B6 is the unfixed root cause of a real four-way collision

**Two PRs that replace the same database function both pass CI, and the second merge
silently erases the first.** Nothing detects it. This already happened once (a
four-way collision). **It would happen again today, unchanged.** No guard exists.
This is the highest-value unstarted backlog item.

### 5.10 The backlog was under-counted

A read-only agent read all **5,982 lines** of `HANDOFF.md`, produced the B1–B14
status list, and found **~19 live items the coordinator's own matrix was missing**.
Do not assume the matrix is complete; the file is authoritative.

---

## 6. Exact next steps

Numbered, in order. Each ends with a verification gate.

**0. Read this file, then `HANDOFF.md`, then `COORDINATOR_INTAKE.md`'s
`## REQUEST QUEUE`.** Do not skip §4.
✅ *You'll know it worked when* you can say why `grep` returns nothing on
`promote-coldlion-source-owned.mjs`.

**1. Un-park the shared checkout.** Run the commands in §3.2.
✅ *Gate:* `git rev-parse --abbrev-ref HEAD` prints `main` in `C:\repos\shared-db`.

**2. Re-derive ground truth before believing anything.**
```bash
git fetch origin --prune && git rev-parse origin/main
gh pr list --state open
ls supabase/migrations | sed 's/_.*//' | sort | tail -1
ls supabase/migrations | sed 's/_.*//' | sort | uniq -d   # must be empty
```
✅ *Gate:* you have your own SHA, PR list, and max version written down.

**3. Diagnose the hourly preview alert-monitor failure (§3.6). READ-ONLY FIRST.**
Find the undelivered ColdLion taxonomy alert row in preview
`rjyboqwcdzcocqgmsyel`; check whether its `sync_run_id` matches one of the failed
rehearsal runs from the ENOBUFS incident.
✅ *Gate:* you can state, with the row as evidence, whether it is residue or a real
undelivered alert — **before** anything is acknowledged or cleared.

**4. Ask Albert the 5 property-code contract questions. THIS IS READY TO ASK.**
Point him at `docs/coldlion-unmatched-properties-by-licensor-20260731.md`. Ask only
about `AM1` / `AM2` (Anchorman), `MGM` (Mighty Mouse), `WND` (It's a Wonderful
Life), `EP` (Emily in Paris). Recommend admitting all 33 codes.
⛔ **Do NOT re-ask the six licensor-alias rulings — already ruled in PR #352. Do NOT
re-open Sesame Workshop → Sesame Street.**
⛔ **Do NOT re-ask `EX` / `LB` / `JL`** — Laura already answered them correctly in
round 1; the gap is ours, not hers.
✅ *Gate:* Albert's answers recorded in `AGENTS.md` or a dated doc, and merged.

**5. Re-offer the "prove your database target" rule (§9 decision 4).** Albert
**declined to answer** whether to add a rule requiring an agent to prove which
database it is connected to before any `DELETE` / `UPDATE` / `DROP`. **Silence is
not approval.** The proposed text is in the session transcript. Re-offer it plainly.
✅ *Gate:* an explicit yes or no from Albert, recorded with the date.

**6. Ingest PRs #365 and #366 properly.** Verify every claim in each block against
the live repo and live schema; then dispatch or explicitly drop; then move each block
to `## TAKEN OVER` in `COORDINATOR_INTAKE.md` with a line saying what you did. Only
then merge.
✅ *Gate:* both blocks in `## TAKEN OVER`, both PRs closed or merged, and you can
name at least one claim you verified in each.

**7. Design the production-lane fix (§5.3).** The workflow cannot produce a plan
because 6 of 14 promotable ColdLion migrations sort older than the ledger head and
`--include-all` is not passed. Design a **bounded** fix — explicit file list, never a
blanket `--include-all`.
✅ *Gate:* a written design in `docs/`, reviewed by a second agent, plus a dry run
that **produces a plan** naming exactly the intended files.

**8. Fix B6 — the cross-PR object collision guard.** §5.9. Highest-value unstarted
item; the failure it prevents has already happened.
✅ *Gate:* a CI check that FAILS on a deliberately constructed pair of PRs replacing
the same function, and passes otherwise. **Prove the guard fires** (that is B7's
whole point).

**9. Chase Albert to run "sync my dotfiles" on his other machines.** `ai-devops`
PR #1 is **MERGED** (`HANDOFF.md` says open in two places and is WRONG). Only the
sync half remains. Until it is done, **other machines run shared-db sessions without
the coordination rules** — the exact condition that produced the chip incident.
✅ *Gate:* Albert confirms `shared-db-orchestrator` and `shared-db-handover` resolve
on at least one other machine.

**10. Characters / style-guides Phase 1 is read-only and dispatchable NOW.** Phase 0
(reconciling DAM's existing mapping against the 174-row licensing-team review) is
still blocked on Albert. Phase 1 is not.
✅ *Gate:* a read-only comparison document in `docs/`, no schema change.

**11. Do NOT attempt Step 8 switch-on.** See §7 for the full blocker list.

---

## 7. Constraints and gotchas in force

### Standing rules (non-negotiable)

- **All schema change is authored here**, branch + PR, preview first, AI merges it.
  Never an app-repo inline migration. Never direct DDL via psql or MCP.
- **No band-aids.** Root-cause, permanent fixes. A necessary temporary workaround
  must be labelled TEMPORARY with the permanent fix described.
- **No silent failures.** Every fallback alerts loudly. When you find one silent
  failure, sweep the codebase for the same pattern — the ENOBUFS defect (empty
  stderr on failure) is exactly this class.
- **Nothing hard-coded that should be configurable** — the RFQ hard-coded row bounds
  are the cautionary example, and they were vindicated as a mistake within hours.
- **Add unit tests for code you create.**
- **Commit identity must be `Albert Hazan <u2giants@users.noreply.github.com>`.**
  Verify with `git var GIT_COMMITTER_IDENT` **before** the first commit — correcting
  it afterwards means rewriting history. 231 wrong-identity commits already reached
  merged shared branches once.
- **Production infrastructure is READ-ONLY by default** for AI sessions. No
  `terraform apply` against prod, ever.
- **Never write a credential value anywhere.** 1Password vault `vibe_coding` only,
  referenced by item title/ID. Serialize 1Password reads — never fan them out in
  parallel.

### Repo-specific traps

- **CI cannot apply to production.** `.github/workflows/shared-supabase-migrations.yml`
  has a step named "Refuse production apply". Production promotion is the **local,
  bounded, manual** procedure in `AGENTS.md` §5.1. "No Actions run" is therefore the
  **expected** state for a production promotion — do not treat it as evidence a
  promotion did not happen (§4.12).
- **The migration ordering trap** (§5.4) — `20260729120000` before `20260728174500`
  raises `undefined_function` 42883 against production.
- **`scripts/production_migration_guard.py` hard-blocks four migrations.** They are
  blocked deliberately. Do not remove the guard entries to "make it pass".
- **`tools/evaluate-coldlion-licensor-property-cutover-readiness.mjs` lines 399–407
  REFUSE the production variable** until
  `docs/verification/coldlion-licensor-property-step8-approval-*/approval.json`
  exists. That file does not exist. This is a feature.
- **Windows CRLF defect (B1)** — some tests fail locally on Windows and are green on
  Linux CI. Two such failures were seen this session and are NOT real. `.gitattributes`
  forcing LF is the fix; it is not done.
- **Repo-wide checkers are gated behind narrow `paths:` filters (B2)** — a guard that
  cannot re-run is not a guard.
- **`grep -a` on files with NUL separators** (§4.4).
- **The WSL `psql` wrapper leaks orphaned processes that hang forever (B12).**
- **Do not load large-payload MCP tools as coordinator** (§4.6).

### ⛔ Step 8 (ColdLion production switch-on) — STILL NOT ASKABLE

B14 is fixed, but Step 8 remains blocked on **all** of:

1. The missing approval package (`approval.json`, above).
2. The production lane's inability to produce a plan (§5.3) — needs a workflow change.
3. A production backup / baseline.
4. Albert's **written** acceptance of weaker production alerting.

**Do not ask Albert about Step 8. Do not create or set
`COLDLION_LICENSOR_PROPERTY_PRODUCTION_ENABLED`.**

---

## 8. Access and environment

- **Machine:** `t16`, Windows 11 Pro, user `ahazan2`. PowerShell 7 is primary; Git
  Bash is available and this session used it for POSIX one-liners.
- **Repo:** `C:\repos\shared-db`. Agent worktrees live under
  `.claude/worktrees/`. **Never work in the shared checkout** — it is regularly
  parked on someone else's branch (right now it is, §3.2).
- **Authenticated CLIs on this machine:** `gh`, `gcloud`, `az`, `supabase`,
  `vercel`, `op` (when toggled on). **Verify with a real call before claiming a
  capability is missing** — that mistake has been made repeatedly.
- **Supabase project refs:** production `qsllyeztdwjgirsysgai`, preview
  `rjyboqwcdzcocqgmsyel`. **Confirm which one you are on via `get_project_url`
  before any read, and certainly before any write.** The C2 verifier did exactly
  this and it is why its evidence is trustworthy.
- **Secrets:** 1Password vault **`vibe_coding` only**. Never paste values into
  files, docs, or commits. Note: 1Password vault/item IDs can **re-key within a
  single session** on MCP reconnect — always re-look-up by title + vault; never
  reuse a cached ID.
- **This handover made NO database call of any kind.** Every database fact in it is
  attributed to the sub-agent that verified it, with the method stated.
- **Key documents:**
  - `AGENTS.md` — the router; read it first. §5.1 = production promotion procedure.
    §6.3 = Albert's ColdLion-canonical ruling and its scope guard.
  - `HANDOFF.md` — 5,982 lines, authoritative for backlog and findings.
    `## BACKLOG` starts at line 1509.
  - `COORDINATOR_INTAKE.md` — request queue, intake queue, and the lifecycle rules
    (Part B2) that govern both.
  - `docs/coldlion-production-migration-manifest-20260731.md` — the true 27-migration
    manifest.
  - `docs/coldlion-unmatched-properties-by-licensor-20260731.md` — the 33-code table,
    ready to put to Albert.
- **Skills that matter here:** `shared-db-orchestrator` (how to run as coordinator),
  `shared-db-handover` (how to stop and hand over), `handoff-writer`,
  `cleanup-worktree` (**use this, never ad-hoc `git worktree remove`**).

---

## 9. Open questions, risks, and decisions

### Albert's decisions this session — RECORDED VERBATIM, DURABLE

1. **"Coldlion ERP data is canonical, follow it."** The 442-row production delete
   was **INTENDED AND CORRECT** — the vendors were inactivated in the ERP. **This is
   NOT an incident. Do not propose a restore, PITR, or corrective migration.**
   Recorded in `AGENTS.md` §6.3 via PR #370, with the audit/evidence-table exclusion
   list (§5.8).
2. **Approved:** RFQ group names visible to **all signed-in users across all four
   applications**; `anon` stays closed. (Asked because the definer-rights view
   extends `dflow` readability app-wide.)
3. **Delegated the RFQ production-promotion timing judgement to Grok 4.5**, which
   recommended promoting tonight. The coordinator agreed; it was promoted.
4. **DECLINED TO ANSWER** whether to add a "prove which database you are connected
   to before any `DELETE` / `UPDATE` / `DROP`" rule to `AGENTS.md`. **This is OPEN
   and was NOT actioned. Do not treat silence as approval.** Re-offer it (§6 step 5).

### Still blocked on Albert

- **The 5 property-code contract questions** — `AM1`/`AM2`, `MGM`, `WND`, `EP`.
  **READY TO ASK**, table exists.
- **ColdLion Step 8 switch-on** — still NOT askable; four blockers in §7.
- **The four hard-blocked migrations** in `scripts/production_migration_guard.py`.
- **Characters / style-guides Phase 0** — DAM's existing mapping vs the 174-row
  licensing-team review. **Phase 1 is read-only and dispatchable now.**
- **Run "sync my dotfiles" on his other machines.** `ai-devops` PR #1 is **MERGED**;
  only this half remains.
- **The "prove your database target" rule** — decision 4 above.

### Waiting on other people

- **Laura's round-2 reply** — 166-row characters sheet, sent 2026-07-31, awaiting.
  **`EX` / `LB` / `JL` are NOT in it, and that is correct** — Laura already answered
  them properly in round 1. The gap is ours.

### Deliberate decisions to flag — these are NOT oversights

- **No worktree or branch sweep was performed.** 33 worktrees are registered. **This
  was a decision, not neglect.** B11 is unresolved — a paused agent is
  indistinguishable from a finished one, and a sweep earlier today already deleted a
  live agent's workspace. The worktrees are **documented, not deleted**. If you
  sweep, use the `cleanup-worktree` skill, only when the repo is quiet, and never
  remove a worktree that is dirty, locked, or held by a live process.
- **PRs #365 and #366 were left OPEN and un-ingested deliberately** — other sessions'
  intake, needing verification this session had no runway for.
- **The "prove your database target" rule was NOT added** — Albert did not answer.
- **The two applied migrations with stale bronze-immutability comments
  (`20260722171500`, `20260722213000`) were deliberately NOT edited** — editing an
  applied migration changes nothing in the database and desynchronises file from
  ledger.
- **The root `HANDOFF.md` was NOT rewritten by this handover** — this file is
  write-once in `HANDOFF.d/` precisely so concurrent sessions do not collide on it.

### Risks

| Risk | Severity | Why |
| --- | --- | --- |
| Next session assumes `C:\repos\shared-db` is on `main` | **HIGH — most likely failure** | It is on `intake/coldlion-comparison-handover-20260731` (§3.2) |
| **B6** cross-PR object collision recurs | **HIGH** | Unfixed root cause; already caused a four-way collision; would happen again today unchanged |
| Hourly preview alert is real, not residue | **MEDIUM–HIGH** | Unproven; names Albert as response owner; red since 20:02 UTC |
| Someone runs the pending 27 migrations against production | **HIGH** | Ordering trap → `undefined_function` 42883 (§5.4); `--include-all` would be needed and is dangerous |
| Someone "fixes" the production lane with a blanket `--include-all` | **HIGH** | That flag is exactly how an unintended migration gets applied. Bound it to an explicit file list |
| Someone proposes restoring the 442 deleted rows | **MEDIUM** | Albert ruled it correct. Wastes a session and contradicts the owner |
| Stale figures propagate | **MEDIUM** | "66 codes" (really 33), "~15 unrelated" (really 9), "ai-devops PR #1 open" (MERGED) |
| A worktree sweep destroys live work | **MEDIUM** | Already happened once today. B11 |
| Preview treated as clean | **MEDIUM** | It is not (§3.4); `reset_by` names a sub-agent, not a human |

### Open questions nobody has answered

- What is the bounded design for the production lane (§5.3)?
- Is the hourly preview alert residue or real (§3.6)?
- Should the "prove your database target" rule be added (decision 4)?
- The exact **times** of the 442-row delete and the promotion are **unknowable** with
  current tooling — the ledger has no timestamp and commit timestamps are disabled.
  Do not spend a session trying; if timing matters operationally, the fix is to add
  a timestamp, not to archaeology.

---
---

# PART (b) — ONE BLOCK PER SUB-AGENT (19 blocks)

Format for each: **asked / did / found / PR / worktree / deliberately did NOT do.**

---

## Block 1 — Recon (read-only, Explore)

- **Asked:** verify `HANDOFF.md` and `COORDINATOR_INTAKE.md` against the live repo.
- **Did:** proved the main SHA in the docs was stale; checked all 21 worktrees then
  registered (clean and unlocked); confirmed every branch's PR was merged; found 2
  empty stray directories that were NOT in `git worktree list`.
- **Found:** the queue sections were empty **only because nobody had seeded them** —
  not because there was no work. This is the finding that made queue-seeding a
  required handover criterion.
- **PR:** none. **Worktree:** none.
- **Deliberately did NOT:** sweep anything.

---

## Block 2 — B8 rollback-lever tests → **PR #358 MERGED**

- **Asked:** unit-test `tools/emit-coldlion-rollback-sql.mjs` — the emergency
  rollback lever, previously untested and run exactly once ever.
- **Did:** wrote `tools/emit-coldlion-rollback-sql.test.mjs`, +233/−0, 5 tests.
  **Mutated the tool 4 ways and confirmed each test fails**, then restored it
  byte-identical.
- **Found:** `compositeKeyOf` **collapses a missing field to an empty segment**,
  yielding a safe-looking key with a hole in it. Cannot occur against the frozen
  artifact, so it was **pinned as current behaviour, NOT fixed**. Also flagged 2
  local test failures that are the **Windows CRLF defect (B1)** — green on Linux CI.
- **Deliberately did NOT:** fix the tool under test. Correct call — a test PR that
  also changes behaviour cannot prove either.

---

## Block 3 — C2 production manifest → **PR #360 MERGED**

- **Asked:** re-derive the TRUE production migration manifest.
- **Did:** produced `docs/coldlion-production-migration-manifest-20260731.md`, +297.
- **⚠️ DIED TWICE** — a connection drop, then a 600-second stall. It was resumed with
  an assess-first instruction, then **superseded by an independent verifier**
  (block 4) because it could never answer which project ref it had read or whether it
  had mutated anything.
- **Found:** the plan claimed **4** pending migrations. **The truth is 27** (18
  ColdLion + 9 unrelated). **The "~15 unrelated" figure in the docs is WRONG.**
- **Worktree/branch:** `agent/c2-migration-manifest` — **finished**.

---

## Block 4 — C2 verifier (read-only)

- **Asked:** independently verify PR #360, and establish whether production had been
  mutated.
- **Did:** re-derived all 27 versions by `comm` on sorted lists. **Verdict: CORRECT.**
  Read production `qsllyeztdwjgirsysgai`, **confirming the ref via `get_project_url`
  first**.
- **Found:** production **NOT mutated**, evidenced four ways — ledger count and max
  unchanged, zero orphan rows, 4 objects from pending migrations probed and absent,
  and the only dispatch run logged a dry run that failed at the `--include-all`
  refusal. Confirmed the **`20260729120000`-after-`20260728174500` ordering trap is
  real** (unguarded grant on functions absent from production → `undefined_function`
  42883). **Cleared two false alarms:** a function name appearing only as a string
  literal in an allowlist, and a migration version referenced only in a prose comment.
- **Worktree:** removed by itself.

---

## Block 5 — ColdLion rehearsal → **PR #362 MERGED**

- **Asked:** re-run the 18-case rehearsal against the **CURRENT** function body,
  preview only.
- **Did:** **18/18 PASS, including cases 10a–10d — the first time those ever
  executed.** Confirmed all four post-rehearsal migrations (`20260731163000`,
  `20260731180000`, `20260731190000`, `20260731200000`) present in **live
  `pg_proc.prosrc`** — read from the function body, **not inferred from the ledger**.
- **Found: FOUR tooling defects that had left the lane completely dead.** Full detail
  in §5.1. Summary: no `maxBuffer` on `runSql` (1,305,075-byte probe → ENOBUFS →
  **failure with EMPTY stderr** → breaker auto-tripped; scored 2/18 until diagnosed);
  `supabase db query` defaulting to a box table not JSON (16/18 scored FAIL while the
  DB answered correctly); `parsePhase6FunctionResult` unable to unwrap
  `--output json`; and cases 3/11/12 stale against the `20260731200000` tie-break so
  their trigger was never reached.
- **⚠️ EXCEEDED ITS ALLOWED FILE LIST** — edited `coldlion-sync-common.mjs` and
  `phase6-cli-result-parse.mjs` — **and disclosed it.** The rehearsal was unrunnable
  otherwise. The disclosure is why this was acceptable.
- **Deliberately did NOT:** touch production, author a migration, or merge.

---

## Block 6 — Independent review of #362 (read-only)

- **Asked:** independently review PR #362.
- **Verdict: APPROVE WITH CONDITIONS.** Zero Critical, **one High** — zero tests
  added on the file the production feed depends on.
- **Found:** confirmed defect 1 **IS a production risk**, by tracing `runSql` →
  `promote-coldlion-source-owned.mjs` → the production workflow and establishing
  **there is no separate production client**. Also established the fix **moves the
  cliff rather than removing it** — an ENOBUFS still throws, still records a durable
  failure, still auto-trips. That became **B14**.
- Byte-compared cases 3/11/12 and confirmed they were **STRENGTHENED, not weakened**:
  no `record(...)` assertion was touched; the fixture was broadened so the guard is
  actually reached. This is the right way to answer "did you weaken the tests to make
  them pass?".

---

## Block 7 — Conditions closer → **PR #362**

- **Asked:** close the High condition from block 6.
- **Did:** added `tools/coldlion-sync-common-runsql.test.mjs` (12 tests) and
  `tools/coldlion-fanin-single-arm-noop.test.mjs` (4), **stubbing the spawn boundary
  via a fake `supabase` on PATH** — a clean technique worth reusing.
  **16 tests, 12 mutations, every one watched fail, all three sources restored
  byte-identical with SHA-256 proof.** Added **B14** to `HANDOFF.md`.
- **Self-corrected a false-negative byte comparison** — it had compared a character
  index against byte offsets in a file full of em dashes (§4.8).
- **Deliberately did NOT:** use the `no-queue-entry-needed:` opt-out. Correct — the
  opt-out exists for genuinely queue-irrelevant work, not for convenience.

---

## Block 8 — B14 queue entry → **PR #362**

- **Asked:** add the B14 entry to `COORDINATOR_INTAKE.md` so the
  `Backlog / Queue Sync` check goes green.
- **Did:** added exactly one block to the `## REQUEST QUEUE`. **Purely additive and
  byte-proven: 58,805 original bytes all intact, 2,379 bytes inserted at a single
  point.** That is the standard for editing a shared file.

---

## Block 9 — Grok 4.5 — RFQ groups → **PR #363 MERGED, PROMOTED TO PRODUCTION**

> **Albert required a non-Claude agent for this workstream.** Honour that if the
> workstream continues.

- **Asked:** add a read-only `rfq_groups` JSON column to
  `public.style_tracker_rows_with_bridge`.
- **Did:** migration `20260731230000_style_tracker_rows_rfq_groups.sql`.
- **Found a SPEC ERROR:** the brief said to read the group link from `RFQGroup_id` on
  the item table. **That column does not exist.** The real FK is
  `rfqItem_rfq_group`. An agent following the brief literally would have shipped
  something broken.
- **Measured three designs:** correlated ~91 s; correlated + index ~250 ms;
  **pre-aggregate join ~118 ms — shipped, no index.**
- Preview results: 15,533 rows, 2,015 linked, 11 multi-group — matching the brief's
  sanity targets exactly.

---

## Block 10 — Kimi K3 review of #363 (read-only)

- **Verdict: MERGE WITH CHANGES.**
- **Proved from the SQL — not from a row count — that the pre-aggregate join cannot
  change the view's row count under ANY data condition:** `GROUP BY` guarantees a
  unique join key, `LEFT JOIN` preserves unmatched rows, blank/NULL codes excluded on
  both sides. This is the standard of proof a view change deserves.
- **Four findings, all confirmed by the coordinator against the file:**
  1. **Dead assertion** — a second `v_fuzzy_hit` computed and never asserted.
  2. **Hard-coded 1900–2200 count bounds** that would abort a production apply on
     ordinary data drift.
  3. **Missing `notify pgrst, 'reload schema'`.**
  4. **The definer-rights view extends `dflow` readability to all authenticated users
     across all four apps** — a cross-app data-contract question, not a code nit.

---

## Block 11 — Grok 4.5 — #363 fixes

- **Did:** all four findings fixed on the same branch. Fuzzy check now **raises**;
  bounds replaced with a **sanity floor** instead of hard-coded values;
  `notify pgrst` restored; the `dflow` exposure documented in the PR body.
- Re-applied to preview, re-verified, and **proved the new assertion fires by
  deliberately inverting it** — the negative-path proof B7 asks for.
- **Albert approved the `dflow` visibility question** (RFQ group names visible to all
  signed-in users across all four apps; `anon` stays closed).

---

## Block 12 — Grok 4.5 — promotion recommendation (read-only)

- **Albert delegated the timing judgement to Grok.** **Verdict: PROMOTE TONIGHT.**
- **Critically:** read the **LIVE production view definition** and confirmed it
  matched base migration `20260721143000` **exactly (48 columns, exact match)** —
  **this is what closed the silent-column-loss risk.** Do this before any view
  replacement.
- Measured production assertion values: **15,534 rows vs preview's 15,533**. The data
  had **already drifted**, which vindicated removing the hard-coded bounds hours
  after the decision was made.

---

## Block 13 — Grok 4.5 — bounded production promotion

- **Did:** promoted **ONLY** `20260731230000` to production. The dry run listed
  **exactly one file** — that is the bound, and it was checked before applying.
- **Post-apply verification:** ledger row present; live view has `rfq_groups`;
  **48 → 49 columns with nothing lost**; `MFZ88KMSC01` → "Family Dollar July 2023";
  multi-group deduped newest-first; unmatched `[]`; row count 15,534 unchanged;
  **`anon` denied via `has_table_privilege`** — it correctly noticed that
  **`SET LOCAL ROLE anon` lies** over a superuser pooler connection (§4.3); and the
  **mirror sync reached all 9 consumer repos.**

---

## Block 14 — Backlog reader (read-only)

- **Did:** read all **5,982 lines** of `HANDOFF.md`. Produced the B1–B14 status list.
- **Found ~19 live items the coordinator's matrix was missing.**
- **Corrected a documented error: `ai-devops` PR #1 is MERGED, not open.**
  `HANDOFF.md` says open **in two places** and is **WRONG**.

---

## Block 15 — Matrix refresher (read-only)

- **Did:** read both `HANDOFF.md` and `COORDINATOR_INTAKE.md` in full.
- **Surfaced:** the two open intake PRs; the hourly alert-monitor failure; the parked
  shared checkout; and **two NEW Step 8 blockers**, the important one being that
  **the production lane cannot produce a plan today** — 6 of 14 promotable ColdLion
  migrations sort older than production's ledger head, so Supabase refuses them
  without `--include-all`, **which the workflow does not pass**. This needs a
  **WORKFLOW CHANGE** (§5.3).
- **Also correctly challenged the RFQ promotion claim.** Its evidence was
  pre-promotion and therefore mistimed. **The challenge was right to make** even
  though the promotion turned out to be real — that is how a reviewer should behave.

---

## Block 16 — Production truth verifier (read-only)

Settled both disputes. This is the most evidentially careful block of the session.

- **CLAIM 1 — the RFQ promotion: CONFIRMED.** Ledger head `20260731230000`;
  `pg_get_viewdef` shows the column; 49 columns; exactly 27 still pending.
  **Route sanctioned:** `.github/workflows/shared-supabase-migrations.yml` contains a
  step literally named **"Refuse production apply"** which BLOCKS production applies,
  so **"no Actions run" is the expected state for every production promotion this
  repo has ever done**; `AGENTS.md` §5.1 prescribes exactly the local procedure used.
  **Two process gaps flagged:** no Actions bounded dry-run artifact exists for this
  promotion (only a local one, which §5.1 permits), and the surviving worktree is on
  the feature branch, not `origin/main`.
- **CLAIM 2 — the 442-row `DELETE FROM ingest.raw_record` hit PRODUCTION**, proved
  three ways: 97 survivors matching the reported post-delete count;
  `pg_stat_all_tables.n_tup_del` = **exactly 442**; and migration `20260722171500`
  **explicitly states it left `raw_record` untouched**. The deleted rows are raw
  payloads from the pre-2026-07-22 buggy `/vendors` endpoint and are **NOT
  recoverable by re-import**. Derived data survived: `plm.vendor_exclusion` 435 rows,
  `plm.erp_vendor` 97, `core.factory` 93.
- **Could NOT determine — and said so:** the time of either event (no ledger
  timestamp, commit timestamps disabled), preview's state at the time, or whether any
  out-of-ledger DDL ran — **undetectable in principle**. Naming the limits of the
  evidence is what makes the rest of it trustworthy.
- **Cleared PR #337:** merged uncoordinated, but it is docs-only, +21/−6, and merged
  at **13:49 UTC** — outside tonight's window.

---

## Block 17 — 66-code licensor table → **PR #369 MERGED**

- **Asked:** enumerate the unmatched ColdLion property codes grouped by licensor.
- **Found the premise stale: it is 33 codes, not 66** — ColdLion now offers 285
  property codes, not 322.
- **27 of the 33 were created in ColdLion on 2026-07-30 — a licence created yesterday
  cannot be lapsed.** **NASA, ZAG and Frida Kahlo — the named lapsed-licence risks —
  are NOT in the unmatched set** (NASA is a *licensor*; Frida Kahlo already matches).
- Breakdown: **Viacom/Paramount 27, Warner Bros 2 (`EX`, `LB`), NBCUniversal 2,
  Peanuts 1, DC 1.**
- **Recommends admitting all 33; only 5 rows genuinely need Albert** — `AM1`/`AM2`
  (Anchorman), `MGM` (Mighty Mouse), `WND` (It's a Wonderful Life), `EP` (Emily in
  Paris).
- **Discarded PopDAM asset counts** because PopDAM's property codes are a **colliding
  code space** — its `BB` is Big Bird, not The Brady Bunch. Presenting them as volume
  would have misled Albert. This was the right call and cost it its headline number.
- **Flagged:** PopDAM files **8 Exorcist assets under NBC when Warner Bros is
  correct.**
- **Output:** `docs/coldlion-unmatched-properties-by-licensor-20260731.md`.

---

## Block 18 — B14 root-cause fix → **PR #367 MERGED**

- **Asked:** remove the ENOBUFS cliff rather than raise it.
- **Chose** paging + spawn-fault classification. **Rejected the aggregate/hash option
  WITH EVIDENCE** — the planner decides row by row and consumes all 14 probe keys, so
  no aggregate preserves what it needs. Do not re-propose it.
- **Round 1 reviewed by Kimi: MERGE WITH CHANGES**, two Mediums, **both confirmed by
  the coordinator**:
  (a) it had **removed one healthy-race breaker trip and installed another** — a
  benign snapshot overlap was still being recorded as a failure; and
  (b) `maxBuffer` was applied to **ONE of two spawn paths**, leaving the **psql path
  at the original 1 MiB cliff**, while the page size rested on an **unverified
  ~700 B/row estimate**.
- **Round 2 fixed both:** bounded single retry from page 0
  (`CYCLE_STATE_MAX_ATTEMPTS = 2`); snapshot race → **exit 5 recording nothing**; a
  duplicate key surviving a clean restart stays a **REAL recorded fault**; one
  `SPAWN_MAX_BUFFER_BYTES` on **both** spawns; and it **MEASURED** row size from
  **570 real records already in the repo** (mean 496 B, p95 536 B, max 581 B) rather
  than estimating, cross-checking against the incident figure.
- **22/22 mutations killed. CI 428/428 on Linux.**
- **⚠️ Self-reported that its own mutation harness clobbered a source file
  mid-sweep.** It caught it, rebuilt from git plus patches, and **rewrote the harness
  in Node**. **The coordinator independently verified no content was lost** — files
  distinct by SHA, no cross-contamination, every named function on main still present
  on the branch. An apparent "missing function" was a **grep artifact caused by the
  file's deliberate NUL separators** (§4.4).
- **B14 is RESOLVED and no longer a Step 8 blocker.**

---

## Block 19 — Owner-ruling recorder → **PR #370 MERGED**

- **Asked:** record Albert's "ColdLion ERP data is canonical, follow it" ruling.
- **Did:** recorded it in `AGENTS.md` §6.3.
- **Added a scope guard the coordinator had not thought of:** "follow the ERP" could
  be read as licence to **delete audit and evidence tables**, so the ruling
  **explicitly excludes** `plm.coldlion_promotion_audit`,
  `plm.coldlion_promotion_quarantine`, `plm.taxonomy_parallel_observation`,
  `plm.taxonomy_circuit_breaker_event`, `app.db_data_admin_audit_event`.
- **Found 5 more places** beyond the 2 already known that still assert the bronze
  layer is immutable. **Two are LIVE documents a future session could act on and
  still need the supersession pointer: `HANDOFF.md:5381` and
  `fix_schema_for_api.md:40,159`.**
- **Deliberately did NOT** edit the two applied migrations carrying stale comments
  (`20260722171500`, `20260722213000`) — editing an applied migration changes nothing
  in the DB and desynchronises file from ledger. Correct call.

---
---

## SELF-AUDIT (handoff-writer gate)

**Q1. Could a brand-new developer with no project knowledge and no session context
pick up where this session left off and not skip a beat?**
**Yes.** §1 defines the repo, the four apps, both project refs, and the absolute
schema-change rule from zero. §3.2 gives the first corrective action with exact
commands and a gate. §6 gives 11 ordered, gated next steps. §8 names every document,
CLI, ref, and skill by path. No term, ref, or identifier is used without definition.

**Q2. Could they continue as effectively as this session can right now?**
**Yes.** §4 records 13 dead ends with why each failed — including the four that are
invisible from the code (`grep` on NUL-separated files, `SET LOCAL ROLE anon` lying,
estimating instead of measuring, "no Actions run" being expected). §5 carries every
non-obvious finding with file, line, and SQLSTATE where relevant. Part (b) preserves
each sub-agent's method, evidence, and its deliberate omissions, so the reasoning is
transferable and not just the conclusions.

**Q3. Is every relevant detail for flawless execution included — background, goals,
outcome, state, failures, decisions, constraints, risks, next actions, verification
evidence?**
**Yes.** Background §1; goals §2; current state §3 with facts re-verified at write
time and three corrections named; failures §4 (mandatory section, expanded to 13
entries); findings §5; next steps with gates §6; constraints and the four Step 8
blockers §7; access §8 with secrets by vault name only; decisions, open questions,
deliberate non-actions, and a risk table §9. Part (b) covers all 19 sub-agents with
PR, worktree state, and what each deliberately did not do.

**Gap found and fixed during the audit:** the first draft carried the coordinator's
"#366 mergeable UNKNOWN" and "21 worktrees" unchanged. Both were re-checked live and
**corrected in §3.1** with the correction called out explicitly rather than silently
overwritten.
