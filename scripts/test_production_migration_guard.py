#!/usr/bin/env python3

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from production_migration_guard import (  # noqa: E402
    HARD_BLOCKED,
    UNBLOCKED_20260804,
    GuardError,
    local_migrations,
    parse_allowlist,
    parse_remote_versions,
    preflight_batch,
    prepare,
    validate_candidates,
    verify_dry_run,
)

REPO = Path(__file__).resolve().parents[1]

# The exact ordered ColdLion promotion batch, named by 14-digit version.
# 14-file ordering: the one that ABORTS at file 3 (20260727221500) with 42P01.
BATCH_14 = [
    "20260724060000",
    "20260724061000",
    "20260727221500",
    "20260727223000",
    "20260727224500",
    "20260728134500",
    "20260729230000",
    "20260729234500",
    "20260729235500",
    "20260730000500",
    "20260731163000",
    "20260731180000",
    "20260731190000",
    "20260731200000",
]
# 18-file ordering: the four unblocked 2026-08-04 inserted at positions 3-6,
# ahead of 20260727221500 (position 7) and 20260728134500 (position 10).
BATCH_18 = sorted(BATCH_14 + sorted(UNBLOCKED_20260804))

# The 27 versions pending on production at the 2026-08-02 lane design
# (docs/production-migration-lane-design-20260802.md sections 1.1 and 4):
# the 18 ColdLion above plus 9 unrelated. Used to reconstruct production's
# ledger offline; the reconstruction is self-checked against the recorded
# production row count of 359, so a stale constant fails loudly.
PENDING_9_UNRELATED = [
    "20260727230000",
    "20260728171500",
    "20260728174500",
    "20260728181500",
    "20260729120000",
    "20260731150000",
    "20260731153000",
    "20260731210000",
    "20260731220000",
]
PRODUCTION_LEDGER_HEAD = "20260731230000"
PRODUCTION_LEDGER_ROWS = 359


def production_ledger_versions() -> set[str]:
    pending = set(BATCH_18) | set(PENDING_9_UNRELATED)
    versions = {
        version
        for version in local_migrations(REPO)
        if version <= PRODUCTION_LEDGER_HEAD and version not in pending
    }
    if len(versions) != PRODUCTION_LEDGER_ROWS:
        raise AssertionError(
            f"reconstructed production ledger has {len(versions)} rows, "
            f"expected {PRODUCTION_LEDGER_ROWS}"
        )
    return versions


def write_migrations(root: Path, files: dict[str, str]) -> Path:
    directory = root / "supabase" / "migrations"
    directory.mkdir(parents=True, exist_ok=True)
    for name, body in files.items():
        (directory / name).write_text(body, encoding="utf-8")
    return root


class GuardTests(unittest.TestCase):
    def test_bad_allowlists_are_blocked(self) -> None:
        values = [
            "",
            "20260727",
            "20260727010000,20260727010000",
            "20260727020000,20260727010000",
            # The Master Data pair stays HARD_BLOCKED permanently: already
            # applied to production, listed so the known lockdown mistake
            # (AGENTS.md section 0.4) can never be re-run.
            "20260726190000",
            "20260726200000",
        ]
        for value in values:
            with self.subTest(value=value), self.assertRaises(GuardError):
                parse_allowlist(value)

    def test_master_data_pair_is_the_whole_block_list(self) -> None:
        self.assertEqual(HARD_BLOCKED, {"20260726190000", "20260726200000"})

    def test_the_four_coldlion_versions_are_unblocked(self) -> None:
        # Owner ruling 2026-08-04, AGENTS.md section 6.8: unblocked as ONE
        # bundle, never individually.
        self.assertEqual(
            UNBLOCKED_20260804,
            {
                "20260726030000",
                "20260726031000",
                "20260726032000",
                "20260726180000",
            },
        )
        self.assertFalse(UNBLOCKED_20260804 & HARD_BLOCKED)
        self.assertEqual(
            parse_allowlist(",".join(sorted(UNBLOCKED_20260804))),
            sorted(UNBLOCKED_20260804),
        )

    def test_local_migration_versions_are_unique(self) -> None:
        # A duplicate 14-digit version silently SKIPS a migration: the ledger
        # keys on the version alone. local_migrations raises on duplicates.
        self.assertGreater(len(local_migrations(REPO)), 300)

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

    def test_empty_remote_ledger_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.txt"
            path.write_text("Local | Remote | Time\n", encoding="utf-8")
            with self.assertRaises(GuardError):
                parse_remote_versions(path)

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
        self.assertNotIn("supabase db push\n", production)
        self.assertNotIn("--include-all", production)

    def test_run_blocks_do_not_embed_dispatch_inputs(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "shared-supabase-migrations.yml"
        ).read_text(encoding="utf-8")
        in_run = False
        run_indent = 0
        for line in workflow.splitlines():
            indent = len(line) - len(line.lstrip())
            if line.lstrip().startswith("run:"):
                in_run = True
                run_indent = indent
            elif in_run and line.strip() and indent <= run_indent:
                in_run = False
            if in_run:
                self.assertNotIn("${{ inputs.", line)

    def test_prepare_removes_every_unapproved_pending_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            output = root / "bounded"
            migrations = repo / "supabase" / "migrations"
            migrations.mkdir(parents=True)
            for name in (
                "20260727010000_applied.sql",
                "20260727020000_approved.sql",
                "20260727030000_unapproved.sql",
            ):
                (migrations / name).write_text("select 1;\n", encoding="utf-8")
            ledger = root / "ledger.txt"
            ledger.write_text(
                "Local | Remote | Time\n"
                "20260727010000 | 20260727010000 | x\n",
                encoding="utf-8",
            )

            def fake_worktree(*_args, **_kwargs):
                import shutil
                shutil.copytree(repo, output)

            with patch(
                "production_migration_guard.subprocess.run",
                side_effect=fake_worktree,
            ):
                prepare(
                    repo,
                    output,
                    "a" * 40,
                    "20260727020000",
                    ledger,
                )
            names = sorted(path.name for path in (output / "supabase" / "migrations").glob("*.sql"))
            self.assertEqual(
                names,
                [
                    "20260727010000_applied.sql",
                    "20260727020000_approved.sql",
                ],
            )


class PreflightNegativeTests(unittest.TestCase):
    """The guard must FIRE. Every test here points it at a bad input."""

    def test_real_14_file_batch_is_rejected_at_file_3_and_file_10(self) -> None:
        migrations = local_migrations(REPO)
        remote = production_ledger_versions()
        with self.assertRaises(GuardError) as caught:
            preflight_batch(migrations, BATCH_14, remote)
        message = str(caught.exception)
        # File 3 of 14: the foreign key in create table if not exists.
        self.assertIn("20260727221500", message)
        self.assertIn("plm.taxonomy_sync_alert", message)
        self.assertIn("foreign key", message)
        # File 6 of 14 / file 10 of 18: the trigger on a missing table.
        self.assertIn("20260728134500", message)
        self.assertIn("trigger target", message)
        self.assertIn("plm.taxonomy_parallel_observation", message)
        # And it names the excluded creator.
        self.assertIn("20260726180000", message)

    def test_real_18_file_batch_passes(self) -> None:
        migrations = local_migrations(REPO)
        remote = production_ledger_versions()
        preflight_batch(migrations, BATCH_18, remote)

    def test_prepare_refuses_a_batch_that_cannot_run_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = write_migrations(
                root / "repo",
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_maker.sql": "create table plm.parent (id uuid primary key);",
                    "20260103000000_user.sql": (
                        "create table if not exists plm.child (\n"
                        "  id uuid primary key,\n"
                        "  parent_id uuid references plm.parent(id)\n"
                        ");"
                    ),
                },
            )
            ledger = root / "ledger.txt"
            ledger.write_text(
                "Local | Remote | Time\n20260101000000 | 20260101000000 | x\n",
                encoding="utf-8",
            )
            with patch("production_migration_guard.subprocess.run") as run:
                with self.assertRaises(GuardError):
                    prepare(repo, root / "out", "a" * 40, "20260103000000", ledger)
            # It must fail BEFORE any worktree is created.
            run.assert_not_called()

    def test_if_not_exists_does_not_save_a_missing_foreign_key_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_maker.sql": "create table plm.parent (id uuid primary key);",
                    "20260103000000_user.sql": (
                        "create table if not exists plm.child ("
                        "id uuid, p uuid references plm.parent(id));"
                    ),
                },
            )
            with self.assertRaises(GuardError):
                preflight_batch(
                    local_migrations(repo), ["20260103000000"], {"20260101000000"}
                )

    def test_drop_trigger_if_exists_does_not_save_a_missing_table(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_maker.sql": "create table plm.alert (id uuid);",
                    "20260103000000_user.sql": (
                        "drop trigger if exists t on plm.alert;\n"
                        "create trigger t after insert on plm.alert "
                        "for each row execute function plm.f();"
                    ),
                },
            )
            with self.assertRaises(GuardError):
                preflight_batch(
                    local_migrations(repo), ["20260103000000"], {"20260101000000"}
                )

    def test_creator_later_in_the_batch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_user.sql": (
                        "alter table plm.late add column x int;"
                    ),
                    "20260103000000_maker.sql": "create table plm.late (id uuid);",
                },
            )
            with self.assertRaises(GuardError):
                preflight_batch(
                    local_migrations(repo),
                    ["20260102000000", "20260103000000"],
                    {"20260101000000"},
                )


class PreflightPositiveTests(unittest.TestCase):
    def test_creator_earlier_in_the_batch_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_maker.sql": "create table plm.parent (id uuid primary key);",
                    "20260103000000_user.sql": (
                        "create table plm.child (id uuid, p uuid references plm.parent(id));"
                    ),
                },
            )
            preflight_batch(
                local_migrations(repo),
                ["20260102000000", "20260103000000"],
                {"20260101000000"},
            )

    def test_unknown_creator_is_silent_reject_never_approve(self) -> None:
        # No local migration creates public.ancient, so the check has no
        # positive evidence and must stay quiet rather than guess.
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_user.sql": "alter table public.ancient add column x int;",
                },
            )
            preflight_batch(
                local_migrations(repo), ["20260102000000"], {"20260101000000"}
            )

    def test_function_bodies_are_deferrable_and_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = write_migrations(
                Path(directory),
                {
                    "20260101000000_base.sql": "create table plm.base (id uuid);",
                    "20260102000000_fn.sql": (
                        "create or replace function plm.f() returns void as $$\n"
                        "begin\n"
                        "  alter table plm.made_much_later add column x int;\n"
                        "end;\n"
                        "$$ language plpgsql;"
                    ),
                    "20260103000000_maker.sql": "create table plm.made_much_later (id uuid);",
                },
            )
            preflight_batch(
                local_migrations(repo), ["20260102000000"], {"20260101000000"}
            )


if __name__ == "__main__":
    unittest.main()
