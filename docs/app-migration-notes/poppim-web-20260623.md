# poppim-web Supabase Migration Follow-Up

Date: 2026-06-23

## Status

Production follow-up for the PM/PIM frontend cutover to the shared Supabase.com
project `qsllyeztdwjgirsysgai`.

Follow-up migration `20260623082005_expose_app_schema_to_postgrest.sql`
codifies the production PostgREST configuration issue that was verified and
fixed manually during the app follow-up. Applying that migration should still go
through the shared-db preview/production workflow.

## Done

- Populated PM local frontend environment values for the production Supabase URL
  and anon key, and added the anon key placeholder/value to the PM
  `.env.example`. The anon key was obtained with the Supabase CLI, not found in
  the 1Password item checked during the session. No secret/service-role value
  was committed.
- Regenerated `poppim-web/src/lib/database.types.ts` from production with
  schemas `app,core,pim,crm,dam,plm,ingest,api`, so generated types now include
  `pim`.
- Updated the PM schema helper so `pim()` returns `supabase.schema('pim')` with
  generated types, and removed frontend `pim() as any` escape hatches.
- Backed previously placeholder PM screens with Supabase reads:
  Schedule, Notes, and People.
- Enriched raw `pim.product` records with board-view display fields where
  screens still read base product rows.
- Preserved existing `app.notification.payload` keys when changing reminder
  status.
- Wrote `pim.stage_history` when the frontend moves a product stage.
- Verified in `poppim-web`: TypeScript build, production build, lint, and
  whitespace diff checks passed. Lint/build warnings remained warnings only.

## Production PostgREST Finding

What changed:
Production `authenticator` had `pgrst.db_schemas` set to
`public, graphql_public, api, crm, pim, core`. PM now reads `app.comment`,
`app.activity`, `app.notification`, and `app.profile` directly through the
authenticated browser client, so REST requests using `Accept-Profile: app`
failed with `Invalid schema: app`.

Why:
The `app` schema is the shared support/collaboration layer for profiles,
comments, activity, notifications, and generic app records. Grants/RLS are not
reached if PostgREST does not expose the schema.

Future sessions should:
Verify `pg_roles.authenticator.rolconfig` includes `app` alongside the other
browser-facing schemas before declaring PM/CRM production healthy. The original
session manually updated production to include `app` and reloaded PostgREST
config and schema cache; follow-up migration
`20260623082005_expose_app_schema_to_postgrest.sql` records the durable desired
state. After reload, REST could see the `app` tables; anonymous access was still
denied, while `authenticated` and `service_role` had usage on `app` and `pim`.

## PM Frontend Contracts Observed

| Area | Supabase contracts used |
|---|---|
| Auth/profile | Supabase Auth, `api.current_user_profile`, `app.profile` |
| Pipeline board | `api.pm_product_board`, `pim.product`, `pim.stage`, `pim.product_assignee`, `pim.checklist_item`, `pim.product_file`, `app.comment` |
| Product detail/collaboration | `pim.product`, `pim.checklist_item`, `pim.product_assignee`, `pim.product_file`, `pim.product_update`, `pim.product_tag`, `pim.product_field`, `pim.product_link`, `pim.product_time_entry`, `app.comment`, `app.activity`, `app.notification` |
| Workflow records | `pim.product_submission`, `pim.product_sample`, `pim.revision_request`, `pim.customer_order` |
| Saved views/settings | `pim.saved_view`, `pim.view_pref` |
| Schedule | `pim.product`, `pim.product_sample`, `pim.product_submission`, `app.notification` |
| Notes | `app.comment`, `app.activity` |
| People | `app.profile`, `pim.product_assignee`, `app.notification`, `pim.revision_request` |
| My Work | `pim.product_assignee`, `pim.product`, `pim.revision_request`, `app.notification` |
| Control Room/Reports | `pim.product`, `pim.project`, `pim.design`, `pim.customer_order`, `pim.revision_request`, `pim.product_submission`, `pim.product_sample`, `pim.stage_history`, `app.activity`, `app.notification`, `pim.saved_view` |

## Known Gaps / Watchouts

- `api.pm_product_board` does not expose every field the PM frontend needs for
  migrated display/filter behavior, especially product metadata. The frontend
  currently stitches `api.pm_product_board` display data to `pim.product`
  metadata. Prefer adding explicit API-view columns or a PM detail/board RPC in
  shared-db over expanding frontend stitching further.
- No RLS policy changes were made during this follow-up. The session verified
  schema usage and PostgREST exposure, not final PM role allow/deny behavior.
- No realtime subscriptions were added or tested during this follow-up.
- Preview-branch parity was not re-tested in this follow-up; the app work used
  the production Supabase project. Future migration/config changes should still
  go through preview first.
- The production anon key was retrievable through Supabase CLI but was not found
  in the checked 1Password item. Future secrets hygiene work should store the
  publishable anon key in the approved 1Password location without storing any
  service-role key in frontend repos.
