#!/usr/bin/env python3
"""Apply one exceptional migration and its Supabase ledger row atomically.

The normal migration lane remains Supabase CLI. This tool is fail-closed and only
accepts an exact version+SHA256 entry in config/atomic-migration-allowlist.json.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "config" / "atomic-migration-allowlist.json"
VERSION_RE = re.compile(r"^(\d{14})_(.+)\.sql$")
TX_RE = re.compile(r"(?is)^\s*(begin|start\s+transaction|commit|rollback|savepoint|release\s+savepoint)\b")
EXPECTED_COLUMNS = [
    ("version", "text", "NO"),
    ("statements", "ARRAY", "YES"),
    ("name", "text", "YES"),
]


class Refusal(RuntimeError):
    pass


def split_sql(raw: str) -> list[str]:
    """Split PostgreSQL statements while preserving their exact text."""
    out: list[str] = []
    start = 0
    i = 0
    state = "normal"
    dollar = ""
    while i < len(raw):
        c = raw[i]
        n = raw[i + 1] if i + 1 < len(raw) else ""
        if state == "normal":
            if c == "'": state = "single"
            elif c == '"': state = "double"
            elif c == "-" and n == "-": state = "line"; i += 1
            elif c == "/" and n == "*": state = "block"; i += 1
            elif c == "$":
                m = re.match(r"\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$", raw[i:])
                if m: dollar = m.group(0); state = "dollar"; i += len(dollar) - 1
            elif c == ";":
                statement = raw[start:i].strip()
                if statement: out.append(statement)
                start = i + 1
        elif state == "single":
            if c == "'" and n == "'": i += 1
            elif c == "'": state = "normal"
        elif state == "double":
            if c == '"' and n == '"': i += 1
            elif c == '"': state = "normal"
        elif state == "line":
            if c == "\n": state = "normal"
        elif state == "block":
            if c == "*" and n == "/": state = "normal"; i += 1
        elif state == "dollar" and raw.startswith(dollar, i):
            state = "normal"; i += len(dollar) - 1
        i += 1
    if state not in {"normal", "line"}:
        raise Refusal(f"unterminated SQL lexical state: {state}")
    tail = raw[start:].strip()
    if tail: out.append(tail)
    return out


def dollar_quote(value: str, seed: str) -> str:
    tag = f"$atomic_{seed}$"
    if tag in value:
        raise Refusal("generated dollar-quote tag collides with migration text")
    return f"{tag}{value}{tag}"


def load_candidate(migrations_dir: Path, version: str, target: str) -> tuple[Path, str, str, list[str]]:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    entry = policy.get("migrations", {}).get(version)
    if not entry or target not in entry.get("targets", []):
        raise Refusal(f"version {version} is not atomically authorized for {target}")
    matches = sorted(migrations_dir.glob(f"{version}_*.sql"))
    if len(matches) != 1:
        raise Refusal(f"expected exactly one migration for {version}; found {len(matches)}")
    path = matches[0]
    match = VERSION_RE.fullmatch(path.name)
    if not match or match.group(1) != version:
        raise Refusal("migration filename/version mismatch")
    raw_bytes = path.read_bytes()
    digest = hashlib.sha256(raw_bytes).hexdigest()
    if digest != entry.get("sha256"):
        raise Refusal(f"SHA256 mismatch for {version}")
    raw = raw_bytes.decode("utf-8")
    statements = split_sql(raw)
    if not statements:
        raise Refusal("migration is empty")
    controls = [s for s in statements if TX_RE.match(re.sub(r"(?s)^\s*(?:--[^\n]*\n|/\*.*?\*/\s*)*", "", s))]
    if controls:
        raise Refusal("migration contains forbidden transaction-control statements")
    return path, match.group(2), raw, statements


def linked_connection(linked_dir: Path, expected_ref: str) -> tuple[str, dict[str, str]]:
    if os.environ.get("EXPECTED_PROJECT_REF") != expected_ref:
        raise Refusal("EXPECTED_PROJECT_REF environment does not match requested ref")
    if not os.environ.get("SUPABASE_DB_PASSWORD"):
        raise Refusal("SUPABASE_DB_PASSWORD is missing")
    url_file = linked_dir / "supabase" / ".temp" / "pooler-url"
    if not url_file.is_file():
        raise Refusal("linked Supabase pooler-url is missing")
    url = url_file.read_text(encoding="utf-8").strip()
    parsed = urlparse(url)
    if parsed.scheme not in {"postgres", "postgresql"} or not parsed.hostname:
        raise Refusal("linked pooler-url is malformed")
    if parsed.password:
        raise Refusal("linked pooler-url unexpectedly contains a password")
    if not parsed.username or not parsed.username.endswith("." + expected_ref):
        raise Refusal("linked pooler-url user does not prove the expected project ref")
    if expected_ref not in url:
        raise Refusal("linked pooler-url does not contain the expected project ref")
    env = os.environ.copy()
    env["PGPASSWORD"] = env["SUPABASE_DB_PASSWORD"]
    return url, env


def psql(url: str, env: dict[str, str], sql: str, *, capture: bool = True) -> str:
    result = subprocess.run(
        ["psql", url, "-X", "-v", "ON_ERROR_STOP=1", "-At"],
        input=sql, text=True, env=env, capture_output=capture, check=False,
    )
    if result.returncode:
        raise Refusal("psql failed; transaction rolled back\n" + (result.stderr or "").strip())
    return (result.stdout or "").strip()


def validate_remote(url: str, env: dict[str, str], version: str) -> None:
    sql = """
select current_user;
select column_name||'|'||data_type||'|'||is_nullable
from information_schema.columns
where table_schema='supabase_migrations' and table_name='schema_migrations'
order by ordinal_position;
select count(*) from supabase_migrations.schema_migrations where version = '""" + version + "';\n"
    lines = psql(url, env, sql).splitlines()
    if len(lines) != 5:
        raise Refusal("unexpected migration-ledger catalog result")
    actual = [tuple(line.split("|")) for line in lines[1:4]]
    if actual != EXPECTED_COLUMNS:
        raise Refusal(f"unexpected migration-ledger columns: {actual}")
    if lines[4] != "0":
        raise Refusal(f"version {version} is already applied")


def build_wrapper(version: str, name: str, raw: str, statements: list[str]) -> str:
    values = ",\n".join(dollar_quote(s, f"s{i}") for i, s in enumerate(statements))
    return (
        "\\set ON_ERROR_STOP on\nBEGIN;\n" + raw.rstrip() + "\n"
        "INSERT INTO supabase_migrations.schema_migrations(version, statements, name) VALUES (\n"
        + dollar_quote(version, "version") + ", ARRAY[\n" + values + "\n]::text[], "
        + dollar_quote(name, "name") + ");\nCOMMIT;\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrations-dir", type=Path, required=True)
    parser.add_argument("--linked-dir", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", choices=["preview", "production"], required=True)
    parser.add_argument("--expected-project-ref", required=True)
    parser.add_argument("--mode", choices=["check", "apply"], required=True)
    args = parser.parse_args()
    try:
        path, name, raw, statements = load_candidate(args.migrations_dir, args.version, args.target)
        url, env = linked_connection(args.linked_dir, args.expected_project_ref)
        validate_remote(url, env, args.version)
        print(f"ATOMIC PREFLIGHT OK: target={args.target} version={args.version} sha256={hashlib.sha256(path.read_bytes()).hexdigest()} statements={len(statements)}")
        if args.mode == "check":
            return 0
        wrapper = build_wrapper(args.version, name, raw, statements)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".sql", delete=False) as handle:
            handle.write(wrapper)
            temp_name = handle.name
        try:
            result = subprocess.run(["psql", url, "-X", "-v", "ON_ERROR_STOP=1", "-f", temp_name], env=env, text=True, capture_output=True)
            if result.returncode:
                raise Refusal("atomic apply failed; PostgreSQL rolled back DDL and ledger together\n" + (result.stderr or "").strip())
        finally:
            Path(temp_name).unlink(missing_ok=True)
        verify = psql(url, env, "select count(*)||'|'||coalesce(cardinality(statements),-1)||'|'||coalesce(name,'') from supabase_migrations.schema_migrations where version='" + args.version + "';\n")
        expected = f"1|{len(statements)}|{name}"
        if verify != expected:
            raise Refusal("post-commit ledger verification failed")
        print(f"ATOMIC APPLY OK: target={args.target} version={args.version} ledger_row=1 statements={len(statements)}")
        return 0
    except Refusal as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
