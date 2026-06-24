> ⚠️ **Auto-synced — do not hand-edit the copies.**
>
> [`u2giants/shared-db`](https://github.com/u2giants/shared-db) is the **single source of truth**. Its entire contents are mirrored into the **`shared-db/` folder** of every consumer repo (CRM, DAM, PM, Directus) on each push to `main`.
>
> **Reading this inside a consumer repo's `shared-db/` folder?** It's a read-only copy — edits here are overwritten on the next sync. Change the canonical repo instead.

---

# AGENTS.md — cross-app coordination playbook

This is the operating contract for **every AI session working on any of the four
apps that share one Supabase database** (PM/PIM `poppim-web`, CRM `popcrm-web`,
DAM `popdam-web`, and the `directus` backend). Read it before touching code or
the database. It exists to stop four apps — often driven by separate AI sessions
— from breaking each other through the one database they all depend on.

## 0. The owner is not a programmer

The repository owner directs the work and judges results, but does **not** review
code, manage branches, or merge pull requests. Therefore:

- **The AI owns all git mechanics.** Branches, commits, pull requests, and merges
  are the AI's job from start to finish. Never leave an open PR for the owner to
  deal with — open it *and* merge it within the same piece of work, once it is
  safe (see §4).
- **The owner reviews behavior, not code.** Their feedback is "the board doesn't
  load," "the dropdown is empty." Translate that into changes yourself.
- **Surface risk in plain English.** Before anything hard to undo (dropping a
  column, applying to production, deleting data), explain the risk in one or two
  plain sentences and ask. Approval for one change does not extend to the next.

## 1. Two workflows — choose by where you are working

| Where | Workflow | Why |
|---|---|---|
| **An app repo** (`poppim-web`, `popcrm-web`, `popdam-web`, `directus`) | Commit straight to **`main`. No branches.** Build must pass, then push; CI deploys. | One app, one owner, a deploy you can watch. Branches add ceremony with no safety gain. Fix-forward or revert on `main`. |
| **This repo** (`shared-db`) | **Branch + PR, and the AI merges it** once the §4 checklist passes. | All four apps read these tables. A bad change breaks everyone at once. The PR is a safety checkpoint and an undo button — not paperwork for the owner. |

## 2. Why `shared-db` is the dangerous one

Every app reads and writes the **same tables in the same Supabase project**. A
single schema change here can break an app that a different session built months
ago. The database has no "just this app" — it is always shared. That is why the
four rules below are non-negotiable for any database change.

## 3. The four anti-collision rules (shared database)

1. **One schema change in flight at a time.** Before starting database work,
   check whether another change is already in progress (§5). If so, finish or
   land that one first, or coordinate with the owner. Two simultaneous schema
   edits are the number-one cause of a broken shared database.
2. **Preview database first. Production never receives untested schema.** Apply
   every migration to the preview branch (`xjcyeuvzkhtzsheknaiu`), prove it
   works, *then* promote to production (`qsllyeztdwjgirsysgai`).
3. **Additive by default (expand, then contract).** Adding a column or table
   cannot break another app. **Renaming or dropping** one that another app reads
   *will*. Default to additive changes. Only rename/drop after explicit owner
   sign-off and a checked deprecation across all four apps.
4. **New timestamped migration files only.** Each change is a new
   `YYYYMMDDHHMMSS_*.sql` file. Never edit a migration that has already been
   applied anywhere — that is how two sessions silently clobber each other.

## 4. The `shared-db` merge protocol (the checklist the AI runs)

Merge a `shared-db` PR **only when every item is true**:

1. `scripts/check-sql.sh` passes.
2. `supabase db push --dry-run` against the preview branch is clean (only the
   intended changes, no surprise drops/renames).
3. The migration is applied to the **preview** branch and works there.
4. Every app that depends on the change has been tested against preview and the
   owner has confirmed the behavior is correct.
5. The change is additive, or any removal was explicitly approved.

Then: merge to `main` (this auto-syncs the `shared-db/` folder into all apps) and
promote to **production only in an approved window**. Docs-only PRs (no schema
change) need just items 1 and "it reads correctly" — merge them promptly.

## 5. How to tell if a change is already in flight

Before starting database work, run these and read the result:

```bash
gh pr list                      # open shared-db PRs
git branch -a && git ls-remote  # in-progress branches
ls supabase/migrations          # files not yet applied to production
git status --short              # uncommitted migration files in the working tree
```

If anything looks like in-progress database work, **stop and serialize** — land
it (or ask the owner) before adding your own schema change.

## 6. When two apps need conflicting database changes

Serialize, do not parallelize. Land one change, let it sync, test it, then start
the next. Where possible, prefer one **additive** change that satisfies both apps
rather than two competing edits. If they genuinely conflict, explain the trade-off
to the owner in plain English and let them choose order.

## 7. Project references

```text
Preview project ref:  xjcyeuvzkhtzsheknaiu   (Supabase branch "shared-db-schema-rehearsal")
Production project ref: qsllyeztdwjgirsysgai
```

Never commit anon keys, service-role keys, database passwords, or `.env` files.

## 8. PostgREST exposed schemas are part of the app contract

What changed:
On 2026-06-23, the PM frontend cutover follow-up verified that production
PostgREST exposed `api`, `crm`, `pim`, and `core`, but not `app`. Browser reads
against `app.comment`, `app.activity`, `app.notification`, and `app.profile`
failed with `Invalid schema: app` until production `pgrst.db_schemas` was
updated to include `app` and the PostgREST config/schema cache was reloaded.

Why:
RLS policies and table grants are not enough. Any schema used through
`supabase.schema('<schema>')` from a browser app must also be listed in
PostgREST's exposed schemas for that Supabase project.

Future sessions should:
When adding browser reads/writes to a non-`public` schema, verify
`pg_roles.authenticator.rolconfig` includes the schema in `pgrst.db_schemas`,
test the REST contract with the matching `Accept-Profile`, and capture durable
config changes in `shared-db` migrations/docs instead of relying on app-only
workarounds. `scripts/check-sql.sh` intentionally checks the latest
`pgrst.db_schemas` migration so future changes cannot silently drop `app` again.

## 9. CRM contact relationship writes are not plain contact writes

What changed:
On 2026-06-23, popcrm-web commit `5e2622a` changed contact relationship edits to
send the current account context and explicit clear flags to
`api.crm_update_contact`. The matching shared-db migration is
`20260623024500_crm_update_contact_clear_relationship_fields.sql`.

Why:
CRM fields such as account, department, contact type, and scope live on
`core.contact_company`, not only on `core.contact`. A null value can mean "leave
unchanged" or "clear this relationship field", so the RPC contract needs explicit
booleans for clears.

Future sessions should:
Do not replace `api.crm_update_contact` with direct `core.contact` writes for CRM
relationship edits. Preserve the account context and clear-flag contract, and
verify the migration is applied before expecting browser edits to clear
department/type/scope or remove the primary buyer relationship.

## 10. Where to read more

- App rewrite guides: [`docs/ai-session-instructions/`](docs/ai-session-instructions/README.md)
- Shared branch workflow: [`docs/ai-session-instructions/shared-supabase-branch-workflow.md`](docs/ai-session-instructions/shared-supabase-branch-workflow.md)
- Schema ownership map: [`docs/unified-supabase-schema-map.md`](docs/unified-supabase-schema-map.md)
- Migration risks: [`docs/unified-supabase-migration-gaps.md`](docs/unified-supabase-migration-gaps.md)
