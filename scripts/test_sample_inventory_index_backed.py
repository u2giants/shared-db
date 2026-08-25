import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MIGRATION = ROOT / "supabase/migrations/20260825224248_sample_inventory_index_backed.sql"
SQL = MIGRATION.read_text(encoding="utf-8")


class SampleInventoryIndexBackedContract(unittest.TestCase):
    def test_single_transaction(self):
        self.assertEqual(len(re.findall(r"(?im)^BEGIN;$", SQL)), 1)
        self.assertEqual(len(re.findall(r"(?im)^COMMIT;$", SQL)), 1)

    def test_exact_structural_scope(self):
        self.assertIn("CREATE OR REPLACE VIEW dflow.sample_inventory", SQL)
        self.assertEqual(SQL.count("CREATE INDEX IF NOT EXISTS"), 2)
        self.assertNotRegex(SQL, r"(?i)\b(?:CREATE|ALTER|DROP)\s+TABLE\b")
        self.assertNotRegex(SQL, r"(?i)\b(?:INSERT|UPDATE|DELETE|TRUNCATE)\b")

    def test_removes_or_self_join(self):
        view_sql = SQL.split("CREATE OR REPLACE VIEW", 1)[1]
        self.assertIn("UNION ALL", view_sql)
        self.assertNotRegex(view_sql, r"(?i)JOIN\s+dflow\.sample_movement")
        self.assertNotRegex(view_sql, r"(?i)\)\s+OR\s+\(")

    def test_normalized_indexes_match_both_legs(self):
        for side in ("destination", "source"):
            self.assertIn(f"sample_movement_inventory_{side}_normalized_idx", SQL)
        for column in ("to_location_type", "to_location_id", "from_location_type", "from_location_id"):
            self.assertIn(column, SQL)
        for value in ("nyc_office_inventory", "ningbo_office_inventory", "'nyc'", "'ningbo'"):
            self.assertIn(value, SQL)

    def test_preserves_inventory_contract_and_privileges(self):
        for column in (
            "sample_id_fk", "location_type", "product_location_type",
            "product_location_id", "quantity", "available_since", "is_boxed",
            "is_in_transit", "is_eligible", "ineligibility_reason",
        ):
            self.assertIn(column, SQL)
        self.assertIn("REVOKE ALL ON dflow.sample_inventory FROM anon, authenticated", SQL)
        self.assertIn("has_table_privilege('anon'", SQL)
        self.assertIn("has_table_privilege('authenticated'", SQL)


if __name__ == "__main__":
    unittest.main()
