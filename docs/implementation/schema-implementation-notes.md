# Schema Implementation Notes

Date: 2026-06-21

These migrations implement the first migration-ready version of the unified Supabase schema described in the mapping docs. They are intentionally DDL-only; the production project also contains older PopDAM migration-history marker files so Supabase CLI can reconcile this repo with the existing production ledger.

## Files

| File | Purpose |
|---|---|
| `supabase/migrations/20260621150714_foundation.sql` | Extensions, logical schemas, shared enums, timestamp trigger helper, and schema comments. |
| `supabase/migrations/20260621150815_app_core.sql` | Shared app/profile/role tables, canonical `core` business objects, source-reference spines, SKU refs, and auth helper functions. |
| `supabase/migrations/20260621151024_domain_tables.sql` | DAM, CRM, PIM/PM, PLM, ingest, and cross-domain bridge tables. |
| `supabase/migrations/20260621151155_api_rls_realtime.sql` | Browser-facing `api` views, RLS scaffolding, grants, and selected realtime publication tables. |
| `supabase/migrations/20260622043000_crm_contact_segments.sql` | CRM Contacts segmented API: preserves `api.crm_contact_list`, adds `api.crm_contact_segment_list`, adds `api.crm_contact_segment_counts`, and indexes the primary contact-company relationship lookup. |
| `supabase/migrations/20260623024500_crm_update_contact_clear_relationship_fields.sql` | Replaces `api.crm_update_contact` with explicit clear flags for CRM relationship fields on `core.contact_company`; preserves the guarded core-contact update path. |
| `supabase/migrations/20260623082005_expose_app_schema_to_postgrest.sql` | Codifies the production PostgREST exposed-schema fix so browser clients can query `app.*` support tables through Supabase REST. |

## Production Migration History

The production Supabase project started as a PopDAM project and already had a
long migration history before `shared-db` became the canonical coordination repo.
Supabase CLI requires every remote migration version to exist locally before it
will run `supabase db push --dry-run`.

For that reason, this repo includes no-op marker files for pre-shared-db PopDAM
migrations. They intentionally contain comments only. Do not add schema logic to
those marker files, and do not use `supabase migration repair` to hide them from
the production ledger.

## What This Implements

- One Supabase project with logical schemas: `app`, `core`, `dam`, `pim`, `crm`, `plm`, `ingest`, and `api`.
- Shared canonical owners for duplicate business objects:
  - customers/accounts in `core.company`
  - buyers/contacts in `core.contact`
  - licensors/properties/characters in `core`
  - factories/vendors in `core.factory`
  - product/category/merch/SKU matching in `core`
- App-owned domain tables for DAM, CRM, PM/PIM, and PLM.
- Explicit source-reference tables instead of overwriting Directus, PopDAM, PLM, ClickUp, or ERP ids.
- Bridge tables for the important crossover points:
  - `pim.product.plm_item_id`
  - `pim.product_style_group`
  - `pim.design_asset`
  - `crm.opportunity.project_id`
  - `crm.opportunity_product`
  - `pim.customer_order.production_order_id`
- Stable first-pass `api` views for frontend contracts.
- CRM-specific contact segment contracts so popcrm-web can fetch customer,
  department, and triage contacts separately while lazy-loading All.
- CRM contact relationship edit semantics in `api.crm_update_contact`: name,
  email, phone, title, LinkedIn, and salesperson update `core.contact`, while
  company, department, contact type, and scope update the primary
  `core.contact_company` buyer relationship and can be intentionally cleared
  through explicit `p_clear_*` flags.
- RLS enabled across app/domain tables, with conservative policies.
- Realtime publication candidates for user-facing movement, not worker/admin queues.

## What This Does Not Do Yet

- It does not migrate data.
- It does not physically move existing PopDAM public tables.
- It does not import Directus system metadata.
- It does not migrate files from DigitalOcean Spaces or Directus storage.
- It does not implement final vendor row scoping.
- It does not expose pricing-safe role-specific PLM/RFQ views yet.
- It does not include PLM sample tracking because the selected `main` source does not contain those models.

## Rehearsal Order

1. Apply these migrations only to a disposable Supabase branch/project.
2. Restore or load source data into staging/import tables.
3. Populate `core.*_source_ref` and `core.sku_ref` before merging duplicates.
4. Backfill canonical `core` rows.
5. Load domain tables with preserved `external_source` and `external_id`.
6. Run dedupe reports and reject uncertain matches before hard-linking DAM/PM/PLM entities.
7. Test RLS with real Supabase Auth users and app access rows.
8. Enable/write frontend adapters against `api` views or RPCs.
9. Only then plan a production migration or cutover.

## RLS Notes

The policies are a scaffold, not final authorization.

- `administrator` can write most shared/domain data.
- PM writes are limited to administrator/licensing/designer/sales roles.
- CRM writes are limited to administrator/sales/licensing roles.
- DAM writes are limited to administrator/designer/licensing roles for library data.
- PLM writes are administrator-only because PLM data should normally come from service-side syncs.
- Worker queues, raw ingest, source refs, and admin helper tables are admin-only or service-role-only.

Before production use, add field-safe views for pricing/cost data and implement user-to-factory/vendor mapping before granting vendor product/order access.

## Operational Config Notes

### Browser-exposed schemas must include `app`

What changed:
The 2026-06-23 PM frontend production follow-up found production PostgREST
configured with `pgrst.db_schemas=public, graphql_public, api, crm, pim, core`.
That made `app` invisible to browser Supabase clients even though PM uses
`app.comment`, `app.activity`, `app.notification`, and `app.profile` as shared
collaboration/support tables. Production was manually updated to include `app`
and PostgREST was reloaded. The durable follow-up migration is
`20260623082005_expose_app_schema_to_postgrest.sql`.

Why:
The shared schema intentionally keeps collaboration records in `app`, and the PM
frontend now reads those records directly through the authenticated browser
client. Schema usage grants and RLS do not help if PostgREST rejects the schema
before the query reaches PostgreSQL policies.

Future sessions should:
Keep `scripts/check-sql.sh` enforcing that the latest migration touching
`pgrst.db_schemas` includes `public, graphql_public, api, crm, pim, core, app`.
When a frontend starts using another non-`public` schema, update the migration
and static check together. Do not grant `anon` schema usage just to fix
visibility; PM is auth-gated, and the verified production state kept `anon`
denied while `authenticated` and `service_role` had usage.
