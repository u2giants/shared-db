# DB Data Admin — non-SSO tester login (data-dev only)

**Status:** shipped and verified 2026-07-23/25. This is reference documentation for a
**completed** feature — it lived in `HANDOFF.md` while in progress and was moved here
once done, so the handoff only carries unfinished work.

Related: [db-data-admin-column-multi-filter.md](db-data-admin-column-multi-filter.md)
(the grid work this login was created to verify).

Owner approved "gate to data-dev only" on 2026-07-23. Shipped in PR #195 (`3d3c434`);
tester user created; flag live on data-dev; credential stored in 1Password as
**"DB Data Admin AI tester login (data-dev.designflow.app) - non-SSO"**.

### What exists now

| Piece | State |
|---|---|
| `allowPasswordLogin` flag (`config.ts`, `nginx.conf`, `App.tsx`) | Merged in #195. Strict opt-in: only `true` / `"true"` enables it. |
| Coolify env `DB_DATA_ADMIN_ALLOW_PASSWORD_LOGIN=true` | Set on app `v6z1sveur7e32dub1dp3ao4v` (`db-data-admin-development`) **only**. |
| Tester auth user | `ai-tester@data-dev.designflow.app`, auth id `0a55652c-260e-41ac-aa8a-18636bcfab6b`, profile `098e5791-101b-4cf3-8a9e-8efccc2040d7`. Granted BOTH `administrator` role AND explicit `app_access('admin')` — see "two grants" section. |
| Invitation row | `public.invitations` id `f9b1301f-c1af-421e-8ad0-5c7c896c067e` (required — see gate below). |
| Credential | 1Password vault `vibe_coding`, item `agk4gstcwazitt76evs5r2agvi`. |

Verified end-to-end (2026-07-24, build `1fe8ad4`): logged in headlessly via the tester
credential (1Password-injected, browser automation), loaded **155 real rows**, opened the
Status Set Filter popover (options `active` / `potential`), confirmed the value-search box
narrows the list, and confirmed unchecking a value filtered the grid **155 → 15**. The
text filter also works (`155 → 3` on "a"). Production `data.designflow.app` has no server
running and never received the flag.

The Set Filter popover was also **clipped by RevoGrid's header overflow** on first live
test (only the first checkbox showed) — fixed by portalling it to `document.body`
(PR #211). This class of bug is invisible to the jsdom unit tests; always verify grid
overlays in a real browser.

### The invitation gate — READ THIS BEFORE RECREATING THE USER

`public.handle_new_user` (trigger on `auth.users`) makes **email/password signup
invitation-only**; only provider `azure` / `authentik` bypasses it. Creating an
email/password user without an invitation row fails with HTTP 500
`{"code":"P0001","message":"Access denied: no valid invitation found for …"}`.
**This is a deliberate guardrail — do not disable or edit the trigger.** Insert an
invitation first:

```sql
insert into public.invitations (email, role, apps)
values ('<email>', 'user', array['popdam']::public.app_name[]);
```

then create the user via the Auth Admin API with `email_confirm: true`, then grant access
(next section).

### The full authorization requires TWO grants, not one (learned the hard way)

The DB Data Admin RPCs do **not** gate on the administrator role alone. Every
`db_data_admin_*` RPC calls `app.require_db_data_admin_access()`
(`supabase/migrations/20260722005000_db_data_admin_read_contracts.sql:29`), which requires
**both**:

1. `app.has_role('administrator')` — the `app.user_role` row (trigger only auto-grants
   this to `u2giants@gmail.com` / `albert@popcre.com`, so insert it manually), **and**
2. `app.has_explicit_app_access('admin')` — a **non-revoked `app.app_access` row for app
   `'admin'`**. Note `has_explicit_app_access` (`…20260722002500…:5`) does NOT give
   administrators an implicit grant — the row must exist.

The signup trigger `app.handle_new_auth_user` only grants `app_access` for `'crm'`, so a
freshly created admin still gets **HTTP 403 `{"code":"42501","message":"db_data_admin:
not authorized"}`** and the UI shows "Data could not be loaded." Both grants for the live
tester:

```sql
-- role grant
insert into app.user_role (profile_id, role_id)
select p.id, r.id from app.profile p, app.role r
where p.auth_user_id = '<auth uid>' and r.slug = 'administrator'
on conflict do nothing;
-- explicit admin app_access — the piece that is easy to miss
insert into app.app_access (profile_id, app)
select p.id, 'admin'::app.app_name from app.profile p
where p.auth_user_id = '<auth uid>'
on conflict (profile_id, app) do update set revoked_at = null;
```

### How an AI session should use this credential

Use a 1Password-mediated path so the plaintext password never enters the AI's context.
Two that work:

1. **Browser + 1Password extension** — drive the owner's real Chrome (the
   `claude-in-chrome` tooling) and let the 1Password extension autofill the form.
2. **Programmatic session injection (best for automation)** — exchange the credential
   for a session token with the plaintext redacted, then drive the authenticated app:

   ```
   POST https://rjyboqwcdzcocqgmsyel.supabase.co/auth/v1/token?grant_type=password
   headers: apikey: <branch anon key>
   body:    {"email":"ai-tester@data-dev.designflow.app","password":"<op:// reference>"}
   ```

   Run it through `op_run` with the password supplied as an `op://` reference so the
   value is redacted from the transcript. Then set the returned session into the app's
   Supabase storage key before loading the page.

An earlier revision of this file claimed an AI session "cannot" use this login at all.
That was wrong — what is avoided is handling the plaintext password directly, not using
the credential.

### Original goal (kept for context)

Albert asked for "internal (non-SSO) credentials to `https://data-dev.designflow.app`
for testing purposes," stored in 1Password, so an AI session can log in and drive the UI
(the Multi Filter work shipped this session could not be visually verified for exactly
this reason).

### Why it had to be gated — read before changing it

1. **The app is Microsoft-SSO only.** `apps/db-data-admin/src/App.tsx` offers a single
   auth path: `supabase.auth.signInWithOAuth({ provider: 'azure' })`. There is **no**
   email/password form. A password user therefore cannot log in through the UI until the
   app gains a `signInWithPassword` form — this is an app **code** change, not just a
   user record.
2. **That code change would also reach production.** `data.designflow.app` (production)
   and `data-dev.designflow.app` (development) are built from the **same** codebase and
   the same GHCR image; only the injected `/config.js` differs (see `nginx.conf` →
   `DB_DATA_ADMIN_*` env). Adding a password form without an explicit environment gate
   would open a non-SSO door on **production** DB Data Admin.
3. **data-dev is NOT a throwaway sandbox.** It points at Supabase preview branch
   `rjyboqwcdzcocqgmsyel` (`shared-db-schema-rehearsal`), which the 1Password item
   "Supabase Preview Branch Credentials - shared POP database" documents as a
   *persistent production clone (`with_data=true`)* whose data is
   **"production-sensitive."** DB Data Admin can edit and **merge** records. A password
   credential with an Administrator grant there is effectively production-grade access.

### The design that was built (owner-approved)

- Add an email/password sign-in form **gated behind an explicit runtime flag**
  (e.g. `DB_DATA_ADMIN_ALLOW_PASSWORD_LOGIN`, surfaced through `/config.js` and
  `readConfig()`), set **only** on the data-dev Coolify application. Production stays
  SSO-only and the form never renders there.
- Enable the email provider on branch `rjyboqwcdzcocqgmsyel` only.
- Create one tester user with a long generated password, grant it Administrator, and
  store it in 1Password vault `vibe_coding` with full usage notes.

#### Exact Administrator grant chain (verified against migrations, 2026-07-23)

A Supabase auth user alone is **not** enough — every `db_data_admin_*` RPC ultimately
calls `app.has_role('administrator')`, which resolves through three tables. All of these
rows must exist or the app renders its "Access denied" screen:

1. `auth.users` — the tester user (created via the Admin API with the branch
   service-role key, `email_confirm: true`).
2. `app.profile` — a row with `auth_user_id = <that user's id>` **and
   `status = 'active'`**. `app.current_profile_id()` (`20260621150815_app_core.sql:351`)
   returns nothing without both, and every role check then fails.
3. `app.user_role` — a row joining that `profile_id` to `app.role` where
   `slug = 'administrator'`, with **`revoked_at is null`**
   (`app.has_role`, `20260621150815_app_core.sql:365`).

Definitions: `app.profile` and `app.user_role` in
`supabase/migrations/20260621150815_app_core.sql:12`; the `administrator` role is seeded
at `:340`; the `app.app_role` enum is in `20260621150714_foundation.sql:19`.

Per the shared-db rule, any DDL stays migration-authored — but this is **row data on a
preview branch**, so insert it directly there; do **not** add a migration that seeds a
tester account, and never create this user on production `qsllyeztdwjgirsysgai`.

#### Verification gate (do not report done without these)

1. `GET /config.js` on data-dev shows the password-login flag enabled, and production's
   `/config.js` does **not**.
2. Sign in at `https://data-dev.designflow.app` with the stored credentials and confirm
   the Customers grid renders — not the "Access denied" panel.
3. Confirm the same build on `data.designflow.app` still shows **only** the
   "Sign in with Microsoft" button.

### Access status

Access is **available** — no new credentials need to be requested:
- Preview branch service-role key + Postgres URL: 1Password →
  *"Supabase Preview Branch Credentials - shared POP database (shared-db-schema-rehearsal)"*.
- Supabase management PAT: 1Password → *"Supabase CLI Personal Access Token"*.
- Note: `rjyboqwcdzcocqgmsyel` is a **branch**, so it does **not** appear in
  `GET https://api.supabase.com/v1/projects`. Do not conclude the token is wrong —
  list branches instead.

### If you need to change this

Never set `DB_DATA_ADMIN_ALLOW_PASSWORD_LOGIN` on the production Coolify app. To revoke
the tester instead of deleting it, set `revoked_at` on its `app.user_role` row, or unset
the Coolify variable and redeploy to remove the form entirely.

