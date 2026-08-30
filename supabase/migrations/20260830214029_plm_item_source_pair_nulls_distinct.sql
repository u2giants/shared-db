-- Issue #652: source-less canonical items must not collide with each other.
--
-- The original constraint treated (NULL, NULL) as one shared identity, so the
-- whole table could contain only one item without an external source pair.
-- Preserve uniqueness for real source identities while restoring standard
-- NULLS DISTINCT behavior for items that do not have one yet.
-- derived-from: 20260621151024

begin;

do $$
declare
  v_constraint_name text;
  v_nulls_not_distinct boolean;
begin
  select c.conname, i.indnullsnotdistinct
    into v_constraint_name, v_nulls_not_distinct
  from pg_constraint c
  join pg_index i on i.indexrelid = c.conindid
  where c.conrelid = 'plm.item'::regclass
    and c.contype = 'u'
    and (
      select array_agg(a.attname::text order by a.attname)
      from unnest(c.conkey) key_column
      join pg_attribute a
        on a.attrelid = c.conrelid
       and a.attnum = key_column
    ) = array['source_id', 'source_system']
  limit 1;

  if v_constraint_name is null then
    raise exception
      'expected a unique constraint on plm.item(source_system, source_id); refusing an unverified repair';
  end if;

  if v_nulls_not_distinct then
    execute format('alter table plm.item drop constraint %I', v_constraint_name);
    execute format(
      'alter table plm.item add constraint %I unique nulls distinct (source_system, source_id)',
      v_constraint_name);
  end if;

  execute format(
    'comment on constraint %I on plm.item is %L',
    v_constraint_name,
    'NULLS DISTINCT since 20260830214029: multiple items may lack an external identity, while each non-null source_system/source_id pair remains unique.');
end;
$$;

commit;
