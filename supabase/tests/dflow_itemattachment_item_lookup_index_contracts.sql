-- Contracts for 20260826144841_dflow_itemattachment_item_lookup_index.sql.

do $contracts$
declare
  v_is_valid boolean;
  v_is_ready boolean;
  v_is_unconditional boolean;
  v_key_columns smallint;
  v_total_columns smallint;
  v_first_column text;
  v_plan_line text;
  v_plan text := '';
begin
  select i.indisvalid,
         i.indisready,
         i.indpred is null,
         i.indnkeyatts,
         i.indnatts,
         a.attname
    into v_is_valid,
         v_is_ready,
         v_is_unconditional,
         v_key_columns,
         v_total_columns,
         v_first_column
  from pg_index i
  join pg_attribute a
    on a.attrelid = i.indrelid
   and a.attnum = i.indkey[0]
  where i.indexrelid = 'dflow.itemattachment_item_num_id_fk_idx'::regclass;

  if v_is_valid is distinct from true or v_is_ready is distinct from true then
    raise exception 'Item attachment lookup index is not valid and ready';
  end if;

  if v_is_unconditional is distinct from true
     or v_key_columns <> 1
     or v_total_columns <> 1
     or v_first_column <> 'item_num_id_fk' then
    raise exception
      'Item attachment lookup index must be one unconditional key on item_num_id_fk';
  end if;

  perform set_config('enable_seqscan', 'off', true);
  for v_plan_line in
    execute $explain$
      explain (costs off)
      select item_num_id_fk, attachment_display_name
      from dflow."itemattachment"
      where item_num_id_fk = any (array[101, 202, 303]::integer[])
      order by item_num_id_fk, attachment_display_name
    $explain$
  loop
    v_plan := v_plan || v_plan_line || E'\n';
  end loop;

  if position('itemattachment_item_num_id_fk_idx' in v_plan) = 0 then
    raise exception 'Item attachment page lookup does not use its index: %', v_plan;
  end if;
end
$contracts$;
