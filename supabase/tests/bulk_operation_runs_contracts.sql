-- Synthetic append-only history checks; disposable database transaction only.
do $$
declare privilege_name text;
begin
  foreach privilege_name in array array['UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
    if has_table_privilege('service_role','public.bulk_operation_runs',privilege_name) then
      raise exception 'service_role unexpectedly holds % on immutable history', privilege_name;
    end if;
  end loop;
  if not has_table_privilege('service_role','public.bulk_operation_runs','INSERT')
     or not has_table_privilege('service_role','public.bulk_operation_runs','SELECT') then
    raise exception 'worker cannot append and read its history';
  end if;
  if has_table_privilege('anon','public.bulk_operation_runs','SELECT')
     or has_table_privilege('authenticated','public.bulk_operation_runs','INSERT') then
    raise exception 'browser history privileges widened';
  end if;
end $$;
set local role service_role;
insert into public.bulk_operation_runs(operation,run_id,status,error,started_at)
values ('zztest-history','zztest-failed','failed','synthetic failure','2026-01-01T00:00:00Z');
insert into public.bulk_operation_runs(operation,run_id,status,started_at,ended_at)
values ('zztest-history','zztest-success','succeeded','2026-01-02T00:00:00Z','2026-01-02T01:00:00Z');
do $$
begin
  if (select count(*) from public.bulk_operation_runs where operation='zztest-history') <> 2
     or not exists (select 1 from public.bulk_operation_runs where operation='zztest-history' and run_id='zztest-failed' and error='synthetic failure') then
    raise exception 'later success erased earlier failed outcome';
  end if;
  begin
    update public.bulk_operation_runs set error='overwritten' where operation='zztest-history';
    raise exception 'history update was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.bulk_operation_runs where operation='zztest-history';
    raise exception 'history deletion was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.bulk_operation_runs(operation,run_id,status,error,started_at)
    values ('zztest-history','zztest-failed','failed','retry','2026-01-01T00:00:00Z');
    raise exception 'duplicate run was allowed';
  exception when unique_violation then null;
  end;
  begin
    insert into public.bulk_operation_runs(operation,run_id,status,started_at)
    values ('zztest-history','zztest-silent','failed','2026-01-03T00:00:00Z');
    raise exception 'silent failure was allowed';
  exception when check_violation then null;
  end;
end $$;
reset role;
