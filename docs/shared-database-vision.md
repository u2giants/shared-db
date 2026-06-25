# Shared Database Vision

This repo exists to move POP from several overlapping app backends into one shared Supabase database that powers four enterprise applications:

- DAM: digital asset management, style groups, style guides, render/processing work, and asset-to-product links.
- CRM: companies, contacts, departments, opportunities, communication workflow, approvals, notes, and tasks.
- PM/PIM: projects, products, designs, design collections, licensing workflow, samples, revisions, orders, assignments, and saved views.
- PLM: operational item master, production orders, factories/vendors, licensing status, RFQ/ERP references, and production-facing workflow data.

The intention is not four separate databases that sync occasionally. The intention is one large shared database, with logical schemas and carefully controlled API contracts, so the same business objects can be used everywhere in realtime.

## Why One Database

The four apps overlap heavily:

- CRM accounts are PM customers and PLM customers.
- CRM contacts are PM buyers and account stakeholders.
- PM products become DAM style groups/assets and PLM items.
- DAM assets should appear inside PM product/design workflows without file duplication.
- PM orders and PLM production orders need to describe the same operational reality.
- Licensors, properties, characters, factories, vendors, product taxonomy, and SKUs need one canonical identity.

If each app owns a separate database, every app has to invent its own customer, contact, product, factory, asset, and order records. That creates duplicate rows, stale syncs, uncertain joins, and delayed cross-app actions.

In the shared model, apps communicate by reading and writing canonical database rows in the same Supabase project. Realtime updates come from one database state, not from frontend-to-frontend messaging.

## Architectural Shape

The shared database uses logical schemas:

| Schema | Role |
|---|---|
| `app` | shared app support: profiles, roles, app access, comments, activity, notifications, generic files |
| `core` | canonical shared business objects: companies, contacts, licensors, properties, characters, factories, product taxonomy, SKU refs |
| `dam` | DAM-owned assets, style groups, style guides, helper/agent state, queues, DAM snapshots |
| `crm` | CRM-owned opportunities, departments, email/meeting workflow, tasks, notes, approval threads |
| `pim` | PM/PIM-owned products, projects, designs, workflow, submissions, samples, revisions, orders, saved views |
| `plm` | PLM-owned item master, production orders, licensing/RFQ/ERP operational data |
| `ingest` | raw imports, sync runs, source snapshots, dedupe candidates |
| `api` | stable browser-facing views and RPC contracts |

The key split is:

- shared identity and reference objects go in `core`;
- app workflow tables stay in their app schema;
- raw imports and sync records go in `ingest`;
- frontend-facing joined shapes go in `api`.

## Canonical Ownership

These objects should have one canonical owner:

| Business object | Canonical owner |
|---|---|
| Shared account (customer or prospect) | `core.company` |
| CRM ingested email domain (NOT a company) | `crm.ingested_domain` |
| Contact/buyer/person | `core.contact` |
| Company-contact relationship | `core.contact_company` |
| Licensor | `core.licensor` |
| Property | `core.property` |
| Character | `core.character` |
| Factory/vendor identity | `core.factory` |
| Product category/type/subtype | `core.product_category`, `core.product_type`, `core.product_subtype` |
| SKU/style/item reference spine | `core.sku_ref` |
| CRM opportunity | `crm.opportunity` |
| PM product/project/design workflow | `pim.product`, `pim.project`, `pim.design` |
| DAM asset/style group | `dam.asset`, `dam.style_group` |
| PLM item/production order | `plm.item`, `plm.production_order` |

Apps can own workflows, but they should not duplicate shared identity tables.

## Company vs. Customer vs. Ingested Domain

This distinction is easy to get wrong, and getting it wrong pollutes the shared
database, so it is spelled out here as the rule for all four apps.

**There are three different concepts. They are not the same thing.**

| Concept | What it is | Where it lives | Who sees it |
|---|---|---|---|
| **Ingested domain** | A domain that merely *appeared in an ingested email*. We receive email from ~1000 kinds of companies — recruiters, vendors, spam, partners. This is email **noise** / a CRM triage inbox, not a business relationship. | `crm.ingested_domain` | **CRM only.** No other app reads it or FKs to it. |
| **Prospect** | A company we have **not yet done business with** but are tracking and may transact with in the future. CRM/PM care about these; PLM/DAM do not yet. | `core.company` with **no ERP/PLM source ref** | Shared, but it is a `core.company` row like any other. |
| **Customer** | A company we **have actually done business with**. Authoritative source is PLM/ERP (ColdLion). | `core.company` **with** a `designflow_plm` / `coldlion` source ref in `core.company_source_ref` | Shared (CRM, PM, PLM, DAM). |

Key rules:

- **An ingested domain is not a customer and not a company.** It must never be
  written into `core.company` by the email worker. The worker calls
  `crm.record_ingested_domain(...)` instead. Other apps must never join to
  `crm.ingested_domain` — it is a CRM-private table.
- **`core.company` is the shared identity hub**, not "the customer list." It
  holds prospects *and* confirmed customers. Every app FKs here, so it must only
  ever contain real entities — never email noise.
- **PLM/ERP is the system of record for "is this a real customer."** A
  `core.company` is a confirmed customer **iff** it has an ERP source ref. That
  fact is authoritative and factual; the CRM `customer_status` column
  (`ACTIVE_CUSTOMER` / `POTENTIAL_CUSTOMER` / `OTHER` / `UNASSIGNED`) is CRM's
  *subjective* triage opinion and is a different axis.

### Lifecycle: domain → prospect → customer (one identity, never re-pointed)

```txt
crm.ingested_domain (email noise)
   │  crm.promote_ingested_domain()   — CRM decides this is worth tracking
   ▼
core.company  (prospect: no ERP source ref)
   │  plm.import_master_data()        — ERP confirms we transacted with them
   ▼
core.company  (customer: SAME row, now with a designflow_plm source ref)
```

The critical property: **a prospect and the customer it becomes are the same
`core.company` row.** Promotion to customer is a metadata change — attach an ERP
source ref and (optionally) flip a status — **not** a move between tables. So
nothing that already points at the company (opportunities, projects, emails, PLM
items, DAM assets) ever has to be re-pointed.

### Do NOT build a separate "CRM/PM customer" table to union with PLM's

A tempting design is: prospects in their own `crm`/`pim` customer table, ERP
customers in PLM's canonical table, joined by a union view, with a dedupe job
that re-points everything when a prospect graduates into the ERP list. **Don't.**
That recreates the exact pain it tries to avoid: when a prospect becomes a real
customer you must re-point every FK across CRM/PM from the prospect id to the ERP
id, and you can never have a single FK column that means "either table."

Instead, the shared model uses **one hub (`core.company`) + source refs +
entity-resolution on ERP import** — and this is already implemented:
`plm.import_master_data()` (in `20260624173000_plm_master_data_import.sql`), for
each incoming ERP customer:

1. **Already linked?** Look up `core.company_source_ref` for the ERP id → update
   in place.
2. **Not linked → match** against existing `core.company` (today by normalized
   name; should also match on `domain`). A match is almost always a prospect
   CRM/PM already created.
3. **Match found → promote in place:** attach the ERP source ref to that existing
   `core.company`. No FK re-pointing — every existing reference already points at
   this row.
4. **No match → create** a new `core.company` with the ERP source ref.

Refinements still to do on that matcher (tracked as follow-ups, not yet built):
match on `domain` as well as name; consider prospect rows (not just rows already
typed `customer`); and route **ambiguous** matches to `ingest.dedupe_candidate`
for human review instead of silently auto-merging or creating a duplicate. When
PLM's full database lands in this Supabase project, the ERP customer mirror
(`plm.customer_import` today) becomes the authoritative `plm.customer` table and
the same source-ref linkage carries over unchanged.

## Realtime Intention

The desired user experience is cross-app immediacy:

- A CRM opportunity can create or update PM work.
- PM product movement can be visible to CRM account teams.
- DAM asset links can appear on PM product/design screens.
- PLM production/order state can inform PM and CRM views.
- Shared comments, activity, and notifications can reflect work across apps.

That does not mean every table is realtime-enabled. Realtime should be enabled only for user-facing state, with RLS in place first. Worker queues, raw ingest tables, helper tokens, and sensitive PLM/RFQ/cost data should not be broadly streamed to browsers.

## Migration Principle

Move carefully:

1. Build and test schema changes on the Supabase preview branch.
2. Keep existing PopDAM production tables stable while shared schemas are added.
3. Preserve all source ids through source-reference tables.
4. Dedupe canonical objects before hard-linking app data.
5. Switch frontends through `api` views/RPCs or stable table contracts.
6. Promote to production only from committed migrations in this repo.

The first successful milestone is not "all apps rewritten." The first milestone is: the shared schemas exist, PopDAM still works, and CRM/PM can be tested against the preview branch without creating another silo.
