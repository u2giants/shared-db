-- Change DS -> DY and WWE -> WW at their source: the public.licensors rows themselves,
-- replacing the reliance on the hard-coded remap baked into public.dam_character_catalog.
-- Owner ruling 2026-08-07: "Don't hard-code DS to DY, change DS to DY at its source."
--
-- Issue #505. Plan and chain of custody:
--   docs/verification/ds-to-dy-at-source-20260807/README.md
-- Plan facts re-verified against production on 2026-08-29 (read-only); see the
-- issue thread for the delta. The only material change is that the denormalised
-- straggler counts shrank; the shape of the job is unchanged.
--
-- Idempotent. Aborts loudly on any unmet precondition. No object is dropped or replaced.
-- Migration 20260723113000 is applied and is deliberately NOT edited.

set local statement_timeout = '5min';

do $$
declare
  c_disney_legacy constant uuid := '10a445bc-cdb8-4384-ad6f-a46fd029f2bc';
  c_wwe_legacy    constant uuid := '1e3ebfce-7d9d-4424-a68c-73c4e57b6d83';
  c_disney_core   constant uuid := '7d141a6f-e229-46a2-b3f5-0ba0c97dd820';
  c_wwe_core      constant uuid := '7575d1db-dbee-4336-84a9-aa378f05f105';
  v_before        bigint;
  v_after         bigint;
  v_ds_before     bigint;
  v_ds_after      bigint;
  v_sg_ds_before  bigint;
  v_sg_ds_after   bigint;
  v_code          text;
  v_bad           bigint;
  v_n             bigint;
begin
  -- ---------- preconditions ----------
  if not exists (select 1 from public.licensors where id = c_disney_legacy) then
    raise exception 'abort: legacy Disney licensor row % is missing', c_disney_legacy;
  end if;
  if not exists (select 1 from public.licensors where id = c_wwe_legacy) then
    raise exception 'abort: legacy WWE licensor row % is missing', c_wwe_legacy;
  end if;

  select code into v_code from core.licensor where id = c_disney_core;
  if v_code is distinct from 'DY' then
    raise exception 'abort: core.licensor % has code %, expected DY',
      c_disney_core, coalesce(v_code, '<missing>');
  end if;
  select code into v_code from core.licensor where id = c_wwe_core;
  if v_code is distinct from 'WW' then
    raise exception 'abort: core.licensor % has code %, expected WW',
      c_wwe_core, coalesce(v_code, '<missing>');
  end if;

  -- The target codes must be free, or the unique index licensors_external_id_key
  -- would reject the update.
  select count(*) into v_bad
  from public.licensors
  where external_id in ('DY', 'WW')
    and id not in (c_disney_legacy, c_wwe_legacy);
  if v_bad <> 0 then
    raise exception
      'abort: % other public.licensors row(s) already hold DY or WW; unique index would be violated',
      v_bad;
  end if;

  -- THE TRAP (plan section 2.4a). Rows in public.assets / public.style_groups whose
  -- licensor_code is the literal 'DS' are NOT Disney: the letters are a substring of
  -- the item SKU (MCZ6X-DS-PT01, GF152-DS-EN01, VDE83H-DS-UC01, ...). Every one of
  -- them carries licensor_name IS NULL and is_licensed = false. This migration must
  -- not touch them, and must fail if that discriminator ever stops holding.
  select count(*) into v_n
  from public.assets
  where licensor_code = 'DS' and licensor_name is not null;
  if v_n <> 0 then
    raise exception
      'abort: % public.assets row(s) with licensor_code DS carry a licensor_name; the SKU-artifact finding no longer holds, re-verify before proceeding',
      v_n;
  end if;

  select count(*) into v_n
  from public.style_groups
  where licensor_code = 'DS' and licensor_name is not null;
  if v_n <> 0 then
    raise exception
      'abort: % public.style_groups row(s) with licensor_code DS carry a licensor_name; the SKU-artifact finding no longer holds, re-verify before proceeding',
      v_n;
  end if;

  -- Baselines that must survive the change untouched.
  select count(*) into v_before from public.dam_character_catalog;
  select count(*) into v_ds_before from public.assets where licensor_code = 'DS';
  select count(*) into v_sg_ds_before from public.style_groups where licensor_code = 'DS';

  -- ---------- the change (idempotent: re-running matches 0 rows) ----------
  update public.licensors
     set external_id = 'DY', updated_at = now()
   where id = c_disney_legacy and external_id = 'DS';

  update public.licensors
     set external_id = 'WW', updated_at = now()
   where id = c_wwe_legacy and external_id = 'WWE';

  -- Straggler denormalised codes that the 2026-07-23 cutover missed.
  -- licensor_name = 'WWE' is the discriminator that proves these are genuinely WWE
  -- (their SKUs contain 'WW', not 'WWE' -- see AA036WWSU01, CSW1TWWSU01).
  update public.assets
     set licensor_code = 'WW'
   where licensor_code = 'WWE' and licensor_name = 'WWE';

  -- ---------- postconditions ----------
  select external_id into v_code from public.licensors where id = c_disney_legacy;
  if v_code <> 'DY' then
    raise exception 'abort: Disney legacy external_id is % after update, expected DY', v_code;
  end if;
  select external_id into v_code from public.licensors where id = c_wwe_legacy;
  if v_code <> 'WW' then
    raise exception 'abort: WWE legacy external_id is % after update, expected WW', v_code;
  end if;

  -- Every legacy licensor still resolves to exactly one core.licensor under the
  -- view's own join expression. This is the proof that the hard-coded remap in
  -- public.dam_character_catalog degrades to a harmless pass-through.
  select count(*) into v_bad
  from public.licensors l
  where (
    select count(*) from core.licensor c
    where lower(c.code) = lower(
            case l.external_id when 'DS' then 'DY' when 'WWE' then 'WW' else l.external_id end)
       or lower(trim(c.name)) = lower(trim(l.name))
  ) <> 1;
  if v_bad <> 0 then
    raise exception 'abort: % legacy licensor(s) no longer resolve to exactly one core.licensor', v_bad;
  end if;

  select count(*) into v_after from public.dam_character_catalog;
  if v_after <> v_before then
    raise exception 'abort: dam_character_catalog row count changed from % to %', v_before, v_after;
  end if;

  select count(*) into v_n from public.assets where licensor_code = 'WWE';
  if v_n <> 0 then
    raise exception 'abort: % assets still carry licensor_code WWE', v_n;
  end if;

  -- The SKU-artifact rows must be exactly as numerous as before: not zero, unchanged.
  select count(*) into v_ds_after from public.assets where licensor_code = 'DS';
  if v_ds_after <> v_ds_before then
    raise exception
      'abort: public.assets rows with licensor_code DS changed from % to %; these are SKU artifacts and must be untouched',
      v_ds_before, v_ds_after;
  end if;

  select count(*) into v_sg_ds_after from public.style_groups where licensor_code = 'DS';
  if v_sg_ds_after <> v_sg_ds_before then
    raise exception
      'abort: public.style_groups rows with licensor_code DS changed from % to %; these are SKU artifacts and must be untouched',
      v_sg_ds_before, v_sg_ds_after;
  end if;
end $$;

comment on column public.licensors.external_id is
  'Canonical licensor code, aligned to core.licensor.code since 2026-08-07 (owner ruling: change DS to DY at its source). Legacy values DS/WWE were normalised to DY/WW by issue #505. public.dam_character_catalog still carries a defensive DS/WWE remap; it is now a no-op and is deliberately retained as a safety net.';
