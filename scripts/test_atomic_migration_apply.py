import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atomic_migration_apply as atomic


class AtomicMigrationApplyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self): self.temp.cleanup()

    def authorize(self, sql="lock table x in exclusive mode;"):
        path = self.root / "29990101000000_test.sql"
        path.write_text(sql, encoding="utf-8")
        policy = {"migrations": {"29990101000000": {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "targets": ["preview"]}}}
        policy_path = self.root / "policy.json"
        policy_path.write_text(json.dumps(policy), encoding="utf-8")
        return path, policy_path

    def test_split_preserves_semicolons_in_quotes_comments_and_dollar_blocks(self):
        sql = "select ';'; -- ;\n do $$ begin perform ';'; end $$; select 2;"
        self.assertEqual(len(atomic.split_sql(sql)), 3)

    def test_exact_hash_and_single_file_are_required(self):
        path, policy = self.authorize()
        with patch.object(atomic, "POLICY", policy):
            loaded = atomic.load_candidate(self.root, "29990101000000", "preview")
            self.assertEqual(loaded[0], path)
            path.write_text("select 2;", encoding="utf-8")
            with self.assertRaisesRegex(atomic.Refusal, "SHA256 mismatch"):
                atomic.load_candidate(self.root, "29990101000000", "preview")

    def test_transaction_controls_are_refused(self):
        _, policy = self.authorize("begin; select 1; commit;")
        with patch.object(atomic, "POLICY", policy):
            with self.assertRaisesRegex(atomic.Refusal, "transaction-control"):
                atomic.load_candidate(self.root, "29990101000000", "preview")

    def test_wrapper_places_sql_and_exact_ledger_row_in_one_transaction(self):
        wrapper = atomic.build_wrapper("29990101000000", "test", "create table x(id int);", ["create table x(id int)"])
        self.assertLess(wrapper.index("BEGIN;"), wrapper.index("create table"))
        self.assertLess(wrapper.index("create table"), wrapper.index("INSERT INTO supabase_migrations.schema_migrations"))
        self.assertLess(wrapper.index("INSERT INTO"), wrapper.index("COMMIT;"))


if __name__ == "__main__": unittest.main()
