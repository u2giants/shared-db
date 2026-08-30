-- Issue #1883: presence-only Disney OPA entity lifecycle. No source rows are included.

alter table plm.opa_property
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add constraint opa_property_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint opa_property_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

alter table plm.opa_character
  add column status text not null default 'active',
  add column withdrawn_at timestamptz,
  add constraint opa_character_lifecycle_status_chk
    check (status in ('active', 'withdrawn')),
  add constraint opa_character_withdrawn_at_chk
    check ((status = 'withdrawn') = (withdrawn_at is not null));

comment on column plm.opa_property.status is
  'Presence lifecycle only: active or withdrawn. This does not describe canonical resolution.';
comment on column plm.opa_property.withdrawn_at is
  'First source-capture time at which this property was confirmed absent; retained on withdrawal.';
comment on column plm.opa_character.status is
  'Presence lifecycle only: active or withdrawn. This does not describe canonical resolution.';
comment on column plm.opa_character.withdrawn_at is
  'First source-capture time at which this character was confirmed absent; retained on withdrawal.';

do $verify$
declare
  v_table text;
  v_columns integer;
  v_checks integer;
begin
  foreach v_table in array array['opa_property', 'opa_character'] loop
    select count(*) into v_columns
    from pg_catalog.pg_attribute
    where attrelid = format('plm.%I', v_table)::regclass
      and attname in ('status', 'withdrawn_at')
      and not attisdropped;

    if v_columns <> 2 then
      raise exception 'verify: %.% lifecycle columns are incomplete', 'plm', v_table;
    end if;

    select count(*) into v_checks
    from pg_catalog.pg_constraint
    where conrelid = format('plm.%I', v_table)::regclass
      and contype = 'c'
      and convalidated
      and conname in (
        v_table || '_lifecycle_status_chk',
        v_table || '_withdrawn_at_chk'
      );

    if v_checks <> 2 then
      raise exception 'verify: %.% lifecycle constraints are incomplete', 'plm', v_table;
    end if;

    if exists (
      select 1
      from pg_catalog.pg_attribute a
      left join pg_catalog.pg_attrdef ad
        on ad.adrelid = a.attrelid and ad.adnum = a.attnum
      where a.attrelid = format('plm.%I', v_table)::regclass
        and a.attname = 'status'
        and (a.attnotnull is false or pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) <> '''active''::text')
    ) then
      raise exception 'verify: %.% status default or nullability is wrong', 'plm', v_table;
    end if;
  end loop;
end
$verify$;
