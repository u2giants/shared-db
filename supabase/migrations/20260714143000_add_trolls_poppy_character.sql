-- Add missing PopDAM character taxonomy used by AI tag bake-off.
-- The bake-off can resolve character names only when a canonical character row
-- exists for the property. Trolls assets can identify Poppy visually, but the
-- live public.characters table did not have a Poppy row under the Trolls
-- property.

insert into public.characters (property_id, name, is_priority, usage_count)
select p.id, 'Poppy', false, 0
from public.properties p
where p.name = 'TROLLS FRANCHISE ASSET'
  and not exists (
    select 1
    from public.characters c
    where c.property_id = p.id
      and lower(c.name) = 'poppy'
  );
