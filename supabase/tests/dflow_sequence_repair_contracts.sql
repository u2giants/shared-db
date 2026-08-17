-- Synthetic and live contracts for issue #764. All fixtures are temporary.
begin;

do $$
declare
  v_next bigint;
begin
  if (
    select pg_get_expr(d.adbin, d.adrelid)
    from pg_attrdef d
    join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'dflow."LicensingTime"'::regclass and a.attname = 'id'
  ) is distinct from 'nextval(''dflow."LicensingTime_id_seq"''::regclass)' then
    raise exception 'LicensingTime.id is not backed by its expected sequence';
  end if;

  if (
    select pg_get_expr(d.adbin, d.adrelid)
    from pg_attrdef d
    join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'dflow.properties_and_characters'::regclass and a.attname = 'id'
  ) is distinct from 'nextval(''dflow.properties_and_characters_id_seq''::regclass)' then
    raise exception 'properties_and_characters.id is not backed by its expected sequence';
  end if;

  if not (
    select is_called
       and last_value >= coalesce((select max(id) from dflow."LicensingTime"), 1)
    from dflow."LicensingTime_id_seq"
  ) then
    raise exception 'LicensingTime sequence remains behind its table';
  end if;

  if not (
    select is_called
       and last_value >= coalesce((select max(id) from dflow.properties_and_characters), 1)
    from dflow.properties_and_characters_id_seq
  ) then
    raise exception 'properties_and_characters sequence remains behind its table';
  end if;

  create temporary sequence issue_764_sequence start with 1;
  create temporary table issue_764_rows (
    id integer default nextval('issue_764_sequence') primary key
  );

  insert into issue_764_rows(id) values (10458);

  perform setval(
    'issue_764_sequence'::regclass,
    greatest(
      coalesce((select max(id)::bigint from issue_764_rows), 1),
      (select last_value from issue_764_sequence)
    ),
    true
  );

  insert into issue_764_rows default values returning id into v_next;
  if v_next <> 10459 then
    raise exception 'synthetic stale sequence repair returned %, expected 10459', v_next;
  end if;
end;
$$;

rollback;
