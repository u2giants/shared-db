# Post-batch application verification — the runnable half of §7

**Issue:** [#711](https://github.com/u2giants/shared-db/issues/711) — owner ruling **D7**.
**Script:** `scripts/post_batch_app_verification.py`
**Tests:** `scripts/test_post_batch_app_verification.py` (105 tests, no network, no database).
**Contract it implements:** `docs/production-promotion-app-tolerance-contract.md`, §3, §5, §6, §7.

---

## 1. Why this exists

§7 of the tolerance contract is a manual checklist: a person with logins to three applications and
SSH to the PopCRM worker host, run **nine times**, once after every batch. §8/D7 asked who that
person is. Nobody was ever named, and **the checks were never run after batch B1 — which is already
applied to production**.

The owner ruled that an AI agent does these checks instead of a human. That ruling means nothing
unless the check is a **runnable artifact**. "An agent clicks around three apps" is not a check, it
is a hope. This is the artifact.

**It does not replace §7.1's five-minute smoke test.** It replaces the part of §7 that a database
can answer, which is most of it, and it says plainly which part it cannot answer (§6 below).

---

## 2. How to run it

After a batch lands, from a checkout of `main`, with a Supabase Management API PAT in the
environment:

```bash
export SUPABASE_ACCESS_TOKEN='<PAT from 1Password vault vibe_coding, item 3t2xoqk5luyz7ffgdhj24gvtpq, field credential>'

python scripts/post_batch_app_verification.py \
  --batch B8 \
  --project-ref qsllyeztdwjgirsysgai \
  --output-dir artifacts/post-batch
```

On PowerShell:

```powershell
$env:SUPABASE_ACCESS_TOKEN = '<PAT>'
$env:PYTHONIOENCODING = 'utf-8'
python scripts/post_batch_app_verification.py --batch B8 --project-ref qsllyeztdwjgirsysgai --output-dir artifacts\post-batch
```

Instead of `--batch` you may pass the exact versions that were applied, which is the safer form
because it makes the script check that you are actually at a legal resting point:

```bash
python scripts/post_batch_app_verification.py \
  --versions 20260809170000,20260809170100,20260809170200,20260809170300,20260809170400,20260809170500 \
  --project-ref qsllyeztdwjgirsysgai \
  --output-dir artifacts/post-batch
```

**The token is read from the environment, never from `argv`** — process arguments are visible in OS
process listings. Do not pass it as a flag; there is no flag for it.

### What you get

- **Exit code 0** — all three applications PASS.
- **Exit code 1** — at least one hard failure, printed to stderr, one line each.
- `artifacts/post-batch/post-batch-app-verification.md` — the human-readable report.
- `artifacts/post-batch/post-batch-app-verification.json` — the raw catalog evidence.

Keep the artifact. The job log gets scrolled past; the artifact is the evidence.

---

## 3. What it checks

For **PopPIM**, **PopDAM** and **PopCRM** — the three applications the contract §2.3 proves are
exposed to the shared production project — it asks the catalog, not the migration ledger:

| Check | Primitive | Why |
|---|---|---|
| The relation exists | `to_regclass` | "It applied successfully" proves nothing |
| It is the right kind | `pg_class.relkind` | A view where the app reads a table is a different bug, still a bug |
| The role can use it | `has_table_privilege` | A lost grant breaks an app with every object intact |
| The function exists | `pg_proc` overload count | An applied `create or replace` whose routine is not there is a catastrophe |
| The role can execute it | `has_function_privilege` | Same |
| Filter columns exist | `information_schema.columns` | A missing filter column is a 400 or a **silently empty result** |
| Embed FKs exist | `pg_constraint` | PostgREST resolves `.select('contact:contact_id(...)')` through the FK; drop it and the request 400s |
| Schemas are exposed | `pg_db_role_setting` | The apps reach the database THROUGH PostgREST |
| The clock agrees | `TimeZone` + a midday-UTC pin | This database runs `America/New_York` |
| Batch-specific facts | §7.2 | See below |

Plus the **batch-specific** assertions the contract names in §7.2, one query each:

| Batch | Asserted |
|---|---|
| **B1** | `sync_coldlion_licensors_properties` is 3-arg; the 2-arg overload is **gone** from both `plm` and `public` |
| **B6** | The 8-argument `trip_taxonomy_circuit_breaker` is gone from both schemas |
| **B7** | `api.opa_property_reconciliation` survived its drop-and-recreate, and has a readable definition |
| **B8** | `core.product_size` exists, holds rows, holds **active** rows; `core.product_depth` exists |
| **B9** | `api.dam_order_list` has `security_invoker=true` (#653); no Warner `plm.wb_*` SELECT policy is still `using (true)`; `service_role` holds no TRUNCATE on `plm.pmt_*` |

And it refuses to certify an illegal state: if the last version applied is on contract §6's
never-rest list, or is the retired `20260729120000`, or is one of the two §6.5-held versions, the run
**fails** and tells you to complete the batch rather than verify and wait.

---

## 4. Where the object list came from

Derived on 2026-08-10 from **fresh shallow clones of `origin/main`** of `poppim-web`, `popdam3` and
`popcrm-web` — not from the stale local checkouts, which contract §2.3 records as having produced
four confidently wrong answers. Every entry traces to a real `.rpc()`, `.schema().from()` or
realtime call site, and each carries its file and line in the `why` field.

Two things are **inferred, not observed**, and the script says so in its own docstring:

1. **Privileges** are the verbs the code needs, derived by scanning each `.from('x')` call site for
   the `.select` / `.insert` / `.update` / `.delete` that follows it. They are not a copy of
   production's grant matrix — if they were, the check could never detect a lost grant.
2. **Role attribution** is by file location: `src/` is `authenticated`, `workers/` and
   `apps/worker/` are `service_role`.

---

## 5. Three findings the first live run produced

The first run against production (batch B1 applied, nothing since) exited 0 with all three
applications PASS — **the B1 check that D7 says should have happened and never did**. It also
surfaced three things worth their own tickets:

1. **PopPIM writes that cannot work.** `authenticated` holds **SELECT and nothing else** on
   `pim.checklist_item`, `pim.product_assignee`, `pim.product_sample`, `pim.product_submission` and
   `pim.revision_request`, while PopPIM's code inserts, updates and deletes against all five. Those
   writes 403 today. It predates every batch, so it is recorded as a **baseline gap** — reported in
   every run, never suppressed, and never counted as batch damage.
2. **PopDAM's size picker is already on its hardcoded fallback.** `core.product_size` does not exist
   yet; B8 creates it. `StylesPage.tsx` swallows the error and shows `COMMON_SIZE_OPTIONS`. This is
   exactly the silent failure §3.2 warns about, happening now, and nobody has noticed.
3. **Two contract claims did not reproduce** against today's `origin/main`: `core.product_material`
   has no reader at all, and `dam_character_catalog` is read from `public`, not `api`. Both are
   recorded in the script's `MANIFEST_DRIFT` rather than dropped.

---

## 6. What it does NOT cover — read this before trusting a green run

- **It does not open the applications.** A white page, a React render crash, a broken build or a
  wrong-looking picker is invisible to a catalog query. §7.1's five-minute smoke test still stands,
  and for PopPIM a blank screen is the *expected* symptom of a break.
- **It does not read the PopCRM worker journal.** Worker failures appear only in systemd, and the
  worker's `/health` is a hardcoded `{ok:true}` that would stay green through a total schema break.
- **It does not evaluate RLS semantics.** It reads catalog grants, not what a given end user can
  actually see through a policy.
- **It does not compare function bodies, argument names, argument defaults or return shapes.**
  PostgREST resolves overloads **by argument name**; a renamed argument makes a function unfindable
  while `pg_proc` still shows an overload, and this check would pass. Renames are the dominant
  failure mode in §3.4 — the reason batching is defensible at all is that there are none in the
  backlog, not that this script would catch one.
- **It does not exercise DesignFlow non-production**, the free rehearsal of §7.0.
- **It does not check performance.** A batch that is logically safe can still hold a lock long
  enough for a live app to time out (§9.4).
- **The manifest is a snapshot.** A deploy of any of the three applications invalidates it.

### DesignFlow PLM — explicitly out of scope, and why

Contract §2.1 proves DesignFlow **production runs on Cloud SQL and cannot connect to Supabase**: the
provider, port, SSL setting, network path and username shape are all forced, and the Supabase pooler
username form is rejected outright. It therefore imposes no constraint on any batch and is not
checked here.

Its **non-production** environments (develop, staging, sandbox) are contractually bound to the shared
Supabase pooler and receive every batch instantly with no redeploy. That is a genuine exposure and a
genuine free rehearsal — but exercising a running application is not something a catalog query can
do. It stays a human step (§7.0), and the report says so in every run.

---

## 7. Design rules a future edit must not relax

1. **Absence of evidence is never a pass.** An empty result, a NULL aggregate, a failed query, an
   empty manifest — every one of them is a failure. A guard that silently admits the call is worse
   than no guard, because it reads as safety.
2. **Every verdict goes through `is_explicit_true()`.** A pass requires a non-null value AND a
   positive match. Never write `if not is_false(...)`; that is the null-permissive bug this repo has
   already shipped once.
3. **Dates are pinned to midday UTC and asserted in both zones.** The server is `America/New_York`;
   a midnight-UTC timestamp reads back through `::date` as the previous day.
4. **`plm` is not exposed via PostgREST, and that is correct.** A check that expects it there fails
   for a configuration reason, not because an application is broken.
5. **There is no record-only mode.** §7 is the entire safety net; a safety net with a soft setting is
   a decoration. The one narrow exception — recorded baseline gaps — is documented at
   `BASELINE_GAP_POLICY` in the script and is exactly one privilege wide per entry.
6. **The non-default `User-Agent` is load-bearing.** Cloudflare answers HTTP 403 (error 1010) to
   `Python-urllib`, and the run then looks like an auth failure it is not.
