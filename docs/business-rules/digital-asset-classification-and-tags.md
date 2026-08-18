# Digital-asset classification, tags, and source evidence

**Status:** Settled where stated; unapproved vocabulary and thresholds remain Proposed.

## Purpose

Tags and classifications help people find and understand source artwork. They must describe supported business facts, retain how those facts were derived, and never silently turn folder noise or AI guesses into official Licensor, Property, Character, or product taxonomy.

## Authority order

- Manual reviewed decisions are preserved until explicitly changed.
- Official Licensor, Property, and Character identities follow Licensing Master Data.
- Exact controlled-taxonomy matches may create deterministic tags.
- Folder paths, filenames, embedded metadata, document text, and image analysis are evidence sources with recorded provenance, not authorities by themselves.
- AI output is a separate suggestion source and may not overwrite manual or deterministic evidence.

## Canonicalization and provenance

Display one canonical tag while retaining aliases and every supporting source. Each accepted or rejected tag keeps its facet, source, evidence, confidence where applicable, rule/model version, actor, and time.

Removing an automatic tag records a rejection; it does not erase evidence. Automatic reruns replace only output from the same source and version. Manual tags survive every automatic rebuild.

## Safety rules

- Never create a Licensor or Property tag merely because a folder occupies a particular path depth.
- Never use fuzzy similarity alone to establish Licensor, Property, or Character identity.
- Never use a sampled `quick_hash` alone to prove file identity or copy tags.
- Never propagate workflow state, language, or color to sibling files by default.
- Do not convert arbitrary frequent document words into tags.
- Store bounded evidence snippets, not complete copyrighted document bodies.
- File moves and renames recalculate path- and filename-derived evidence without destroying unrelated sources.
- Inactive files retain history but do not appear in normal browsing.

## Search and presentation

Search uses canonical names and reviewed aliases. Users must be able to distinguish manual, folder, filename, metadata, document, relationship, and AI sources. A Style Guide must not be described by a tag supported by only one outlier file unless the aggregation rule explicitly says so.

## Unknown or Proposed decisions

Who may create new manual vocabulary, which non-taxonomy facets are official, propagation thresholds, year treatment, and the threshold for AI enrichment remain Proposed until approved. Application plans may test options but must not present them as Settled.

## Implementation and evidence

PopDAM and PopSG implementation plans, including `fix_add_tags.md`, may contain pipelines, thresholds, performance goals, and UI designs. Those are implementation proposals or evidence. This page owns the business rules.
