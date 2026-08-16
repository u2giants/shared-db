"""Disposable PostgreSQL proofs for the exceptional atomic migration path."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atomic_migration_apply as atomic


@unittest.skipUnless(os.environ.get("ATOMIC_MIGRATION_POSTGRES_TEST") == "1", "disposable PostgreSQL only")
class AtomicMigrationPostgresTests(unittest.TestCase):
    def psql(self, sql, ok=True):
        result = subprocess.run(["psql", "-X", "-v", "ON_ERROR_STOP=1", "-At"], input=sql, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def setUp(self):
        self.psql("drop schema if exists atomic_test cascade; create schema atomic_test; create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations(version varchar primary key, statements text[], name text); delete from supabase_migrations.schema_migrations where version like '299902%';")

    def test_success_commits_ddl_and_ledger_and_rerun_refuses(self):
        wrapper = atomic.build_wrapper("29990201000001", "success", "create table atomic_test.success(id int);", ["create table atomic_test.success(id int)"])
        self.psql(wrapper)
        out = self.psql("select (to_regclass('atomic_test.success') is not null)::int||'|'||count(*) from supabase_migrations.schema_migrations where version='29990201000001';").stdout.strip()
        self.assertEqual(out, "1|1")
        self.psql(wrapper, ok=False)
        self.assertEqual(self.psql("select count(*) from supabase_migrations.schema_migrations where version='29990201000001';").stdout.strip(), "1")

    def test_forced_ledger_failure_rolls_back_ddl(self):
        self.psql("create function atomic_test.block_ledger() returns trigger language plpgsql as $$begin if new.version='29990201000002' then raise exception 'blocked'; end if; return new; end$$; create trigger block_atomic before insert on supabase_migrations.schema_migrations for each row execute function atomic_test.block_ledger();")
        wrapper = atomic.build_wrapper("29990201000002", "ledger_fail", "create table atomic_test.ledger_fail(id int);", ["create table atomic_test.ledger_fail(id int)"])
        self.psql(wrapper, ok=False)
        self.assertEqual(self.psql("select (to_regclass('atomic_test.ledger_fail') is null)::int||'|'||count(*) from supabase_migrations.schema_migrations where version='29990201000002';").stdout.strip(), "1|0")

    def test_forced_ddl_failure_adds_no_ledger(self):
        wrapper = atomic.build_wrapper("29990201000003", "ddl_fail", "create table atomic_test.ddl_fail(id definitely_not_a_type);", ["create table atomic_test.ddl_fail(id definitely_not_a_type)"])
        self.psql(wrapper, ok=False)
        self.assertEqual(self.psql("select count(*) from supabase_migrations.schema_migrations where version='29990201000003';").stdout.strip(), "0")


if __name__ == "__main__": unittest.main()
