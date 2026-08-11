#!/usr/bin/env python3
"""Offline tests for the production apply review-reference gate.

No network, no secrets, no database, no cost. This replaces the tests for
`production_apply_model_review.py`, which stubbed an Anthropic API call that no
longer exists.

The behaviour under test is one sentence long: **a production apply cannot
proceed unless the operator records where the review was performed, and no
input short of a real reference gets through.** The tests below are mostly
refusals, on purpose -- the value of a gate is entirely in what it rejects.
"""

import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import production_apply_review_reference as gate  # noqa: E402

REPO = Path(__file__).resolve().parents[1]

GOOD_URL = "https://github.com/u2giants/shared-db/pull/804#pullrequestreview-1234567890"


class TestRefusals(unittest.TestCase):
    """Everything here must FAIL CLOSED."""

    def refused(self, value: str) -> str:
        accepted, reason = gate.validate(value)
        self.assertFalse(accepted, f"{value!r} was accepted and should not be")
        self.assertTrue(reason, "a refusal must say why")
        return reason

    def test_empty_is_refused(self) -> None:
        self.refused("")

    def test_whitespace_only_is_refused(self) -> None:
        for value in (" ", "\t", "   \t  ", " " if False else "  "):
            with self.subTest(value=value):
                self.refused(value)

    def test_placeholders_are_refused_by_name(self) -> None:
        for value in ("n/a", "N/A", "none", "None", "TBD", "skip", "-", "todo", "x"):
            with self.subTest(value=value):
                reason = self.refused(value)
                self.assertIn("placeholder", reason)

    def test_bare_prose_is_refused(self) -> None:
        self.refused("I reviewed it myself and it looked fine")

    def test_a_bare_host_is_refused(self) -> None:
        reason = self.refused("https://github.com")
        self.assertIn("no path", reason)

    def test_a_urlish_string_with_no_host_is_refused(self) -> None:
        self.refused("https:///pull/804")

    def test_plain_http_is_refused(self) -> None:
        reason = self.refused("http://github.com/u2giants/shared-db/pull/804")
        self.assertIn("http", reason)

    def test_multiline_is_refused(self) -> None:
        # Stops an operator smuggling a second value, or a newline-padded blank.
        reason = self.refused(f"{GOOD_URL}\nand also nothing")
        self.assertIn("single line", reason)

    def test_an_arbitrary_repo_path_is_refused(self) -> None:
        reason = self.refused("README.md")
        self.assertIn(".ai/reviews/", reason)

    def test_a_reviews_path_that_does_not_exist_is_refused(self) -> None:
        reason = self.refused(".ai/reviews/this-file-was-never-written.md")
        self.assertIn("does not exist", reason)

    def test_a_traversal_path_is_refused(self) -> None:
        accepted, reason = gate.validate(".ai/reviews/../../../etc/passwd")
        self.assertFalse(accepted)
        self.assertTrue(reason)


class TestAcceptances(unittest.TestCase):
    def test_a_github_review_comment_url_is_accepted(self) -> None:
        accepted, reason = gate.validate(GOOD_URL)
        self.assertTrue(accepted, reason)

    def test_an_issue_comment_url_is_accepted(self) -> None:
        accepted, reason = gate.validate(
            "https://github.com/u2giants/shared-db/issues/800#issuecomment-1"
        )
        self.assertTrue(accepted, reason)

    def test_surrounding_whitespace_is_tolerated(self) -> None:
        accepted, reason = gate.validate(f"  {GOOD_URL}  ")
        self.assertTrue(accepted, reason)

    def test_an_existing_reviews_file_is_accepted(self) -> None:
        existing = sorted(Path(REPO, ".ai", "reviews").glob("*.md"))
        self.assertTrue(existing, ".ai/reviews/ is empty; this test needs a real file")
        rel = existing[0].relative_to(REPO).as_posix()
        accepted, reason = gate.validate(rel, repo=REPO)
        self.assertTrue(accepted, reason)

    def test_a_windows_style_path_is_accepted(self) -> None:
        existing = sorted(Path(REPO, ".ai", "reviews").glob("*.md"))
        rel = existing[0].relative_to(REPO).as_posix().replace("/", "\\")
        accepted, reason = gate.validate(rel, repo=REPO)
        self.assertTrue(accepted, reason)


class TestMainAndEvidence(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.summary = Path(self.temp.name, "summary.md")
        self.summary.write_text("", encoding="utf-8")
        self.env = {
            "RUNNER_TEMP": self.temp.name,
            "GITHUB_STEP_SUMMARY": str(self.summary),
            "GITHUB_WORKSPACE": str(REPO),
            "GITHUB_ACTOR": "u2giants",
            "REQUESTED_SHA": "326c25e16123029af3b302945d283a729801a995",
            "PRODUCTION_ALLOWLIST": "20260810070000",
        }

    def run_main(self, reference: str) -> int:
        with patch.dict(os.environ, {**self.env, "REVIEW_REFERENCE": reference}):
            return gate.main()

    def summary_text(self) -> str:
        return self.summary.read_text(encoding="utf-8")

    def artifact_text(self) -> str:
        return Path(self.temp.name, "production-review-reference.md").read_text(
            encoding="utf-8"
        )

    def test_missing_reference_exits_non_zero(self) -> None:
        self.assertEqual(self.run_main(""), 1)

    def test_missing_reference_says_so_in_the_evidence(self) -> None:
        self.run_main("   ")
        for text in (self.summary_text(), self.artifact_text()):
            self.assertIn("FAILING ON PURPOSE", text)

    def test_missing_reference_emits_an_error_annotation(self) -> None:
        with patch.object(gate, "safe_print") as printed:
            self.run_main("")
        emitted = "\n".join(str(call.args[0]) for call in printed.call_args_list)
        self.assertIn("::error::", emitted)

    def test_a_good_reference_exits_zero(self) -> None:
        self.assertEqual(self.run_main(GOOD_URL), 0)

    def test_the_evidence_records_the_reference_sha_and_allowlist(self) -> None:
        self.run_main(GOOD_URL)
        for text in (self.summary_text(), self.artifact_text()):
            self.assertIn(GOOD_URL, text)
            self.assertIn("326c25e16123029af3b302945d283a729801a995", text)
            self.assertIn("20260810070000", text)
            self.assertIn("u2giants", text)

    def test_the_evidence_does_not_overclaim(self) -> None:
        # It must not say the review was good, only that a reference exists.
        self.run_main(GOOD_URL)
        self.assertIn("does NOT prove", self.artifact_text())

    def test_no_environment_variable_bypasses_the_check(self) -> None:
        # Anything that smells like a skip switch must not exist.
        for name in ("SKIP_REVIEW", "SKIP_REVIEW_REFERENCE", "FORCE", "ALLOW_NO_REVIEW"):
            with patch.dict(os.environ, {**self.env, "REVIEW_REFERENCE": "", name: "1"}):
                self.assertEqual(gate.main(), 1, f"{name} bypassed the gate")


class TestNoPaidCallRemains(unittest.TestCase):
    """The whole point of the change: this lane costs nothing to run."""

    def source(self) -> str:
        return Path(gate.__file__).read_text(encoding="utf-8")

    def test_the_gate_never_touches_the_anthropic_api(self) -> None:
        src = self.source()
        self.assertNotIn("api.anthropic.com", src)
        self.assertNotIn("urllib.request", src)

    def test_the_deleted_model_review_script_is_gone(self) -> None:
        self.assertFalse(
            Path(REPO, "scripts", "production_apply_model_review.py").exists(),
            "the paid model review script is back; it was removed on purpose",
        )
        self.assertFalse(
            Path(REPO, "scripts", "test_production_apply_model_review.py").exists()
        )


class TestWorkflowWiring(unittest.TestCase):
    """A gate the workflow is allowed to shrug off is not a gate."""

    def workflow(self) -> str:
        return Path(
            REPO, ".github", "workflows", "shared-supabase-migrations.yml"
        ).read_text(encoding="utf-8")

    def test_the_workflow_runs_this_gate(self) -> None:
        self.assertIn("production_apply_review_reference.py", self.workflow())

    def test_the_workflow_no_longer_runs_the_paid_review(self) -> None:
        workflow = self.workflow()
        self.assertNotIn("production_apply_model_review.py", workflow)
        self.assertNotIn("ANTHROPIC_API_KEY", workflow)
        self.assertNotIn("SHARED_DB_REVIEW_MODEL", workflow)

    def test_the_review_reference_input_exists(self) -> None:
        self.assertIn("review_reference:", self.workflow())

    def test_the_input_has_no_default_that_would_satisfy_the_gate(self) -> None:
        workflow = self.workflow()
        block = workflow.split("review_reference:", 1)[1].split("\n      ", 1)[0]
        self.assertNotIn("default:", block, "a default would pre-satisfy the gate")

    def test_no_step_in_the_workflow_carries_continue_on_error(self) -> None:
        offenders = [
            line
            for line in self.workflow().splitlines()
            if re.match(r"^\s*continue-on-error\s*:", line)
        ]
        self.assertEqual(offenders, [], f"continue-on-error is back: {offenders}")

    def test_the_reference_is_saved_into_the_apply_evidence(self) -> None:
        self.assertIn("production-review-reference.md", self.workflow())


if __name__ == "__main__":
    unittest.main()
