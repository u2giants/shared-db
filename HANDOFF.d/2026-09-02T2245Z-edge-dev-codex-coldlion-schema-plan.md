---
issue: 2081
status: OPEN
owner: codex/coldlion-schema-completion-plan
---

# ColdLion landing-schema completion plan

## 0. Decisions only the owner can make

None are required to begin the four structurally ready master feeds or the evidence refresh. Sales-history reporting may use the approved per-design quantities; it must not infer fulfilment from document-number presence or claim unavailable document provenance. Remaining feeds require Albert's ingest/ignore field disposition after a sanitized live census; present that entire field decision package once, not piecemeal. Already settled: no image bytes, EP001 excluded, history from 2019-01-01, three forward versions, and component-level licensor/property and quantities.

Separately, roughly 68 public `docs/` files were previously found to contain real customer identifiers and commercial details. Albert has not chosen whether to redact them or move that evidence to a private repository. Making `shared-db` private is a cancelled option because it removed branch protection. Until Albert rules, add no new customer or licensed row detail to this public repository; use sanitized structural evidence only.

## 1. What this application is

ColdLion is POP Creations' ERP. `u2giants/shared-db` governs the shared Supabase/Postgres structure. The private `coldlion` schema is a source-aligned landing layer that applications never read directly.

## 2. Session goal

Audit every planned ColdLion feed, answer which are structurally ready, and write a fresh-session implementation plan for all required corrections and missing tables.

## 3. Current state

The durable plan is [`../plan_coldlion_landing_schema_completion.md`](../plan_coldlion_landing_schema_completion.md). Production was inspected read-only on 2026-09-02: 17 landing tables exist, all are empty. Four feeds have complete structural destinations; all others are incomplete, stale, unproven, intentionally excluded, or lack tables. The older same-issue handoff was retired because its statement that no schema existed was false; its U1-U20 recovery paths and open obligations are carried here and in the plan, including the unresolved public-document exposure decision above. No database change or data load was performed.

## 4. Failed approaches and dead ends

The older plan STATUS was not trusted because it labels applied tables open. The closed #1184 issue was not treated as end-to-end completion because it proves structural deployment, not current API fit or loaded rows. Existing applied history tables cannot be repaired in place because their keys predate `salesOrderLineNo`.

## 5. Root causes and findings

ColdLion changed history response shape on 2026-08-31. The current sales key is superseded; history paging silently caps at 200; production history requires all three stages; history child rows lack parent foreign keys; `/divisions` has no landing table; and D5 makes an omitted field expensive to recover. Full findings and evidence routes are in plan §§5–8.

## 6. Exact next steps

1. Start at plan §9 Step 1 and re-resolve `origin/main`, the live spec, production catalog, marker, queue, and U1-U20. Gate: every objection and exact object has an owner/issue.
2. Dispatch exact structural units in plan order: references, items, sales history, production history, remainder. Gate: each unit passes its stated verification and updates STATUS.
3. Build loaders and controlled loads only after structures are current. Gate: complete pages/stages/windows and reconciled counts.
4. Publish governed consumer contracts and close #2081 only after direct production verification. Gate: no selected feed lacks a proven destination.

## 7. Constraints and gotchas

Use the shared-db orchestrator for structure, isolated worktrees, forward-only migrations, preview-first PRs, exact target proof before writes, and private evidence. Never commit real customer/licensed rows. Do not infer licensor/property relationships or let applications read landing tables.

## 8. Access and environment

Work was performed on EDGE-DEV in branch `codex/coldlion-schema-completion-plan`. GitHub uses `u2giants`. Secret locations and the live API/spec routes are listed in plan §12; no secret value belongs in a command argument, log, prompt, or commit.

## 9. Open questions and risks

The sales feed lacks a source-document discriminator, but the practical duplicate-row problem is resolved and must not be re-asked. Remaining endpoint grains require live proof. The loader runtime is settled as repository-owned Node tools run by GitHub Actions; any different runtime needs an owner-approved plan amendment. The plan gives the safe boundary and decision criteria in §13.

### Self-audit

Yes, a new developer can continue without context: §§1–3 define purpose and exact state; §§4–5 preserve failed assumptions and findings; §6 points to ordered steps with gates; §§7–9 cover rules, access, decisions, and risks. The owner-decision sweep found only the two conditional items in §0, both consolidated there. Commit, push, PR, and deployment state are explicit.
