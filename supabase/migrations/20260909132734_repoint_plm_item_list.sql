-- Issue #2466: repoint the stable 21-column item-list contract from the frozen
-- DesignFlow mirror to canonical ColdLion-backed plm.item rows.
-- derived-from: 20260715193000
--
-- The ColdLion detail landing is intentionally closed to application roles. The
-- serving view is therefore a barrier/definer view: authenticated callers see
-- only this explicit projection, not the closed landing rows themselves.

create or replace view api.plm_item_list
with (security_invoker = false, security_barrier = true) as
select
  i.id,
  i.item_number                                           as source_id,
  i.item_number                                           as style_number,
  i.description                                           as item_description,
  i.raw ->> 'mGCategory'                                  as mg_category,
  i.raw ->> 'merchGroup01'                                as mg01_code,
  i.raw ->> 'merchGroup02'                                as mg02_code,
  i.raw ->> 'merchGroup03'                                as mg03_code,
  i.raw ->> 'merchGroup04'                                as mg04_code,
  i.raw ->> 'merchGroup05'                                as mg05_code,
  i.raw ->> 'merchGroup06'                                as mg06_code,
  i.raw ->> 'sizeRangeCode'                               as size_code,
  licensor.code                                           as licensor_code,
  property.code                                           as property_code,
  i.raw ->> 'divisionCode'                                as division_code,
  prepacks.prepack_code,
  prepacks.prepack_codes,
  coalesce(legacy.dismissed, false)                       as dismissed,
  nullif(i.raw ->> 'modTime', '')::timestamptz            as erp_updated_at,
  i.updated_at                                            as synced_at,
  i.source_system
from plm.item i
left join core.licensor licensor on licensor.id = i.licensor_id
left join core.property property on property.id = i.property_id
left join public.erp_items_current legacy
  on legacy.external_id = i.item_number
left join lateral (
  select
    min(btrim(detail.pre_pack_code)) as prepack_code,
    to_jsonb(
      array_agg(distinct btrim(detail.pre_pack_code) order by btrim(detail.pre_pack_code))
    ) as prepack_codes
  from coldlion.item_detail detail
  where detail.company_code = i.raw ->> 'companyCode'
    and detail.division_code = i.raw ->> 'divisionCode'
    and detail.item_no = i.item_number
    and nullif(btrim(detail.pre_pack_code), '') is not null
) prepacks on true
where i.source_system = 'coldlion';

comment on view api.plm_item_list is
  'Canonical ColdLion-backed item list over plm.item. The 21-column Phase 1 contract is preserved. '
  'ColdLion modification time remains distinct from the Supabase sync time; canonical attribution '
  'stays null when unresolved; direct item-detail prepacks are aggregated; frozen PopDAM dismissed '
  'state is retained until issue #2482 gives it a canonical application-owned home.';

grant select on api.plm_item_list to authenticated;
