#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_class(){
  local path="$1" expected="$2" label="$3" actual
  printf '%s\n' "$path" > "$TMP/paths"
  actual="$(ai-task-gates explain --json --paths-from "$TMP/paths" | jq -r '.observed_class')"
  if [ "$actual" = "$expected" ]; then pass "$label"; else fail "$label (expected $expected, got $actual)"; fi
}

expect_class README.md prose 'ordinary documentation uses the prose fast path'
expect_class scripts/example.py code 'ordinary source uses the code path'
expect_class supabase/config.toml shared-db 'Supabase configuration is protected shared-db work'
expect_class supabase/migrations/20990101000000_fixture.sql shared-db 'migration is protected shared-db work'

fixture="$TMP/shared-db"
mkdir -p "$fixture/.ai-devops"
git -C "$TMP" init --quiet shared-db
git -C "$fixture" config user.name 'Task Gate Test'
git -C "$fixture" config user.email 'task-gate-test@example.invalid'
git -C "$fixture" remote add origin https://github.com/u2giants/shared-db.git
cp "$ROOT/.ai-devops/task-gates.json" "$fixture/.ai-devops/task-gates.json"
git -C "$fixture" add .ai-devops/task-gates.json
git -C "$fixture" commit --quiet -m baseline

export AI_TASK_GATES_DIR="$TMP/state"
(
  cd "$fixture"
  ai-task-gates start --class code --base HEAD >/dev/null
  mkdir -p supabase/migrations
  printf '%s\n' '-- classification fixture only' > supabase/migrations/20990101000000_fixture.sql
)

assert_blocked(){
  local label="$1"; shift
  local output rc
  set +e
  output="$(cd "$fixture" && ai-task-gates check --before deploy "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 3 ] && grep -q 'protected' <<<"$output"; then pass "$label"; else fail "$label (exit $rc)"; fi
}

assert_blocked 'migration scope escalation refuses deployment'
assert_blocked 'acknowledgement cannot bypass protected migration' --acknowledge 'fixture acknowledgement'
assert_blocked 'owner request cannot bypass protected migration' --owner-request 'fixture owner request'

(
  cd "$fixture"
  rm -f supabase/migrations/20990101000000_fixture.sql
  mkdir -p scripts
  printf '%s\n' 'print("fixture")' > scripts/example.py
  ai-task-gates start --class code --base HEAD >/dev/null
  ai-task-gates check --before ship >/dev/null
)
pass 'valid code flow proceeds to shipping checks'

cp "$fixture/.ai-devops/task-gates.json" "$TMP/policy.backup.json"
rm -f "$fixture/.ai-devops/task-gates.json"
cp "$TMP/policy.backup.json" "$fixture/.ai-devops/task-gates.json"
cmp -s "$TMP/policy.backup.json" "$fixture/.ai-devops/task-gates.json" \
  && pass 'policy rollback and restore leaves repository code unchanged' \
  || fail 'policy rollback and restore did not reproduce the declaration'

if [ "$failures" -ne 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '9 passed / 0 failed\n'
