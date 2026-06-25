<!--
DRAFT to insert into popcrm-web `docs/architecture.md`, immediately after the
"## Data loading" section (before "## Key modules"). popcrm-web is an app repo,
so this commits straight to main once approved. Do NOT edit popcrm-web's
vendored `shared-db/` folder — that is auto-synced from u2giants/shared-db.
-->

## Data model: company vs. customer vs. ingested domain

The CRM works with three different things that are easy to conflate. They are
**not** the same and they do not live in the same place.

| Concept | What it is | Storage | Visible to other apps? |
|---|---|---|---|
| **Ingested domain** | A domain that merely appeared in an ingested email. We get email from ~1000 kinds of companies (recruiters, vendors, spam, partners) — this is the triage **inbox**, not a relationship. | `crm.ingested_domain` (CRM-private) | No. Only the CRM sees it. |
| **Prospect** | A company we have **not yet done business with** but are tracking. | `core.company` with no ERP source ref | Yes — it is a normal `core.company` row. |
| **Customer** | A company we **have actually done business with**. Authoritative source is PLM/ERP (ColdLion). | `core.company` **with** a `designflow_plm`/`coldlion` source ref | Yes (shared by CRM/PM/PLM/DAM). |

Why this matters for the frontend:

- `core.company` is the **shared identity hub** that PM, PLM, and DAM also join
  to. It must only ever hold real accounts (prospects + customers). Email noise
  must never land there. The Fireflies/email worker records noise via
  `crm.record_ingested_domain(...)`, never by inserting into `core.company`.
- The **Accounts → Triage** tab is the human review queue. "New Companies" there
  are ingested domains awaiting a decision; promoting one calls
  `crm.promote_ingested_domain(...)`, which creates the shared `core.company`
  account. Reads for that queue come from `api.crm_ingested_domain_list`;
  curated accounts still come from `api.crm_account_list`.
- `customer_status` (`ACTIVE_CUSTOMER` / `POTENTIAL_CUSTOMER` / `OTHER` /
  `UNASSIGNED`) is the CRM's **subjective** triage opinion. It is a *different
  axis* from the factual "is this a real customer," which is owned by PLM/ERP and
  expressed as the presence of an ERP source ref. Do not treat `customer_status`
  as the source of truth for "have we done business with them."

Lifecycle (one identity, never re-pointed):

```txt
crm.ingested_domain  ──promote──▶  core.company (prospect)  ──ERP import──▶  core.company (customer, same row)
```

A prospect and the customer it becomes are the **same** `core.company` row, so
opportunities/contacts/programs attached in the CRM never need to be moved when
the company graduates into the PLM/ERP customer list. The canonical rationale and
the cross-app rules live in `shared-db/docs/shared-database-vision.md` →
"Company vs. Customer vs. Ingested Domain".
