-- Add licensors present in the PopSG style-guide library but absent from the
-- DesignFlow PLM / ColdLion feed.
--
-- Context: PopSG resolves style_guide_files.licensor_name (a generated column,
-- split_part(relative_path,'/',1)) against core.licensor by name + merch-group
-- code. After switching to core and adding curated aliases, 801 of 216,472
-- active files still had no licensor. 698 of those are these six real brands,
-- which simply never arrive from PLM/ColdLion.
--
--   Miller Coors 283 · Anheuser Busch 187 · NASA 153 · NFL 32 · Ford 22 · NCAA 21
--
-- The remaining 103 are intentionally NOT licensors and are excluded here:
--   Spirit Halloween (98) is a CUSTOMER, CAA (4) is a talent agency whose files
--   are actually Ford's (CAA/Ford/*), and seafile-ignore.txt (1) is another
--   application's canary file, now filtered at crawl time.
--
-- Code choice: core.licensor has UNIQUE NULLS NOT DISTINCT (code), so every row
-- needs a distinct non-null code. PLM merch-group codes are short (AA, WB, 1P),
-- so these use an "X-" namespaced placeholder that a PLM code can never collide
-- with. plm.import_master_data() matches by code first and then by lower(name);
-- because these codes cannot match, a future PLM record for the same brand will
-- match by NAME and update the row in place, adopting the real merch-group code.
-- That makes these rows durable now and self-correcting later.
--
-- Idempotent: skips any brand whose name already exists (case-insensitive).

insert into core.licensor (name, code, status, metadata)
select
  v.name,
  v.code,
  'active'::app.entity_status,
  jsonb_build_object(
    'source', 'manual_popsg_backfill',
    'reason', 'present in PopSG style-guide library, absent from PLM/ColdLion feed',
    'added_migration', '20260723210000'
  )
from (values
  ('Miller Coors',   'X-MILLERCOORS'),
  ('Anheuser Busch', 'X-ANHEUSERBUSCH'),
  ('NASA',           'X-NASA'),
  ('NFL',            'X-NFL'),
  ('Ford',           'X-FORD'),
  ('NCAA',           'X-NCAA')
) as v(name, code)
where not exists (
  select 1 from core.licensor l where lower(l.name) = lower(v.name)
)
and not exists (
  select 1 from core.licensor l where l.code = v.code
);
