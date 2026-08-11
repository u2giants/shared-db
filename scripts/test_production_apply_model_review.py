#!/usr/bin/env python3
"""Offline tests for the production apply model review.

No network, no secrets, no database. Every API call is stubbed.

The behaviour under test is the one that was broken: a review that did not
happen must FAIL, and a review that happened must PASS regardless of the
model's opinion.
"""

from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import production_apply_model_review as review  # noqa: E402


class EnvSandbox(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        temp = Path(self.temp.name)
        (temp / "supabase" / "migrations").mkdir(parents=True)
        (temp / "supabase" / "migrations" / "20260101000000_thing.sql").write_text(
            "create table public.thing();", encoding="utf-8"
        )
        self.summary = temp / "summary.md"
        env = {
            "PRODUCTION_ALLOWLIST": "20260101000000",
            "REQUESTED_SHA": "deadbeef",
            "ANTHROPIC_API_KEY": "test-key",
            "GITHUB_WORKSPACE": str(temp),
            "RUNNER_TEMP": str(temp),
            "GITHUB_STEP_SUMMARY": str(self.summary),
        }
        patcher = patch.dict("os.environ", env, clear=False)
        patcher.start()
        self.addCleanup(patcher.stop)

    def summary_text(self) -> str:
        return (
            self.summary.read_text(encoding="utf-8")
            if self.summary.exists()
            else ""
        )


class TestReviewMustRun(EnvSandbox):
    """The whole point: a review that did not happen is RED, not green."""

    def test_missing_api_key_fails_the_job(self) -> None:
        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": ""}):
            self.assertEqual(review.main(), 1)
        text = self.summary_text()
        self.assertIn("REVIEW DID NOT RUN", text)
        self.assertIn("ANTHROPIC_API_KEY", text)

    def test_whitespace_only_api_key_fails_the_job(self) -> None:
        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "   "}):
            self.assertEqual(review.main(), 1)

    def test_empty_allowlist_fails_the_job(self) -> None:
        with patch.dict("os.environ", {"PRODUCTION_ALLOWLIST": ""}):
            self.assertEqual(review.main(), 1)
        self.assertIn("allowlist was empty", self.summary_text())

    def test_api_error_fails_the_job_after_retrying(self) -> None:
        calls = []

        def boom(prompt, api_key):
            calls.append(1)
            raise OSError("connection reset")

        with patch.object(review, "call_api", boom), patch.object(
            review.time, "sleep", lambda _s: None
        ):
            self.assertEqual(review.main(), 1)
        self.assertEqual(len(calls), review.ATTEMPTS)
        self.assertIn("REVIEW DID NOT RUN", self.summary_text())

    def test_empty_model_response_fails_the_job(self) -> None:
        with patch.object(review, "call_api", lambda p, k: "  "), patch.object(
            review.time, "sleep", lambda _s: None
        ):
            self.assertEqual(review.main(), 1)

    def test_transient_failure_then_success_passes(self) -> None:
        state = {"n": 0}

        def flaky(prompt, api_key):
            state["n"] += 1
            if state["n"] == 1:
                raise OSError("transient")
            return "Looks fine.\nVERDICT: CLEAR"

        with patch.object(review, "call_api", flaky), patch.object(
            review.time, "sleep", lambda _s: None
        ):
            self.assertEqual(review.main(), 0)
        self.assertEqual(state["n"], 2)

    def test_there_is_no_bypass_env_var(self) -> None:
        """A future 'skip the review' flag must not quietly reappear."""
        source = Path(review.__file__).read_text(encoding="utf-8")
        for banned in ("SKIP_MODEL_REVIEW", "MODEL_REVIEW_OPTIONAL", "ALLOW_NO_REVIEW"):
            self.assertNotIn(banned, source)


class TestVerdictStaysAdvisory(EnvSandbox):
    """A model may not block a production apply, nor have its concerns hidden."""

    def test_clear_verdict_passes(self) -> None:
        with patch.object(review, "call_api", lambda p, k: "Nothing.\nVERDICT: CLEAR"):
            self.assertEqual(review.main(), 0)
        self.assertNotIn("RAISED CONCERNS", self.summary_text())

    def test_concerns_verdict_passes_but_shouts(self) -> None:
        with patch.object(
            review, "call_api", lambda p, k: "Drops a column.\nVERDICT: CONCERNS"
        ):
            self.assertEqual(review.main(), 0)
        text = self.summary_text()
        self.assertIn("RAISED CONCERNS", text)
        self.assertIn("Drops a column.", text)

    def test_unreadable_verdict_is_treated_as_concerns(self) -> None:
        with patch.object(review, "call_api", lambda p, k: "I have opinions."):
            self.assertEqual(review.main(), 0)
        text = self.summary_text()
        self.assertIn("RAISED CONCERNS", text)
        self.assertIn("readable", text)

    def test_read_verdict_takes_the_last_line(self) -> None:
        self.assertEqual(
            review.read_verdict("VERDICT: CLEAR\nmore\nVERDICT: CONCERNS"), "CONCERNS"
        )
        self.assertEqual(review.read_verdict("nope"), "UNREADABLE")
        self.assertEqual(review.read_verdict("VERDICT: CLEAR"), "CLEAR")

    def test_prompt_demands_a_machine_readable_verdict(self) -> None:
        self.assertIn("VERDICT: CLEAR", review.PROMPT)
        self.assertIn("VERDICT: CONCERNS", review.PROMPT)


class TestWorkflowWiring(unittest.TestCase):
    """The script can only fail the job if the step is allowed to fail."""

    def test_model_review_step_has_no_continue_on_error(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "shared-supabase-migrations.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("production_apply_model_review.py", workflow)
        # A real step-level key, not the word inside an explanatory comment.
        offenders = [
            line
            for line in workflow.splitlines()
            if re.match(r"^\s*continue-on-error\s*:", line)
        ]
        self.assertEqual(offenders, [], f"continue-on-error is back: {offenders}")


if __name__ == "__main__":
    unittest.main()
