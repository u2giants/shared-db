# Implementation plan — three gaps in the orchestrator workflow

**File:** `plan_orchestrator-workflow-gaps.md` · **Repo:** `u2giants/shared-db` · **Created:** 2026-08-07
**Status:** WRITTEN, NOT STARTED. Not yet reviewed.

Three gaps Albert asked to have fixed, found while finishing the intake-to-Issues migration
on 2026-08-07. They are independent of each other and are listed worst-first.

| # | Gap | Phase | State |
|---|---|---|---|
| A | Production migrations have no apply path, and the dry-run path has never been exercised | 1 | ⬜ open |
| B | Nothing mechanically stops two orchestrators running at once | 2 | ⬜ open |
| C | A session already running never learns of a new owner ruling | 3 | ⬜ open |
| D | 71 open issues with no ordering — no single "what is next" | 3 | ⬜ open |

> **Do A first.** B, C and D are process quality. A is the reason the database five
> applications share has not received a migration since **2026-08-02**.

---

## Correcting the framing this plan was born from

I told Albert the production lane "has never worked" and quoted *281 runs, 142 skipped, 1
failed, 0 succeeded*. **That reading was wrong and the plan must not inherit it.**

Read live 2026-08-07 from `.github/workflows/shared-supabase-migrations.yml`:

- The `production-dry-run` job runs **only** on `workflow_dispatch` with `target=production`.
  On a pull request its `if` is false, so it does not run. **The 142 "skips" are pull
  requests, which is correct behaviour, not failure.**
- The job is **deliberately dry-run only**. Its first step is *"Refuse production apply"*,
  which exits 1 whenever `mode == apply`. That is an intentional interlock.
- It is well-built: exact-SHA confirmation, a typed confirmation string
  (`DRY-RUN <sha>`), a `production` GitHub environment, the ledger captured before
  anything runs, a **bounded allowlist** enforced by `scripts/production_migration_guard.py`,
  and the dry-run output verified against that allowlist afterwards.

**The true statement is narrower and still serious: nobody has ever run it.** Zero
successes means the mechanism is unproven against real production, and there is no apply
path at all — by design, pending a process nobody has yet written.

---

## Measured starting position

Read read-only from production (`qsllyeztdwjgirsysgai`) on 2026-08-07, after confirming the
target with `get_project_url` per `AGENTS.md` §12 standing fact 6:

| | |
|---|---|
| Production ledger | **361** rows, head **`20260802194100`** |
| Migration files on `main` | **405** |
| **Pending** (newer than head) | **11** |
| ⚠️ **Older than head, absent from the ledger** | **33** |

**The 33 are the whole difficulty.** The Supabase CLI refuses migrations sorting older than
the ledger head unless given `--include-all`, and `--include-all` would sweep all 33 into a
single unreviewed apply against the shared database. **This plan never uses that flag.**

The 11 pending, in order — the five OPA migrations are only the last five:

```
20260803150000  itemdetail coldlion item identity and UPC contract
20260803200000  temp status watch snapshot and change log
20260803201000  temp status watch hardening
20260804120000  taxonomy baseline pins table
20260804120100  taxonomy breaker environment and provenance
20260807030000  owner ruling — Coco is a Disney license
20260807170000  opa property/character landing
20260807170100  opa property/character importer
20260807180000  opa sync reentrancy fix
20260807190000  opa security and view corrections     ← security fix, NOT optional
20260807200000  opa comment corrections
```

⚠️ Without `20260807190000` the landing table ships `using (true)`, letting **every**
authenticated account — including `vendor` and `viewer` — read the entire Disney extract.
`20260807180000` must precede it.

---

## A. Production migrations: prove the lane, explain the 33, then define an apply path

**A1 — Explain the 33 orphans before anything else. Read-only.**
For each of the 33, establish which of three things it is: (a) applied to production by
some other route and never recorded; (b) genuinely never applied and no longer wanted;
(c) genuinely never applied and still wanted. **The method must be object existence, not
inference from the filename** — check whether the objects the migration creates exist on
production. Output: a committed table under `docs/verification/`, one row per migration,
with the evidence. **No promotion decision can be trusted until this exists**, because
"pending" currently means "not in the ledger", which is not the same as "not applied".

*Gate:* all 33 classified with evidence a stranger can re-derive. Any UNKNOWN stays UNKNOWN
— an honest unknown is safe, a guessed "already applied" is not.

**A2 — Exercise the existing dry-run for the first time.** `workflow_dispatch`, `target:
production`, `mode: dry-run`, the exact `main` SHA, confirmation `DRY-RUN <sha>`, and
`production_allowlist` set to the **11** versions above and nothing else.
This writes nothing. It proves the allowlist mechanism, the guard script and the
credentials all work, and it produces the first real evidence of what an apply would do.

*Gate:* the run succeeds, and the verified dry-run output lists exactly those 11 and no
others. **If it lists anything else, stop — that is the `--include-all` failure mode
appearing, and it is the reason for the allowlist.**

**A3 — Decide the apply path, and write it down before building it.** Two candidates:
- **(i) Add an `apply` mode to the same workflow**, behind the `production` environment's
  required reviewer, the same allowlist, the same typed confirmation, plus a mandatory
  fresh dry-run in the same run whose output must match the allowlist before apply.
- **(ii) A documented manual window** — a human-run, recorded procedure, no new automation.

**Recommendation: (i).** (ii) puts the most dangerous operation this project performs into
a hand-typed sequence, which is precisely what this repo's rules exist to prevent. But (i)
adds an apply path to production, so it is an owner decision, not an engineering one.

*Gate:* Albert has chosen, in writing.

**A4 — OWNER GATE.** Applying to production needs him to name the project and the action.
The exact sentence is written in §Owner gates below. **Nothing in A applies to production
before A1, A2 and A3 are complete.**

**A5 — Apply, verify, record.** Ledger before and after, object existence checked for each
of the 11, and the `20260807190000` policy verified as role-gated rather than `using (true)`.

---

## B. Make the single-orchestrator rule mechanical

Today the marker is an honour-system GitHub issue. A session that misreads it, queries the
**old** `coordinator-marker` label and sees an empty list, or simply skips step 0, just
carries on. Two orchestrators dispatching at once is how this repo produced four competing
migrations on one function.

**B1** — `scripts/check-orchestrator-marker.mjs`: fails when **more than one**
`orchestrator-marker` issue is open, and fails when a `gh` call errors rather than treating
an error as zero. Wire it as a **required** check with no `paths:` filter, like the intake
pointer guard.

⚠️ **This does not prevent a second orchestrator from starting** — nothing in CI can, since
a session claims its marker outside any pull request. It makes the collision **visible on
the next PR** instead of silent. Say that plainly rather than overselling it.

**B2** — Negative-path tests: two open markers must fail, a `gh` error must fail, zero open
must pass, one must pass.

---

## C. Reach a session that is already running

**Proven twice on 2026-08-07.** Albert ruled the Disney extract is not sensitive at ~17:00.
At 22:26 a live session filed issue #578 asking for the git-history scrub that ruling had
cancelled. The rule reached the next session; it did not reach the running one.

**There is no mechanism that reaches a running session, and this plan should not pretend
to invent one.** What it can do is make the next thing that session *does* fail loudly.

**C1** — A `ruling-supersedes` convention: when an owner ruling cancels open work, the
ruling's PR must also close or retitle every issue it invalidates, in the same PR. Today
that happened by hand and only because someone noticed.

**C2** — `scripts/check-cancelled-work.mjs`: reads a small committed table of
`(cancelled instruction, ruling reference)` and fails a PR that reintroduces a cancelled
instruction. Seed it with the two known ones: the R-SEC-1 history scrub, and making the
repo private.

**C3** — Add to the handover skill: an orchestrator re-reads `AGENTS.md` §6 owner rulings
**at handover**, not only at session start, and states in its handover which rulings post-date
its own start time.

---

## D. Give 71 issues an order

The old file had a top; the issue list does not. Losing "what is next" was a real
regression and should be named as one.

**D1 — A `priority` label set, deliberately tiny: `now`, `next`, and nothing else.**
Anything unlabelled is "later". Three tiers, not five: a five-tier scheme becomes a
lifecycle, and design decision D7 of the migration plan rejected exactly that.

**D2 — One pinned issue, `THE BOARD`**, holding the ordered `now` list and nothing else.
It is a pointer, not a second tracker — if it starts carrying detail it has become the old
file again, and that should be written into the issue itself.

**D3** — The orchestrator skill's session-start step reads `--label now` first.

⚠️ **The risk is honest: this is the queue's ordering problem in a new place, and it can rot
the same way.** The mitigation is that it holds ordering only and never detail, and that it
is small enough to re-derive from scratch in minutes.

---

## Owner gates

1. **A3** — which apply path: add `apply` to the workflow, or a documented manual window?
2. **A4** — verbatim, once A1–A3 are done:
   > Apply the 11 pending migrations listed in `plan_orchestrator-workflow-gaps.md` to the
   > production Supabase project `qsllyeztdwjgirsysgai`, in version order, using the
   > allowlist and **without** `--include-all`.
3. **D1** — are two priority labels enough, or do you want a third?

---

## Constraints

1. Branch + PR; you merge it yourself. Never commit to `main`.
2. Commit identity `Albert Hazan <u2giants@users.noreply.github.com>` — check
   `git var GIT_COMMITTER_IDENT` before the first commit.
3. Six required contexts, `strict: true`, `enforce_admins: true`. Expect `gh pr update-branch`.
4. **Never `--include-all` against production.**
5. **The Supabase MCP is bound to PRODUCTION and takes no project parameter.** Call
   `get_project_url` first, every time. Preview work goes through the CLI or psql.
6. Read-only measurement of production is allowed and encouraged. Writes are not, until A4.
7. Other sessions share this checkout — `git diff origin/main --stat` before opening a PR,
   and never `git add -A`.
