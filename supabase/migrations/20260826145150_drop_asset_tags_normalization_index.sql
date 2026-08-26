-- Issue #1467: retire the temporary normalization accelerator after #1427.
-- Both preview and production ledgers contain prerequisite 20260825041343 and
-- final activation 20260825082910, so the partial-index predicate can no longer
-- match a valid public.asset_tags row.

drop index if exists public.asset_tags_pending_metadata_normalization_idx;
