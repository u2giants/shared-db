# PopDAM — rich PDF extraction spike (2026-07-09)

## Status

Discovery only. No shared-db migration, table, view, RPC, trigger, RLS policy, or production data change was created in this session.

## What Was Learned

PopDAM currently stores extracted tech-pack/licensing-sheet text in `public.pdf_text_samples`. The existing durable backend behavior uses that text for:

- `sku_files_used` / Style Guide Sources parsing from "Files Used" style sections.
- DAM library full-text search through `search_assets_full_text` and `search_style_groups_full_text`.

It does not yet store a structured rich-metadata record attached to `style_groups` and projected/searchable on all member `assets`.

## Product Need

For new styles going forward, tech-pack and licensing-sheet PDFs should be scraped for relevant style data, attached to the owning style group, available on/searchable through its assets, and then backfilled over existing styles.

## Discovery Sample

On live production project `qsllyeztdwjgirsysgai`, a read-only sample found:

- `125` tech-pack PDFs with extracted text.
- `14` licensing-sheet PDFs with extracted text.

Ten sample PDFs were analyzed with `qwen3.7-plus` through DashScope compatible-mode:

- 5 tech packs.
- 5 licensing sheets.

The model consistently found useful data in these domains:

- source art/file references,
- style-guide reference names,
- designer and technical designer names,
- approval/submission dates,
- dimensions,
- production materials, finishes, hardware, packaging, and construction notes,
- compliance/legal/country-of-origin requirements,
- manufacturer/factory info,
- Pantone/color references,
- retailer program or season values.

The app repo has the session-specific detail in `docs/RICH_PDF_EXTRACTION.md`.

## Shared-DB Implementation Notes

Future implementation must happen in `/worksp/shared-db` on a dedicated branch and migration path. Do not create PopDAM app-repo migrations for this feature.

Likely backend objects to design:

- A source-level table for model outputs per PDF asset, preserving raw extraction provenance, model ID, confidence, and parse errors.
- A style-group rollup table or `jsonb` field for the current canonical rich metadata per `style_group_id`.
- Search support, either by extending existing full-text RPCs or by adding a maintained flattened search field.
- Backfill bookkeeping so existing `pdf_text_samples` can be processed in batches and resumed safely.

Avoid one column per model-suggested synonym. The spike produced overlapping names such as `material_specs`, `production_material`, `production_materials`, `compliance_codes`, `compliance_standards`, and `regulatory_compliance`; these should be normalized into a small structured schema.

## Verification Done

- Queried live production via service-role key from the existing 1Password item `Supabase Runtime Keys - shared POP database (production)`.
- Verified the sampled PDFs came from `pdf_text_samples` joined to `assets`/`style_groups`.
- Verified Qwen 3.7 Plus through the existing `ai-provider-api-keys` DashScope field.
- Confirmed the available OpenRouter key was present in 1Password but blocked for `qwen/qwen3.7-plus` by OpenRouter privacy/data-policy guardrails.

## Risks / Watchouts

- Existing extracted-text coverage is sparse relative to total eligible PDFs; backfill design must include both metadata extraction and missing PDF text extraction.
- Asset-level "attachment" should probably be a projection/search concern, not duplicated mutable metadata on every asset unless there is a measured query need.
- Raw legal/compliance text can be noisy; store provenance and confidence and keep the original raw text in `pdf_text_samples`.
- If production uses DashScope directly, create a clearly-owned production credential path instead of relying on a broad shared test/provider key.
