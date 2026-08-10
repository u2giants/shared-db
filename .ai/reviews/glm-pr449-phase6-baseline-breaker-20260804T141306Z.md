# GLM review — pr449-phase6-baseline-breaker

| field | value |
|---|---|
| model | zai-coding-plan/glm-5.2 |
| opencode | 1.18.12 (pinned) |
| session | pr449-phase6-baseline-breaker |
| session id | `ses_032e551c0ffeWOazCNOwM1BbXF` |
| repository | /worksp/shared-db/.claude/worktrees/coordinator-handoff-intake-7e55cb |
| branch | claude/coordinator-handoff-intake-7e55cb |
| caller | claude |
| requested | 2026-08-04T14:13:06Z |
| tokens | `{"input":46618,"output":1607,"reasoning":15681,"cache":{"read":0,"write":0}}` |

---

## Verdict per question

### 1. Does it do what it claims?
Largely yes. The pin-table substitution is clean, the append-only guard is genuinely structural (no `auth.role()` dependency), the 9th-parameter change is unambiguous after the 8-arg drop, and grant re-assertion on the *recreated* `plm.*` functions is complete. But several claims are weaker than presented (below), and the production story is unresolved.

### 2. What is wrong or missing

**Public wrappers are not recreated (unverified assumption, untested).** Migration 1 reissues `plm.check_taxonomy_sync_health` and `plm.record_taxonomy_parallel_observation` but explicitly leaves `public.check_taxonomy_sync_health` / `public.record_taxonomy_parallel_observation` untouched, re-asserting only their grants. If those wrappers *delegate* (`select plm.x(...)`) they're fixed automatically; if they *duplicate* the body they still carry the stale hardcoded hash. The PR assumes delegation and the test file never inspects the `public.*` bodies. This is the highest-impact unverified assumption — confirm the wrappers are thin delegators or recreate them.

**TRUNCATE bypasses the append-only guard.** The guard is `before update or delete` (row-level). `grant all on plm.taxonomy_baseline_pin to service_role` includes **TRUNCATE**, and TRUNCATE fires statement-level TRUNCATE triggers, not row-level UPDATE/DELETE triggers. So a `service_role`/migration session can wipe the table and the guard never fires. Revoke TRUNCATE or add a TRUNCATE trigger if the append-only guarantee is meant to be structural for all callers.

**Backfill mutates an append-only audit table.** §6.3 lists `plm.taxonomy_circuit_breaker_event` as append-only. Migration 2 runs `update plm.taxonomy_circuit_breaker_event set trip_provenance = environment ...`. The header even argues against rewriting `environment` to "preserve evidence" — then rewrites the row anyway by populating the new column. Adding a value to a freshly-added column is still an UPDATE of an existing audit row. The consistent choice is to leave `trip_provenance` NULL for historical rows and populate only on new trips. (Also: if a stricter append-only trigger exists on that event table, this UPDATE fails outright — can't confirm from the diff.)

**State-guard assumption is unverifiable from the diff.** The `update plm.taxonomy_circuit_breaker set … updated_at = now()` backfill asserts the 20260728134500 guard "only refuses tripped→closed." If that guard is broader (e.g., blocks any UPDATE, or flags manual `updated_at` writes), the migration aborts mid-apply.

**Grant hygiene is inconsistent, not broken.** The two brand-new `plm.*` accessors (`taxonomy_baseline_pin_set`, `resolve_deployment_environment`, `deployment_environment_is_configured`) only `revoke … from public`, relying on PUBLIC-membership to cover `anon`/`authenticated`. That's correct for fresh functions (no prior explicit grants), but it's stylistically looser than the explicit `from public, anon, authenticated` pattern used on the recreated functions. Not a defect today.

**9th parameter / overload:** correct. After the 8-arg drop there is exactly one signature; all ≤8-positional call sites resolve to it with `p_provenance` defaulting null. No ambiguity. The two auto-trip callers are correctly reissued with named args.

**Timezone:** the midday-UTC `effective_from` pinning is fine, and `effective_from` is provenance-only (never cast to `::date` in any function), so the stated risk is theoretical. The real date logic uses `timezone('utc', now())::date` consistently.

### 3. What fails in production that passes on preview

**Both migrations are non-functional on production today.** The facts state `20260726180000` and `20260727221500` are not applied to production. Concretely:
- `20260804120100`: `alter table plm.taxonomy_circuit_breaker add column …` aborts — the table doesn't exist (`add column if not exists` guards the *column*, not the table). The whole migration fails to apply.
- `20260804120000`: applies (function bodies are late-bound in plpgsql), but every function fails at call time (`compute_taxonomy_immutability_snapshot`, `record_taxonomy_sync_alert`, `taxonomy_parallel_observation` all absent).

**Seeded pins are preview-derived and would lie on production even if the parents existed.** All twelve values were read off preview. The `licensor_status_hash` pin (`00bf7069…`) is the *post*-ruling value; §6.5 deliberately holds `20260802171000` (the FR→inactive ruling) off production, so production's actual hash is still the old `d9b07759…`. Promoting this migration as-is seeds a baseline that production's live data can never match → permanent false `phase4_baseline_drift` → breaker trips immediately. There is **no per-environment seeding mechanism**; production promotion requires manually re-deriving and re-pinning all twelve metrics, which this PR does not provide or document.

### 4. Can the contract tests actually fail?

Most assertions are genuine, but two are weak and one is the wrong kind of test:

- **Section 3 (positive path) is a live-data snapshot, not a contract test.** It asserts `baseline_ok = true`, which only holds while preview's *current* data matches all twelve pins. It cannot run in CI (no preview data), and it breaks on the next legitimate owner ruling or migration even with correct code. It does fail when broken — but it's brittle.
- **Section 8's provenance-preservation assertion is conditional on live state** and silently passes otherwise: `if v_breaker.state='tripped' and v_breaker.tripped_by='auto-trip' and coalesce(trip_provenance,'')='' then raise`. If the breaker was reset, or tripped by a different actor, the guard is vacuously true — a backfill regression would go undetected. The companion event check (`exists … where environment like 'auto (%' and trip_provenance is null`) is stronger but still vacuous if no such events exist.
- **No test touches the `public.*` wrappers** (see §2). If they're stale, every assertion still passes.
- **Strong and real:** the `auth.role() IS NULL` gate in section 5, the "change-a-pin-flips-the-verdict" test in section 4 (this is the one that distinguishes "fixed the baseline" from "muted the alarm"), the stale-hash-absence check, and the incomplete-baseline-must-raise checks. These would all fail on regression.

**Bottom line:** the core refactor is sound and the structural guard is correctly designed. Block/clarify before merge on: (a) confirm `public.*` wrappers delegate rather than duplicate; (b) decide whether mutating `taxonomy_circuit_breaker_event` is acceptable given §6.3, or populate `trip_provenance` only on new trips; (c) close the TRUNCATE gap; and (d) add an explicit "preview-only until parent Phase 6 migrations + production-correct pins land" note so this isn't promoted to production as-is.
