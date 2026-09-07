-- Issue #2356 behavioural contracts for canonical Asset freshness/current state.
-- Synthetic rows are rolled back; no Asset data survives this test.

begin;

do $contracts$
declare
  v_suffix text := to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS')
    || substr(md5(random()::text), 1, 6);
  v_asset uuid;
  v_first timestamptz;
  v_last timestamptz;
  v_raised boolean;
  v_name text;
begin
  -- The freshness facts exist, while current remains the single predicate
  -- missing_since is null rather than a drift-prone stored boolean.
  foreach v_name in array array['first_seen_at', 'last_seen_at', 'missing_since'] loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'dam'
        and table_name = 'asset'
        and column_name = v_name
        and data_type = 'timestamp with time zone'
    ) then
      raise exception '#2356: dam.asset.% is absent or has the wrong type', v_name;
    end if;
  end loop;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'dam'
      and table_name = 'asset'
      and column_name = 'is_current'
  ) then
    raise exception '#2356: dam.asset.is_current duplicates missing_since and can drift';
  end if;

  -- The established canonical identity is unchanged. This exact constraint is
  -- still the conflict target for callers using (source_system, source_id).
  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'dam.asset'::regclass
      and c.contype = 'u'
      and (
        select array_agg(a.attname::text order by a.attname)
        from unnest(c.conkey) k
        join pg_attribute a
          on a.attrelid = c.conrelid
         and a.attnum = k
      ) = array['source_id', 'source_system']
  ) then
    raise exception '#2356: UNIQUE (source_system, source_id) was removed or changed';
  end if;

  -- Existing lookup indexes remain in place.
  foreach v_name in array array['dam_asset_style_group_idx', 'dam_asset_sku_idx'] loop
    if to_regclass('dam.' || v_name) is null then
      raise exception '#2356: existing index dam.% was removed', v_name;
    end if;
  end loop;

  -- Scalar compatibility fields survive with their original nullable UUID shape.
  foreach v_name in array array['licensor_id', 'property_id'] loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'dam'
        and table_name = 'asset'
        and column_name = v_name
        and data_type = 'uuid'
        and is_nullable = 'YES'
    ) then
      raise exception '#2356: compatibility column dam.asset.% changed shape', v_name;
    end if;
  end loop;

  -- New callers get complete first/last-seen facts without supplying them.
  insert into dam.asset (title, source_system, source_id)
  values ('ZZ #2356 Asset ' || v_suffix, 'zz_2356_a', 'asset-' || v_suffix)
  returning id, first_seen_at, last_seen_at into v_asset, v_first, v_last;

  if v_first is null or v_last is null or v_last < v_first then
    raise exception '#2356: new Asset did not receive ordered freshness defaults';
  end if;

  if not (select missing_since is null from dam.asset where id = v_asset) then
    raise exception '#2356: new Asset is not current';
  end if;

  -- Recording absence and a later sighting changes only lifecycle facts; source
  -- identity stays byte-for-byte stable.
  update dam.asset
     set missing_since = v_last + interval '1 second'
   where id = v_asset;

  if (select missing_since is null from dam.asset where id = v_asset) then
    raise exception '#2356: missing Asset still reads as current';
  end if;

  update dam.asset
     set last_seen_at = v_last + interval '2 seconds',
         missing_since = null
   where id = v_asset;

  if not exists (
    select 1
    from dam.asset
    where id = v_asset
      and source_system = 'zz_2356_a'
      and source_id = 'asset-' || v_suffix
      and missing_since is null
      and last_seen_at = v_last + interval '2 seconds'
  ) then
    raise exception '#2356: freshness/current-state update altered source identity';
  end if;

  -- The original source key remains collision-proof, while another fully distinct
  -- source namespace may legitimately reuse the same source-local id.
  v_raised := false;
  begin
    insert into dam.asset (title, source_system, source_id)
    values ('ZZ #2356 duplicate', 'zz_2356_a', 'asset-' || v_suffix);
  exception when unique_violation then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2356: duplicate (source_system, source_id) was accepted';
  end if;

  insert into dam.asset (title, source_system, source_id)
  values ('ZZ #2356 distinct source', 'zz_2356_b', 'asset-' || v_suffix);

  -- Impossible lifecycle orderings fail without touching the source key.
  v_raised := false;
  begin
    update dam.asset
       set last_seen_at = first_seen_at - interval '1 second'
     where id = v_asset;
  exception when check_violation then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2356: last_seen_at before first_seen_at was accepted';
  end if;

  v_raised := false;
  begin
    update dam.asset
       set missing_since = first_seen_at - interval '1 second'
     where id = v_asset;
  exception when check_violation then
    v_raised := true;
  end;
  if not v_raised then
    raise exception '#2356: missing_since before first_seen_at was accepted';
  end if;

  -- Existing bridge cardinality stays many-to-many: no constraint makes asset_id
  -- unique by itself on any canonical Asset relationship bridge.
  foreach v_name in array array['asset_property', 'asset_style_guide', 'asset_franchise'] loop
    if exists (
      select 1
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid
       and a.attnum = any(c.conkey)
      where c.conrelid = ('dam.' || v_name)::regclass
        and c.contype in ('p', 'u')
      group by c.oid
      having array_agg(a.attname::text order by a.attname) = array['asset_id']
    ) then
      raise exception '#2356: dam.% incorrectly limits one relationship per Asset', v_name;
    end if;
  end loop;
end
$contracts$;

rollback;
