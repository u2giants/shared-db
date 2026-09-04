---
issue: 1223
status: OPEN
owner: claude/1223-guard-mutation-sweep
---

# HANDOFF — issue #1223 guard mutation sweep

## 0. DECISIONS ONLY THE OWNER CAN MAKE

The queue-level owner decisions were already sent to Albert in one message at session start:

1. Keep the newer #1686 presentation ruling and move #1322's “mark inactive” capability into Scraped Properties; this blocks PR #2278.
2. For #1031, send the drafted vendor reply unchanged and initially load three years of history.
3. For #771/#770, authorize only a specifically named, read-only production Cloud SQL rehearsal with no writes.
4. Ask Laura and Ilona for a completion date on #1941.
5. File a repo-maintenance issue for governed-review output being discarded after a refusal.

No additional owner decision is needed for #1223. The next session must not start new queue work; it should finish only this open workstream.

Already settled: repository maintenance belongs to a repository session, not the structural orchestrator; do not re-ask.

## 1. What this application is

`u2giants/shared-db` is the governed source of truth for the shared Supabase database structure and its safety tooling. Issue #1223 is repository-maintenance work on tests for the final promotion evidence chain; it changes no database structure or data.

## 2. What we set out to do this session, and why

Resume the interrupted #1223 mutation sweep from the prior handoff, generate a reproducible JSON report for 266 refusal guards across seven Python files, split surviving untested guards into focused follow-up issues, then continue the non-orchestrator queue. Albert later instructed this session to close out after its current task and take no new work.

## 3. Current state — what is true right now

- Branch/worktree: `claude/1223-guard-mutation-sweep` in `C:/repos/shared-db/.claude/worktrees/shared-db-non-orchestrator-queue-01bc29`.
- The sweep tool is committed in WIP commit `f1ff919849a9e18b6537edf04b54895f2d7b60c5`; no final JSON exists.
- All controlled mutations were restored from `HEAD`. Temporary launcher/log files were removed. Only this handoff should be uncommitted before closeout.
- #1223 remains open. No follow-up issues were created because no complete self-verified JSON was produced.
- This Codex session closed no GitHub issue. Do not attribute predecessor closures #2116 or #2282 to it.

## 4. Everything we tried that did NOT work

1. The exact serial command ran directly for several hours. It reached the fifth of seven files, but a user-provided instruction refresh terminated the attached process. The tool correctly wrote no JSON and left one active mutation, which was restored.
2. A hidden `Start-Process` launch passed the quoted unittest command incorrectly; argument parsing refused immediately before mutation.
3. A temporary PowerShell launcher passed the command correctly, but the process was still killed when its parent command channel reset. It wrote no JSON and left one mutation, which was restored.
4. A third directly attached, unbuffered run proved a green baseline and reached guard 92 of 106 in the first file before Albert stopped the unsustainable eight-hour workflow. It was interrupted and restored. Partial console survivors are not authoritative and must not become issues.
5. The serial design reruns roughly 40–50 seconds of tests per guard. At 266 guards it is inherently multi-hour and must not be repeated unchanged.

## 5. Root causes and key findings

- The sweep is honest about interruption: it writes the JSON only after all mutations finish, every file is byte-identically restored, and the suite is green again.
- Its serial execution model is operationally unacceptable. A replacement needs bounded parallel workers in isolated copies/worktrees plus checkpoint/resume, while retaining the full suite for every survivor and a final clean baseline.
- Detached Windows descendants launched by the command tool are not durable across command-channel resets on this host.
- Partial output showed real survivors, but interruption means those observations are diagnostic only, not publishable evidence.

## 6. Exact next steps

1. Confirm `git status --short` has no modified guard script and no `.ai-1223-*` temporary file. Success: only the committed branch state and this handoff are present.
2. Modify `scripts/mutation_sweep_guards.py` to support checkpoint/resume and bounded parallel execution in isolated worker directories. Do not let workers mutate the same checkout. Success: an interruption can resume without repeating completed guards and source digests remain unchanged.
3. Add focused tests for checkpoint integrity, worker isolation, result merging, interrupted-worker recovery, and final baseline refusal. Success: each safety control has a test that fails when disabled.
4. Run the full seven-file sweep with a declared hard wall-clock limit and visible progress. Success: JSON reports all 266 guards, all source digests match, and the final suite is green.
5. Group survivors by owning file/function and business risk; create one `db-work` issue per coherent group with `work_type: repo-maintenance`, `route: repo-maintenance`, and parent #1223. Success: every survivor appears exactly once across child issues.
6. Commit only the tool, its tests, and JSON; push, open a PR, complete required checks and governed exact-head review, then use the guarded merge workflow. Success: PR is merged and #1223 is closed with merge evidence.
7. Stop. Per Albert's instruction, do not take another queue issue in this session.

## 7. Constraints and gotchas in force

- Check `git worktree list` and each issue route before touching it.
- Never publish partial survivor results.
- Never disable or narrow the guards or tests to make the sweep fast.
- Code changes require normal checks, independent governed review, and guarded merge; admin merge is not a substitute.
- Keep the canonical checkout landing-only and use this dedicated worktree.
- Take no new issue after #1223.

## 8. Access and environment

- Host: `edge-dev`; PowerShell, Python 3.13, Node 24, GitHub CLI authenticated as `u2giants`.
- Repository worktree and branch are listed in section 3.
- No secrets, credentials, database connections, production reads, or database writes were used.

## 9. Open questions and risks

- The correct worker count must be bounded by host capacity; excessive parallelism could make test timing unreliable. Start conservatively and measure.
- A final report is valid only if it accounts for all 266 guards and passes restoration plus final baseline checks.
- Do not infer the survivor list from this session's partial console output.

## Self-audit

1. Yes: sections 1–3 define the repository, goal, exact branch, commit, and unfinished state for a newcomer.
2. Yes: sections 4–5 preserve every failed launch mode, why it failed, and the serial-runtime root cause.
3. Yes: sections 6–9 give ordered actions, success gates, constraints, environment, and risks; no deploy or database action is falsely claimed.
4. Yes: a line-by-line sweep of sections 1–9 found only the already-raised queue decisions, all consolidated in section 0; #1223 itself needs no new owner ruling.
