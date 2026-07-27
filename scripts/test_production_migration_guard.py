#!/usr/bin/env python3

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from production_migration_guard import (  # noqa: E402
    GuardError,
    parse_allowlist,
    parse_remote_versions,
    validate_candidates,
    verify_dry_run,
)


class GuardTests(unittest.TestCase):
    def test_bad_allowlists_are_blocked(self) -> None:
        for value in ("", "20260727", "20260727010000,20260727010000",
                      "20260727020000,20260727010000", "20260726180000",
                      "20260726190000"):
            with self.subTest(value=value), self.assertRaises(GuardError):
                parse_allowlist(value)

    def test_remote_parser_uses_remote_column(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.txt"
            path.write_text(
                " Local          | Remote         | Time\n"
                " 20260727010000 | 20260726010000 | x\n"
                " 20260727020000 |                | x\n",
                encoding="utf-8",
            )
            self.assertEqual(parse_remote_versions(path), {"20260726010000"})

    def test_unknown_and_applied_versions_are_blocked(self) -> None:
        migrations = {"20260727010000": Path("one.sql")}
        with self.assertRaises(GuardError):
            validate_candidates(migrations, ["20260727020000"], set())
        with self.assertRaises(GuardError):
            validate_candidates(
                migrations, ["20260727010000"], {"20260727010000"}
            )

    def test_dry_run_requires_exact_list(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dry.txt"
            path.write_text(
                "Would push these migrations:\n"
                " • 20260727010000_one.sql\n"
                " • 20260727020000_two.sql\n",
                encoding="utf-8",
            )
            with self.assertRaises(GuardError):
                verify_dry_run(path, "20260727010000")
            verify_dry_run(path, "20260727010000,20260727020000")

    def test_dry_run_without_marker_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dry.txt"
            path.write_text("20260727010000_one.sql\n", encoding="utf-8")
            with self.assertRaises(GuardError):
                verify_dry_run(path, "20260727010000")

    def test_general_workflow_has_no_production_apply(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "shared-supabase-migrations.yml"
        ).read_text(encoding="utf-8")
        production = workflow.split("production-dry-run:", 1)[1]
        self.assertIn("Refuse production apply", production)
        self.assertNotIn("run: supabase db push\n", production)


if __name__ == "__main__":
    unittest.main()
