-- DRILL FIXTURE — NOT A MIGRATION. Never move this under supabase/migrations/.
-- Half B of the deliberate collision: same function, different body, different
-- version. Nothing textual conflicts with half A — that is the whole point.
create or replace function plm.promote_coldlion_source_owned(p_mode text)
returns void language plpgsql as $$
begin
  raise notice 'drill B body';
end;
$$;
