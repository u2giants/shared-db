-- Expose the shared app schema to PostgREST.
--
-- PM/PIM and CRM browser clients read shared support tables in app.* for
-- profiles, comments, activity, notifications, and generic app records. A prior
-- migration exposed api/crm/pim/core but missed app, which made valid browser
-- requests fail with "Invalid schema: app" before RLS could run.

do $$
begin
  execute 'alter role authenticator set pgrst.db_schemas = '
    || quote_literal('public, graphql_public, api, crm, pim, core, app');
end $$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
