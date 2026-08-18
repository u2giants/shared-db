# Merchandise groups and product taxonomy

**Status:** Settled where stated. Historical-description remediation remains governed by its active plan.

## Business hierarchy

Product classification is a real business hierarchy:

1. MG01 Product Type
2. MG02 Product Sub-Type
3. MG03 Product Sub-Sub-Type

Higher merchandise-group numbers describe other business dimensions such as size, licensor, Property, artwork, material, or division. A code from one dimension must not be treated as a substitute for another.

## `mgCategory`

`mgCategory` is a hidden broad grouping of real MG01 Product Types. It is not another MG hierarchy level and does not replace MG01.

| Category | MG01 Product Types |
|---|---|
| Wall | A Stretched/Box; B Framed; C Plaque; D Functional; E Other Wall |
| Tabletop | F Block; G Box; H Photo Frames; J Object; K Other Tabletop |
| Clock | M Clocks |
| Storage | N Soft Storage; P Hard Storage; R Other storage |
| Workspace | S Stationery org; T Desk Acc; U Other workspace |
| Floor | V Floor coverings |
| Garden | W Garden |

That is seven categories covering nineteen MG01 Product Types. Category constrains dependent choices such as valid sizes. A Product Type may not belong to two categories unless the business explicitly changes this rule.

## Description classification

Historical item descriptions must be interpreted into separate facts: Product Type, size, Licensor, Property, and artwork wording. Matching starts with the most specific supported combination and falls back carefully. Failure of a full multi-level match is not evidence that MG01 failed.

Do not infer current product meaning from pre-2025-05-10 single-letter ERP values without the approved historical remediation method. After the cutoff, the current mapping may be used as documented.

## Authority boundary

This taxonomy governs product and merchandise meaning only. Licensing names, ownership, Characters, Style Guides, Assets, Franchises, and Property Active/Inactive status follow [`licensing-master-data.md`](licensing-master-data.md).

## Implementation and evidence

The full schema history, code mappings, workbook evidence, and historical-remediation procedure remain in [`../merch-group-taxonomy-architecture.md`](../merch-group-taxonomy-architecture.md) and [`../item-description-mg-classification-process.md`](../item-description-mg-classification-process.md).
