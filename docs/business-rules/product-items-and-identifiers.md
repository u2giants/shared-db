# Products, items, SKUs, and identifiers

**Status:** Proposed

## Identity

A Product or Item is the business object. A SKU, style number, ERP item number, and application row ID are identifiers for that object; none should be confused with the object itself. Separate source references must be retained when multiple systems describe the same Item.

Designs and creative concepts remain business assets even when no buyer selects them. Approved but unsold concepts and unpicked designs must remain findable and reusable rather than disappearing inside an old project.

## Style numbers

A ColdLion style number is required only when a user requests ColdLion numbering. Draft or earlier-stage Items may exist without one. When supplied, each merchandise-group component used to request the number must exist and be active.

A failure to obtain a ColdLion style number must not destroy the Item or silently invent a number.

## Classification and descriptions

Product classification follows [`merchandise-and-product-taxonomy.md`](merchandise-and-product-taxonomy.md). A controlled description keeps Product Type, subtype, Licensor, Property, artwork wording, and size as separate facts even when presented as one readable description.

## Prepacks and assortments

**Settled — Albert Hazan, 2026-09-06.** A prepack is not an Item. It is a manifest of the Items packed in a carton. An Item in the creative systems will never map to a prepack, so prepacks belong to the transactional ERP domain and are out of scope for creative Master Data work. Prepacks must be excluded from any population being assessed for missing Licensor or Property, not chased for attribution.

An assortment head and a prepack member are different business objects. The assortment head is the orderable carton and legitimately carries no single Licensor or Property, because it mixes several. The member is a real single-property Item and must carry its own Licensor and Property. Reporting an assortment head as an Item with missing Licensor data is a false defect.

Assortment membership is the controlling test, not the shape of the style number. Style-number length and format correlate with assortment status but misclassify in both directions and must not be used as the rule.

## Lifecycle

Stage, lifecycle, next action, owner, blocker, and required evidence are different facts. A single status label must not be made to carry all of them. Every transition that becomes Settled must identify the object, starting and ending state, permitted role, required evidence, next owner, rejection/reversal behavior, and related notifications.

## Implementation and evidence

Application plans and Item Master validation notes may describe screens, endpoints, fields, and proposed transitions. They must link here and to [`product-development-workflow.md`](product-development-workflow.md) instead of becoming separate business authorities.

The ColdLion ERP records assortment membership on the stock record rather than on the item record: an inventory row carrying a prepack code identifies that item as the assortment head, and the prepack manifest lists its member items. The two populations are effectively disjoint. An Item with no stock record carries no assortment evidence either way and must be reported as unconfirmed rather than assumed. The item record itself carries no assortment flag.
