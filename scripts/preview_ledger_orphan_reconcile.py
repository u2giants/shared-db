#!/usr/bin/env python3
"""Reconcile one proven preview-only ledger orphan without touching schema DDL."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

from atomic_migration_apply import load_candidate, linked_connection, psql
from production_migration_guard import parse_remote_versions


class Refusal(RuntimeError):
    pass


def version(value: str) -> str:
    if not re.fullmatch(r"\d{14}", value or ""):
        raise Refusal("migration versions must be exactly 14 digits")
    return value


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise Refusal(f"unreadable JSON evidence: {path.name}") from exc


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if result.returncode:
        raise Refusal("git evidence check failed")
    return result.stdout.strip()


def validate_governance(args, local_statements: list[str]) -> dict:
    repo = args.repo.resolve()
    if git(repo, "rev-parse", "HEAD") != args.main_sha or git(repo, "rev-parse", "origin/main") != args.main_sha:
        raise Refusal("checkout is not exact current main")
    if list((repo / "supabase/migrations").glob(f"{args.orphan_version}_*.sql")):
        raise Refusal("orphan version still exists on current main")

    issue, claim, pr, run, artifact = (read_json(p) for p in (args.issue_json, args.claim_json, args.pr_json, args.run_json, args.artifact_json))
    if issue.get("number") != args.issue or issue.get("state") != "open":
        raise Refusal("work issue is not the exact open issue")
    if claim.get("number") != args.claim or claim.get("state") != "open" or f"#{args.issue}" not in claim.get("title", ""):
        raise Refusal("claim is not the exact open issue claim")
    if not re.search(rf"^version: {re.escape(args.replacement_version)}$", claim.get("body", ""), re.M):
        raise Refusal("claim does not bind the replacement version")
    if pr.get("number") != args.source_pr or not pr.get("merged") or not pr.get("merge_commit_sha"):
        raise Refusal("source pull request is not the exact merged PR")
    if git(repo, "merge-base", "--is-ancestor", pr["merge_commit_sha"], args.main_sha) != "":
        pass
    if run.get("id") != args.preview_run_id or run.get("status") != "completed" or run.get("conclusion") != "success":
        raise Refusal("preview run is not the exact successful run")
    if artifact.get("workflow_run", {}).get("id") != args.preview_run_id or artifact.get("digest") != args.preview_artifact_digest or artifact.get("expired"):
        raise Refusal("preview artifact identity or digest mismatch")

    before_path = args.preview_evidence_dir / "preview-ledger-before.txt"
    after_path = args.preview_evidence_dir / "preview-ledger-after.txt"
    before = before_path.read_text(encoding="utf-8")
    after = after_path.read_text(encoding="utf-8")
    apply = (args.preview_evidence_dir / "preview-apply.txt").read_text(encoding="utf-8")
    before_versions, after_versions = parse_remote_versions(before_path), parse_remote_versions(after_path)
    if args.replacement_version in before_versions or args.replacement_version not in after_versions or after_versions - before_versions != {args.replacement_version}:
        raise Refusal("preview artifact does not prove replacement-only ledger addition")
    if f"Applying migration {args.replacement_version}_" not in apply:
        raise Refusal("preview artifact does not prove replacement application")
    return {"statement_count": len(local_statements), "migration_sha256": hashlib.sha256(args.migration.read_bytes()).hexdigest()}


def ledger_rows(url: str, env: dict[str, str], old: str, replacement: str) -> list[dict]:
    sql = (
        "select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name,'statements',statements) order by version),'[]'::jsonb)::text "
        "from supabase_migrations.schema_migrations where version in ('" + old + "','" + replacement + "');\n"
    )
    value = json.loads(psql(url, env, sql))
    if not isinstance(value, list):
        raise Refusal("migration ledger returned an invalid shape")
    return value


def reconcile(url: str, env: dict[str, str], args, expected: list[str]) -> tuple[list[dict], list[dict]]:
    before = ledger_rows(url, env, args.orphan_version, args.replacement_version)
    by_version = {str(row.get("version")): row for row in before}
    if set(by_version) != {args.orphan_version, args.replacement_version}:
        raise Refusal("ledger must contain exactly the orphan and replacement rows")
    if by_version[args.orphan_version].get("statements") != expected or by_version[args.replacement_version].get("statements") != expected:
        raise Refusal("orphan and replacement statements are not both exact local migration bytes")
    if args.mode == "check":
        return before, before
    expected_json = json.dumps(expected, separators=(",", ":"))
    sql = rf"""\set ON_ERROR_STOP on
begin;
lock table supabase_migrations.schema_migrations in exclusive mode;
do $reconcile$
declare n integer;
begin
  if (select count(*) from supabase_migrations.schema_migrations where version in ('{args.orphan_version}','{args.replacement_version}')) <> 2 then
    raise exception 'ledger ownership changed before reconciliation';
  end if;
  if (select to_jsonb(statements) from supabase_migrations.schema_migrations where version='{args.orphan_version}') <> $expected${expected_json}$expected$::jsonb
     or (select to_jsonb(statements) from supabase_migrations.schema_migrations where version='{args.replacement_version}') <> $expected${expected_json}$expected$::jsonb then
    raise exception 'ledger statements changed before reconciliation';
  end if;
  delete from supabase_migrations.schema_migrations where version='{args.orphan_version}';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'reconciliation did not delete exactly one row'; end if;
  if (select count(*) from supabase_migrations.schema_migrations where version='{args.replacement_version}') <> 1 then
    raise exception 'replacement ledger row disappeared';
  end if;
end $reconcile$;
commit;
"""
    psql(url, env, sql)
    after = ledger_rows(url, env, args.orphan_version, args.replacement_version)
    if [str(row.get("version")) for row in after] != [args.replacement_version]:
        raise Refusal("post-reconciliation readback is not replacement-only")
    return before, after


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=("check", "apply"), required=True)
    p.add_argument("--repo", type=Path, required=True); p.add_argument("--linked-dir", type=Path, required=True)
    p.add_argument("--expected-project-ref", required=True); p.add_argument("--main-sha", required=True)
    p.add_argument("--orphan-version", type=version, required=True); p.add_argument("--replacement-version", type=version, required=True)
    p.add_argument("--issue", type=int, required=True); p.add_argument("--claim", type=int, required=True); p.add_argument("--source-pr", type=int, required=True)
    p.add_argument("--preview-run-id", type=int, required=True); p.add_argument("--preview-artifact-digest", required=True)
    p.add_argument("--issue-json", type=Path, required=True); p.add_argument("--claim-json", type=Path, required=True); p.add_argument("--pr-json", type=Path, required=True)
    p.add_argument("--run-json", type=Path, required=True); p.add_argument("--artifact-json", type=Path, required=True); p.add_argument("--preview-evidence-dir", type=Path, required=True)
    p.add_argument("--evidence-out", type=Path, required=True)
    return p.parse_args()


def main() -> int:
    try:
        args = parse_args()
        if args.orphan_version == args.replacement_version or args.expected_project_ref != "rjyboqwcdzcocqgmsyel":
            raise Refusal("reconciliation is preview-only and requires two different versions")
        args.migration, _, _, statements = load_candidate(args.repo / "supabase/migrations", args.replacement_version, "preview")
        governance = validate_governance(args, statements)
        url, env = linked_connection(args.linked_dir, args.expected_project_ref)
        before, after = reconcile(url, env, args, statements)
        args.evidence_out.write_text(json.dumps({"schema":"shared-db-preview-ledger-orphan-reconciliation/v1","mode":args.mode,"project_ref":args.expected_project_ref,"main_sha":args.main_sha,"issue":args.issue,"claim":args.claim,"source_pr":args.source_pr,"orphan_version":args.orphan_version,"replacement_version":args.replacement_version,"preview_run_id":args.preview_run_id,"preview_artifact_digest":args.preview_artifact_digest,"governance":governance,"before":before,"after":after}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"PREVIEW LEDGER RECONCILIATION {args.mode.upper()} OK: removed={args.orphan_version if args.mode == 'apply' else 'none'} replacement={args.replacement_version}")
        return 0
    except (Refusal, RuntimeError, OSError, ValueError) as exc:
        print(f"REFUSED: {exc}", file=__import__('sys').stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
