-- DRILL FIXTURE — NOT A MIGRATION. Never move this under supabase/migrations/.
-- The innocent third party: a DIFFERENT object. The guard must NOT fire on it.
create or replace view api.drill_unrelated_view as select 1 as one;
