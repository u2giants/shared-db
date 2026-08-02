-- DRILL FIXTURE — NOT A MIGRATION. Never move this under supabase/migrations/.
-- Half A of the deliberate collision used to prove the B6 guard fires.
create or replace function plm.promote_coldlion_source_owned(p_mode text)
returns void language plpgsql as $$
begin
  raise notice 'drill A body';
end;
$$;
