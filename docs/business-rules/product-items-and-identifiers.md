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

## Non-inventory items

**Settled - Albert Hazan, 2026-09-07.** Not every row in the Item Master is a
product. Some rows exist only so that a charge, a placeholder, or a consumed
input can be put on an order or a cost record. Those rows are non-inventory
items and must be marked accordingly.

An entry is a non-inventory item when it is any of:

- a **fee or charge** - extra cost, glitter fee, reprint fee, colour corners,
  handling, foil stamp fee, tooling or machine-tool charge, labelling fee,
  sample charge, port charge, repackaging, plate cost, ticketing, discount,
  commission, freight or shipping charge, small-order fee;
- a **raw material or component** consumed into a finished product - lenticular
  material, felt pieces, clear hang tabs, PVC window film. These are physically
  held, but they are inputs, not sellable goods;
- a **sample or test placeholder** that exists to carry a transaction rather
  than to be sold;
- a **digital or downloadable good** that is never stocked.

An entry is an inventory item, and must not be marked non-inventory, when it is
a finished good we sell, **or a store fixture we physically own and hold** -
display racks, rack signage, PDQ units, spinners, brackets, card attachments.
A fixture is not sold, but it is real stock and is counted as such.

The controlling test is whether the entry represents something held and counted
as stock, not whether it is sold. A physical thing we hold is inventory even
when it never reaches a customer; a charge or a consumed input is not inventory
even when it appears on the same order.

## Lifecycle

Stage, lifecycle, next action, owner, blocker, and required evidence are different facts. A single status label must not be made to carry all of them. Every transition that becomes Settled must identify the object, starting and ending state, permitted role, required evidence, next owner, rejection/reversal behavior, and related notifications.

## Implementation and evidence

Application plans and Item Master validation notes may describe screens, endpoints, fields, and proposed transitions. They must link here and to [`product-development-workflow.md`](product-development-workflow.md) instead of becoming separate business authorities.

The ColdLion ERP records assortment membership on the stock record rather than on the item record: an inventory row carrying a prepack code identifies that item as the assortment head, and the prepack manifest lists its member items. The two populations are effectively disjoint. An Item with no stock record carries no assortment evidence either way and must be reported as unconfirmed rather than assumed. The item record itself carries no assortment flag.

The ColdLion ERP carries this distinction as a single-character flag on the item
record, mirrored into our systems as the Item Master's non-inventory field. The
flag is not maintained: as measured on 2026-09-07 only 15 of roughly 19,600 item
records carried it, while at least 35 further entries - including glitter fee,
reprint fee and colour corners - were recorded as ordinary products, and around
4,700 records had the field left blank rather than set either way. A blank or
"not non-inventory" value is therefore evidence of nothing, and this field must
not be used on its own to decide whether a row is a real product until it has
been corrected at source and kept current.
