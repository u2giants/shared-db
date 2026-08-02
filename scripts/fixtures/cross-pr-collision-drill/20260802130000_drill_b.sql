-- DRILL FIXTURE — NOT A MIGRATION. Never move this under supabase/migrations/.
-- Half B: the SAME function, a different body, a different version. Nothing
-- conflicts textually with half A — that is precisely the hazard.
create or replace function plm.promote_coldlion_source_owned(p_mode text)
returns void language plpgsql as $$
begin
  raise notice 'drill B body';
end;
$$;
