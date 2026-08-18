# ERP, orders, and source meaning

**Status:** Settled where stated in the source audit.

## General rule

An ERP field name does not establish its business meaning. Every imported field must retain its source, time scope, and interpretation. Applications must not give the same source value different meanings.

## Orders and items

Google OrderList rows and future ColdLion rows describe the same real orders. They are not competing order systems. One canonical order and line must retain separate source references for each system. The ultimate item list belongs to the canonical PLM item identity.

## Historical classification

ERP merchandise data before the approved cutoff may use codes whose historical meaning differs from current codes. Historical items must follow the approved description-based remediation process rather than being forced through the current mapping.

## Samples and production indicators

Contractual-sample, DAVID-sample, cost, production, and order-history fields must retain the exact meanings established by the source audit. A source value that is absent or ambiguous must remain Unknown rather than being silently converted to zero, false, or not applicable.

## Implementation and evidence

The field-by-field source evidence and formula findings remain in [`../business-rules-erp-data.md`](../business-rules-erp-data.md), [`../app-migration-notes/popdam-order-list.md`](../app-migration-notes/popdam-order-list.md), and the linked formula audit. This page is the companywide entry point.
