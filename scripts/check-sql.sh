#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
migration_dir="$root_dir/supabase/migrations"

required_files=(
  "20260621150714_foundation.sql"
  "20260621150815_app_core.sql"
  "20260621151024_domain_tables.sql"
  "20260621151155_api_rls_realtime.sql"
)

for file in "${required_files[@]}"; do
  test -f "$migration_dir/$file"
done

rg --quiet "create schema if not exists app" "$migration_dir/20260621150714_foundation.sql"
rg --quiet "create table core.company" "$migration_dir/20260621150815_app_core.sql"
rg --quiet "create table pim.product" "$migration_dir/20260621151024_domain_tables.sql"
rg --quiet "create or replace view api.pm_product_board" "$migration_dir/20260621151155_api_rls_realtime.sql"
rg --quiet "enable row level security" "$migration_dir/20260621151155_api_rls_realtime.sql"

latest_postgrest_schema_migration="$(rg -l "pgrst\\.db_schemas" "$migration_dir" | sort | tail -n 1)"
if [[ -z "$latest_postgrest_schema_migration" ]]; then
  echo "No migration configures pgrst.db_schemas." >&2
  exit 1
fi

rg --quiet "public, graphql_public, api, crm, pim, core, app" "$latest_postgrest_schema_migration"

if [[ -n "${DATABASE_URL:-}" ]]; then
  command -v psql >/dev/null
  for file in "${required_files[@]}"; do
    psql "$DATABASE_URL" --set ON_ERROR_STOP=1 --single-transaction --file "$migration_dir/$file"
  done
else
  echo "Static checks passed. Set DATABASE_URL to run migrations against a disposable database."
fi
