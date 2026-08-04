# Phase 6 baseline pins + breaker environment (2026-08-04)

Two fix-forward migrations. Neither edits an applied migration.

- `20260804120000_taxonomy_baseline_pins_table.sql`
- `20260804120100_taxonomy_breaker_environment_and_provenance.sql`
- Contract tests: `supabase/tests/taxonomy_baseline_pin_and_breaker_environment_contracts.sql`

## What was wrong

`20260726180000` pinned the Phase 4 baseline as PL/pgSQL `constant` declarations in
two functions. On 2026-08-02 the approved owner ruling in
`20260802171000_owner_ruling_friends_tv_frida_kahlo.sql` set a licensor to
`inactive`. That is correct data, and it changed `core.licensor`'s status hash from
`d9b07759bf80ff227e2fa9bd635d2138` to `00bf7069fff79b9deab1d14dbd9112b2`. The pinned
constant could not follow, because an applied migration is immutable.

Verified live on preview `rjyboqwcdzcocqgmsyel` on 2026-08-04: **every other pin
still matched exactly** — 26 licensors, 256 properties, 1047/542/505 source refs,
38/504 links, both UUID hashes, the property status hash, the parent edge hash.
Exactly one value differed. That single-value signature is what distinguishes an
owner ruling from real drift.

Consequences: `baseline_ok` false on every non-drill observation since 2026-08-03,
a critical alert daily (23 unacknowledged, 08-02 to 08-04), and the
`coldlion_licensor_property` breaker auto-tripped at 2026-08-02 11:16:31-04.

Separately, `plm.taxonomy_circuit_breaker.environment` held
`auto (alert 4f44ec88-…)` — provenance, not an environment — because the auto-trip
functions in `20260728134500` call the trip function **positionally** and the 5th
slot is `p_environment`. The fallback in `20260727221500` line 170 was
`server_version_num`, a PostgreSQL version.

## What changed

`plm.taxonomy_baseline_pin` holds the expected values as rows with provenance
(who pinned it, when, why). Both Phase 6 functions read it via
`plm.taxonomy_baseline_pin_set()`, which **raises** if any of the twelve metrics
has no live pin — a missing pin must never read as "nothing to compare". The table
is append-only: a pin is retired by stamping `superseded_at`, enforced by a
**structural** trigger that does not consult `auth.role()` (NULL inside a
migration, which makes any role-based guard silently permissive).

`trip_provenance` columns now carry the cause. `plm.deployment_environment` names
the database. The trip function gained `p_provenance` as a ninth parameter with a
default, so all nine existing call sites work unchanged, and the two auto-trip
functions now call it with **named** arguments.

## Required post-apply step, once per environment

No in-database value distinguishes preview from production (probed 2026-08-04: no
project ref in `pg_settings`, `pg_db_role_setting`, `pg_roles`; `current_database()`
is `postgres` and `cluster_name` is `main` in both). So the environment is explicit
configuration, seeded loud as `unconfigured (db=postgres)` rather than guessed.

Run both statements, in order, after the migrations apply:

```sql
update plm.deployment_environment
   set environment_name  = 'preview rjyboqwcdzcocqgmsyel',   -- production: 'production qsllyeztdwjgirsysgai'
       configured_by     = 'Albert Hazan (owner)',
       configured_at     = now(),
       configured_reason = 'Supabase preview project for the shared backend',
       updated_at        = now()
 where singleton;

update plm.taxonomy_circuit_breaker
   set environment = plm.resolve_deployment_environment(), updated_at = now()
 where environment is null;
```

Already done on preview. **Production has not been touched.**

## Evidence (preview, 2026-08-04)

| Proof | Result |
|---|---|
| Positive: new observation `7665e5dc-…` | `baseline_ok = true`, `pass = true`, hash `00bf7069…` |
| Negative: forced drill | alert `27fb2a02-…`, `severity = critical`, `is_drill = true` |
| Wrong pin injected (rolled back) | `baseline_ok` flips to false — the gate reads the table |
| Grants before / after | `postgres=X/postgres ; service_role=X/postgres` on every replaced function — unchanged |

The 23 pre-existing alerts were **not** acknowledged and the breaker was **not**
reset. Clearing them is a separate step that must happen after this lands, or the
evidence that the fix worked is destroyed.
