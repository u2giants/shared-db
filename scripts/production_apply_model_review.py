#!/usr/bin/env python3
"""Run a model review of a proposed production apply, and prove that it ran.

Two different things live in this script, and keeping them apart is the whole
design. Read this before changing anything here.

  1. THE REVIEW'S VERDICT IS ADVISORY. A model saying "APPROVE" approves
     nothing; a model saying "REJECT" blocks nothing. The blocking checks are
     the deterministic ones in `production_migration_guard.py`, and the gate
     that actually holds is Albert clicking approve on the `production`
     environment. Never make the verdict itself fail the run: that would create
     a lane where a model can wave a production write through (or hold one
     hostage). A verdict of "concerns found" is therefore reported LOUDLY --
     a `::warning::` annotation and a CONCERNS banner at the top of the job
     summary -- but it is not swallowed and it is not blocking.

  2. THE REVIEW ACTUALLY HAPPENING IS MANDATORY. This is the part that changed
     (issue: "silent no-op on every production apply"). Previously this script
     always exited 0 and the workflow step carried `continue-on-error: true`,
     so a missing `ANTHROPIC_API_KEY` -- which is exactly the state this
     repository was in -- produced a fully GREEN production-apply-review job
     that had reviewed nothing. A green tick that stands in for evidence it
     never gathered is a silent failure, and silent failures are banned.

     So: missing API key, empty allowlist, API/network error after retries, or
     an empty model response now EXIT NON-ZERO with a message naming the cause.
     The `production-apply-review` job goes red, and because `production-apply`
     `needs:` it, the approval gate is never even offered.

     There is deliberately NO environment-variable escape hatch. If the review
     cannot run, fix the review (add the secret) -- do not add a bypass, or you
     have rebuilt the hole this script was changed to close.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.request

MODEL = "claude-opus-4-5-20260514"
API_URL = "https://api.anthropic.com/v1/messages"

ATTEMPTS = 3
BACKOFF_SECONDS = (5, 15)

BANNER = (
    "> **ADVISORY VERDICT.** The verdict below does not gate anything. The "
    "blocking checks are `production_migration_guard.py`; the approval gate is "
    "the `production` environment reviewer. What IS enforced is that this "
    "review ran at all -- if it could not run, this job is red and you are not "
    "reading this.\n\n"
)

PROMPT = """You are reviewing a proposed bounded production database migration \
apply for the shared Supabase project `qsllyeztdwjgirsysgai`.

Commit SHA: {sha}
Allowlist ({count} migrations, in order):
{versions}

Migration SQL follows. For each file, judge:
1. Is it additive, or does it drop/rename/alter something other apps may read?
2. Does it grant or leave in place a privilege that should be revoked?
3. Does it depend on an object that no earlier file in this batch creates?
4. Is there anything in it that cannot be undone by a forward-only lane?

Answer with a short technical verdict: a one-line summary, then the specific \
concerns, then a bullet list of anything the human approver should check before \
approving. Be concrete. If you see nothing concerning, say so plainly rather \
than inventing risk.

Your LAST line must be exactly one of these two, on its own line, with nothing \
after it:
VERDICT: CLEAR
VERDICT: CONCERNS

Use CONCERNS if there is anything at all the human approver should look at \
before approving. Use CLEAR only if you found nothing.

{sql}
"""

MAX_SQL_CHARS = 400_000

VERDICT_RE = re.compile(r"^VERDICT:\s*(CLEAR|CONCERNS)\s*$", re.MULTILINE)


class ReviewNotPerformed(Exception):
    """The review did not happen. This is fatal; it is never advisory."""


def collect_sql(repo: Path, versions: list[str]) -> str:
    chunks: list[str] = []
    total = 0
    for version in versions:
        matches = sorted((repo / "supabase" / "migrations").glob(f"{version}_*.sql"))
        if not matches:
            chunks.append(f"\n===== {version} — FILE NOT FOUND =====\n")
            continue
        body = matches[0].read_text(encoding="utf-8", errors="replace")
        if total + len(body) > MAX_SQL_CHARS:
            chunks.append(
                f"\n===== {matches[0].name} — TRUNCATED, batch exceeds "
                f"{MAX_SQL_CHARS} characters =====\n"
            )
            break
        total += len(body)
        chunks.append(f"\n===== {matches[0].name} =====\n{body}")
    return "".join(chunks)


def call_api(prompt: str, api_key: str) -> str:
    payload = json.dumps(
        {
            "model": MODEL,
            "max_tokens": 4000,
            "messages": [{"role": "user", "content": prompt}],
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
            "x-api-key": api_key,
        },
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        body = json.loads(response.read().decode("utf-8"))
    return "".join(
        block.get("text", "")
        for block in body.get("content", [])
        if block.get("type") == "text"
    ).strip()


def ask_model(prompt: str, api_key: str, sleep=time.sleep) -> str:
    """Call the API, retrying transient failures, then give up LOUDLY.

    A flaky network must not block a production apply on the first hiccup, but
    it must not be papered over either: after ATTEMPTS tries this raises, and
    the caller turns that into a red job.
    """
    last: Exception | None = None
    for attempt in range(ATTEMPTS):
        try:
            text = (call_api(prompt, api_key) or "").strip()
        except (urllib.error.URLError, OSError, ValueError, KeyError) as exc:
            last = exc
            if attempt + 1 < ATTEMPTS:
                sleep(BACKOFF_SECONDS[min(attempt, len(BACKOFF_SECONDS) - 1)])
            continue
        if not text:
            last = ValueError("the model returned an empty response")
            if attempt + 1 < ATTEMPTS:
                sleep(BACKOFF_SECONDS[min(attempt, len(BACKOFF_SECONDS) - 1)])
            continue
        return text
    raise ReviewNotPerformed(
        f"the model review could not be completed after {ATTEMPTS} attempts: "
        f"{type(last).__name__}: {last}"
    )


def read_verdict(text: str) -> str:
    """CLEAR, CONCERNS, or UNREADABLE. An unreadable verdict is NOT clear."""
    found = VERDICT_RE.findall(text)
    if not found:
        return "UNREADABLE"
    return found[-1]


def annotate(level: str, message: str) -> None:
    """Emit a GitHub Actions annotation (harmless plain text off-runner)."""
    print(f"::{level}::{message}")


def publish(text: str, heading: str = "Automatic model review") -> None:
    out = BANNER + text + "\n"
    print(out)
    temp = os.environ.get("RUNNER_TEMP")
    if temp:
        Path(temp, "production-model-review.md").write_text(out, encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"## {heading}\n\n" + out)


def fail(reason: str) -> int:
    """Record why no review exists, then fail the job."""
    body = (
        "**REVIEW DID NOT RUN — THIS JOB IS FAILING ON PURPOSE.**\n\n"
        f"Cause: {reason}\n\n"
        "This production apply has NOT been model-reviewed. The lane refuses to "
        "present a green pre-approval job for a review that never happened. Fix "
        "the cause above and dispatch again; do not add a bypass."
    )
    publish(body, heading="Automatic model review — FAILED TO RUN")
    annotate("error", f"Production apply model review did not run: {reason}")
    print(f"MODEL REVIEW NOT PERFORMED: {reason}", file=sys.stderr)
    return 1


def main() -> int:
    versions = [
        value.strip()
        for value in os.environ.get("PRODUCTION_ALLOWLIST", "").split(",")
        if value.strip()
    ]
    sha = os.environ.get("REQUESTED_SHA", "(unknown)")
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not versions:
        return fail(
            "the allowlist was empty, so there was nothing to review. A "
            "production apply with an empty allowlist is itself a bug."
        )
    if not api_key:
        return fail(
            "`ANTHROPIC_API_KEY` is not configured on this repository, so no "
            "model review could be performed. Add the secret "
            "(Settings -> Secrets and variables -> Actions) and re-dispatch."
        )
    repo = Path(os.environ.get("GITHUB_WORKSPACE", ".")).resolve()
    prompt = PROMPT.format(
        sha=sha,
        count=len(versions),
        versions="\n".join(f"- {version}" for version in versions),
        sql=collect_sql(repo, versions),
    )
    try:
        text = ask_model(prompt, api_key)
    except ReviewNotPerformed as exc:
        return fail(str(exc))

    verdict = read_verdict(text)
    if verdict == "CLEAR":
        publish(text, heading="Automatic model review (advisory) — CLEAR")
        return 0

    # CONCERNS, or a verdict line we could not read. Both are surfaced loudly and
    # neither is blocking: a model may not stop a production apply any more than
    # it may wave one through. An unreadable verdict is treated as CONCERNS
    # because "we could not tell" must never round down to "fine".
    note = (
        ""
        if verdict == "CONCERNS"
        else (
            "\n\n_(The model did not end with a readable `VERDICT:` line, so "
            "this is treated as CONCERNS. Read the text above yourself.)_"
        )
    )
    publish(
        "### :warning: MODEL REVIEW RAISED CONCERNS — READ BEFORE APPROVING\n\n"
        + text
        + note,
        heading="Automatic model review (advisory) — CONCERNS",
    )
    annotate(
        "warning",
        "Production apply model review raised CONCERNS (advisory, not blocking) "
        "— read the job summary before approving.",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
