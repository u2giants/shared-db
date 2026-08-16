from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from post_batch_app_verification import RETIRED_VERSION_REASONS, RETIRED_VERSIONS
from production_migration_guard import HARD_BLOCKED


UNSAFE = ROOT / "supabase/migrations/20260816045130_popdam_orderlist_item_bridge_additive_cutover.sql"
SAFE = ROOT / "supabase/migrations/20260816110750_popdam_orderlist_item_bridge_safe_forward.sql"


def executable_body(sql: str) -> str:
    start = sql.index("lock table plm.style_tracker_item_bridge")
    return sql[start:].removesuffix("\n\ncommit;\n").removesuffix("\ncommit;\n").rstrip()


class SafeForwardTests(unittest.TestCase):
    def test_preserves_exact_database_body_without_transaction_control(self):
        unsafe = UNSAFE.read_text(encoding="utf-8")
        safe = SAFE.read_text(encoding="utf-8")
        self.assertEqual(executable_body(safe), executable_body(unsafe))
        self.assertIn("\nbegin;\n", unsafe.lower())
        self.assertTrue(unsafe.rstrip().lower().endswith("commit;"))
        self.assertTrue(safe.lstrip().lower().splitlines()[0].startswith("--"))
        self.assertNotIn("\nbegin;\n", safe.lower())
        self.assertFalse(safe.rstrip().lower().endswith("commit;"))

    def test_unsafe_version_is_retired_and_hard_blocked_with_exact_reason(self):
        reason = RETIRED_VERSION_REASONS["20260816045130"]
        self.assertIn(
            "explicit COMMIT separates DDL from the Supabase migration ledger",
            reason,
        )
        self.assertIn("never apply production", reason)
        self.assertIn("20260816045130", RETIRED_VERSIONS)
        self.assertIn("20260816045130", HARD_BLOCKED)

    def test_safe_replacement_is_not_retired_or_blocked(self):
        self.assertNotIn("20260816110750", RETIRED_VERSIONS)
        self.assertNotIn("20260816110750", HARD_BLOCKED)


if __name__ == "__main__":
    unittest.main(verbosity=2)
