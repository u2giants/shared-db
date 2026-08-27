---
issue: 1680
status: OPEN
owner: claude/plan-throughput-guard-truth
---

# Handoff — plan written to cut `shared-db` issue lead time (guard truth, false-alarm corpus, blocker ledger)

**UTC:** 2026-08-27T20:00Z · **Machine:** edge-dev · **Agent:** Claude (Opus 5) · **Branch:** `claude/plan-throughput-guard-truth` (from `origin/main` @ `42f0b77`)

## What this session produced

A single deliverable: [`plan_orchestrator_throughput_guard_truth.md`](../plan_orchestrator_throughput_guard_truth.md).
**Read its STATUS table first. Do not re-derive the analysis or re-plan the steps.**

No code was changed. No database was touched. No migration was written.

## Independent review, 2026-08-27 — read this before the plan

GLM-5.3 reviewed the plan (session `shared-db-throughput-plan-review`, report
`.ai/reviews/glm-shared-db-throughput-plan-review-20260827T194444Z.md`) and returned
**APPROVE WITH CHANGES**, with Steps 1–3 rejected as originally written.

**Its finding about the three named files was correct** — they are phantoms of a bare
`$$` regex that paired a `$$` inside a `--` comment with a later real `do $$`.
**But the replacement claim written in response — "the count is zero" — was ALSO wrong,
and wrong the same way.** The re-check used a bare `$$` pattern too, which is structurally
incapable of seeing a tagged dollar quote. A peer session caught it within the hour. It
never reached `main`.

**The verified answer:** one migration,
`supabase/migrations/20260825082910_popdam_ai_search_reconciliation_and_activation.sql`,
creates four durable objects inside `$ddl$ … $ddl$` bodies at lines 2367–2428 — including
**`public.style_group_tags`, the #1645 object, created 2026-08-25**, which matches the
owner's quote exactly. Confirmed against `strip_sql` itself, not a regex: every one of
those names is present in the raw file and absent after `strip_sql`. §6.1's mechanism is
**confirmed**; only the file list was ever wrong. All three versions are recorded in §3.1
of the plan, deliberately, as the best available evidence for why §6.1 matters.

Consequences already applied to the plan: Step 1 restored and corrected — the
`apply_time_ddl_bodies()` extractor must handle **tagged** quotes, and it also picks up
dynamic RLS/policies and the absent-vs-not-derivable collapse in `preflight_batch`;
Step 2 given multi-creator semantics and a project-ref redaction rule;
Step 3 given a text-only rule so enrichment can never change an exit code; Step 5 wired
into a workflow and stripped of generated Markdown; Step 8 keeps **two** reviewers for
anything touching `supabase/migrations/`; Open Question 1 now asks which *job* produced
the #1645 text, with the hard-block bookkeeping trap (`20260814223552` / `20260825094455`,
replacements applied 2026-08-25) listed as a possible second contributor to rule in or out.

**If only one step is ever built, build Step 2 (`catalog-truth`)** — it fixes the
bookkeeping trap regardless of which mechanism produced #1645.

## Why it exists

The owner reviewed the recorded Claude sessions for this repository on 2026-08-27
and asked why issues take so long to clear, citing the #1645 case where a safety
scanner reported a table as missing and blamed a hard-blocked migration, when
production had held that table since 25 August. **The plan's original explanation for
that case — a `CREATE TABLE` hidden inside a dollar-quoted block — did not survive
review; see above and §3.1 of the plan.**

Analysis of 38 archived sessions (8 of them orchestrator sessions) between
2026-08-18 and 2026-08-27 found four repeating shapes, all written up with
verbatim evidence in §6 of the plan:

1. guards judge SQL **text** and treat "I did not see it" as "it does not exist";
2. guards fire on honest input, and each repair costs a whole session;
3. a diagnosis is announced before it is proven, then reversed;
4. waits on external reviewers are unbounded, and the reviewers misreport their own state.

Measured baseline, 400 closed issues: median 4.0h, mean 21.1h, p90 60.3h;
18% over a day, 10% over three days. The long tail is the target.

## What is NOT done

Every step in the plan. Step 0 (open the tracking issue, confirm registration)
is where a fresh session starts.

## Things a successor must not do

- Do **not** flip `strip_sql`'s `keep_dollar` default to fix the headline bug.
  It would create false apply-time dependencies across 546 migrations. §7.2.
- Do **not** characterise the lexer's blind spot with a regex. It has been done twice in
  this plan and produced two different wrong answers. §3.1 gives a command that uses
  `strip_sql` itself; use that. A dollar quote is `$tag$`, not `$$`.
- Do **not** implement `apply_time_ddl_bodies()` with a `$$`-only matcher. It would miss
  the one file that matters. There is a required test for exactly this.
- Do **not** loosen any guard to reduce false alarms. §7.1, and it is the owner's
  standing rule.
- Do **not** route this to the structure/schema orchestrator. It is repository
  maintenance and authorizes no database change.

## Evidence sources

- Transcript archive: `u2giants/ai-devops-transcripts`,
  `collection-2026-08-27/claude_chats/edge-dev/projects/C--repos-shared-db*`.
- In-repo: `scripts/production_migration_guard.py` (`strip_sql`),
  `scripts/production_catalog_verification.py` (`derive_targets`),
  `scripts/check-pr-object-collisions.mjs`, `scripts/check-cancelled-work.mjs`,
  `scripts/check-migration-ledger-drift.mjs`.
