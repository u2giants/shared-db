---
issue: 2252
status: OPEN
owner: codex/session-closeout-2252
---

# 0. Decisions only the owner can make

## Blocking

- Issue #1941 requires Laura and Ilona to review and sign off every licensed Property before the controlled ColdLion reconciliation. Recommendation: keep it open until their dated review exists; do not let an AI infer those business decisions.
- Issue #1031 still needs Albert to send the already-written ColdLion question and decide how far back history should be pulled. Recommendation: send the existing draft and use the earliest supported source date once ColdLion answers; this blocks building the historical puller correctly.
- Issue #771 may not read production Cloud SQL table data or run a direct dump without a new, explicit authorization naming that action. Recommendation: authorize only when ready to schedule the measured rehearsal; catalog-only reads remain permitted.
- Production deployment of DB Data Admin after PR #2166 merges is already authorized by issue #2169. No new approval is needed, but production verification must remain read-only and must not submit Property decisions.

## Already settled; do not re-ask

- 2026-09-03: Kimi is out of credits for 16 hours. Use only Muse Spark Contributor, Grok 4.6, and GLM 5.3 during that window. The repository currently calls Muse `muse-spark-1.2-contributor`; use that exact governed identity rather than inventing a 1.3 identifier.
- 2026-09-03: continue until zero open non-orchestrator issues remain, prioritizing downstream blockers and then oldest work.
- Password/API-key rotation was not required. A short-lived Microsoft/Supabase browser session token was exposed in tool output; all 10 related sessions and refresh tokens were revoked and zero remained.

Put the whole blocking list to Albert in one message if any item becomes the next executable blocker. Do not ask piecemeal.

# 1. What this application is

`u2giants/shared-db` is the governed source for shared Supabase structure and the DB Data Admin application at `https://data.designflow.app/`. This workstream is the separate repository-maintenance queue, explicitly outside the structural orchestrator. Changes ship through branches, pull requests, exact-head independent review, the guarded merge workflow, and deployment/live proof where applicable.

# 2. What this session set out to do

The owner asked for every open shared-db issue that is not orchestrator work to be checked for staleness or supersession, then completed in blocker-count order and oldest-first when no dependency dominates. The terminal condition is zero open non-orchestrator issues. Issue #2252 exists solely to carry this unfinished sweep across sessions.

# 3. Current state

## Completed and verified this session

- Closed as completed, stale, superseded, or safely resolved: #1258, #1993, #1995, #620, #2048, #1789, #508, #519, #880, #943, #1285, #1690, #1353, #1158, #1161, #1182, #1286, #1356, #1689, #2078, #2209, #1224, #2030, #1994, #1851, #1391, #1435, #640, #696, #1693, #2075, #2076, #2117, #2066, #2069, #2084, #2167, #2131, #2148, #2163, #2217, #2162, #1833, #2011, #2164, #2081, #870, #2046, #2208, #2161, #2189, #2044, and #2141.
- PR #2241 merged as `a7ad21fc81d37d1646a1c120134f1aa55f9e650a`; #2044 closed. Its old branch was proved patch-equivalent to main and deleted.
- PR #2246 merged as `e74f47c8f930990f4c7805f738ecb9743ce6976d`; #2141 closed. Final evidence: 56/56 targeted tests, all GitHub checks, exact-head governed GLM approval.
- Earlier material merges in this sweep include PR #2234 (`fe822fef64a444f1c924c3e8dea7799e439bc37c`), PR #2221 (`b58fda1f270a167690c7311e0086f4a1fa43bbc0`), PR #2239 (`8a57adc5de8a25d9f2f6aba4a2324ba936d50009`), and PR #2240.

## Active PR #2166 / issue #2169 — finish first

- Worktree: `C:\repos\shared-db-worktrees\issue-2169-autocomplete`
- Local branch: `codex/issue-2169-autocomplete`; PR branch: `codex/property-match-autocomplete`
- Exact head: `ede4c1685a7af38df680f648feb0717b6c99fae9`; exact base at review: `da92706383f8a6484d02f7ef82e539f9d2f6342e`.
- Grok correctly rejected the earlier head because multi-candidate suggestions disappeared. The fix now preselects every recorded candidate as a removable chip, updates the instruction, and tests display, removal, re-addition, and final payload.
- Verification passed locally: 134 tests, production build, lint. Governed GLM exact-head approval recorded at `refs/db-review-verdicts/2169-2166-ede4c1685a7af38df680f648feb0717b6c99fae9`.
- GitHub `verify` and ephemeral database jobs passed. At handoff time only DB Data Admin workflow run `33822426828`, job `container` (`100869033800`), remained in progress.
- After all checks pass and the base still equals current main: run `guarded-migration-merge.yml` for PR #2166/head above; then dispatch the documented DB Data Admin production workflow from the merge commit, verify `https://data.designflow.app/#` reports that build, and verify Property Matches loads the full Disney autocomplete without submitting a decision. Close #2169 only after live proof.

## Active PR #2245 / issue #2157

- Worktree: `C:\repos\shared-db-worktrees\issue-2157-verdict-unknown`
- Branch: `codex/issue-2157-verdict-unknown`
- Exact current head: `6b2d08ba0808eef196bd2a68edf6cf713175a8e2`; base at push: `e74f47c8f930990f4c7805f738ecb9743ce6976d`.
- Change: an unreadable durable-review verdict is reported as `unknown`, with `verdictPresent:null` and `verdictReadError`, rather than falsely as “no verdict.” Documentation and the ambiguous-slot comment were corrected.
- Full coordination suite passed 425/425 after the last rebase.
- GLM reviewed earlier heads twice and found the issue change correct, but emitted output that the governed recorder could not accept. GLM and Codex are durably excluded for this PR; wait for Grok or Muse capacity, assign a reviewer to the current exact head, and use the strict terminal line format required by `scripts/run-governed-review.mjs`.
- Before review, compare PR base/head to current main. Rebase and rerun 425 tests if main moved. Merge through the guarded workflow and close #2157.

## Remaining audited non-orchestrator queue

The last current-main audit had 22 valid entries, zero malformed, zero unlabelled: #2169, #2140, #2124, #2116, #2106, #2043, #2037, #2029, #2014, #1984, #1941, #1868, #1663, #1403, #1322, #1223, #1201, #1090, #1031, #810, #771, #770. Add #2157 and continuation #2252 when reconciling; the audit unexpectedly omitted open #2157 despite its `db-work` label, so inspect and normalize its one-line scope block if it remains invisible.

Priority after #2169/#2157: #2014 and #1090 are priority 1000; #1201 is 700; #1031/#810 are 600; #1223 is 550; #770 is blocked by #771. Re-run the audit after each merge because the structural orchestrator moves main frequently.

# 4. What did not work

- Do not call Kimi: owner says its credits are exhausted for 16 hours.
- The reviewer manager sometimes assigns Codex first. Do not run it; use `--exclude-reviewer ... --reason terminal-unavailable` with the exact assignment SHA, then redraw.
- GLM twice returned substantive approval for #2157 but did not end with the recorder's exact `VERDICT: <decision> <40-char-head>` line. Those reviews are evidence only, not authorization. Prompts must explicitly require exactly one terminal verdict line and no decision-word line elsewhere.
- Review packets sometimes showed unrelated main-side files because their local merge-base metadata was stale. Pin the exact base/head and instruct the reviewer to judge only `git diff <base>...<head>`.
- A first local test command used a nonexistent test path; the correct files are `scripts/manage-migration-author-lanes.test.mjs` and `scripts/check-sql.test.mjs`.
- Running workspace npm commands from the repository root failed because the root has no package manifest; run them from `apps/db-data-admin`.
- During PR #2166 recovery, a command was issued from the audit worktree rather than the new PR worktree and temporarily force-pushed current main to the PR branch, closing the PR. The original commit remained locally, was immediately rebased correctly, force-pushed back, and PR #2166 was reopened with no content loss. Always set the workdir to `issue-2169-autocomplete` before touching that branch.
- Root checkout is dirty with other sessions' untracked material and has a local unpushed commit. Do not reset, clean, stage, or commit there.

# 5. Root causes and key findings

- Reviewer approval is valid only for exact head and current base. Structural orchestrator merges repeatedly invalidated otherwise-green reviews; always re-resolve both immediately before guarded merge.
- `scripts/run-governed-review.mjs` accepts exactly one terminal line matching `VERDICT: APPROVE|REVISE|REJECT <exact 40-char SHA>` and refuses extra standalone verdict lines.
- #2157's bug was a truthfulness failure: a read error became `false`, making unknown state look safe. The fixed report preserves other reviewer rows and counts the unreadable row as unknown.
- #2169's real UI bug came from `defaultSelection` returning empty for multiple candidates while the new UI rendered only selected chips. Preselecting every recorded candidate restores visibility but still requires an explicit reason and confirmation.
- The current audit's remaining issues are genuine mixes of code, live verification, documentation trackers, and human gates. Do not close a tracker merely because one phase merged; verify its stated completion evidence.

# 6. Exact next steps

1. Poll DB Data Admin run `33822426828`. Gate: `verify` and `container` both succeed and PR #2166 shows no failing/pending required checks.
2. Re-resolve PR #2166 head/base and current main. If base moved, rebase, rerun 134 tests/build/lint, push, and obtain a fresh governed review. Gate: exact head approval and base equals main.
3. Run guarded merge for #2166. Gate: PR state is MERGED and merge commit is on main.
4. Dispatch the documented DB Data Admin production workflow using the merge commit and production confirmation. Gate: production workflow succeeds for that SHA.
5. Perform read-only live UI verification at `https://data.designflow.app/#`: deployed build matches, Property Matches loads full Disney options, multi-candidate suggestions are visible/removable, and no decision is submitted. Gate: observable live behavior matches.
6. Close #2169 with merge, deployment, and live evidence.
7. Rebase PR #2245 onto current main if needed, rerun `node --test scripts/manage-migration-author-lanes.test.mjs`, draw Grok or Muse when free, and run governed exact-head review. Gate: create-only approval artifact exists.
8. Guarded-merge PR #2245 and close #2157. Gate: merged commit on main and issue closed.
9. Rerun `node scripts/manage-migration-author-lanes.mjs --queue-audit`, normalize #2157/#2252 visibility, and work remaining issues by transitive blocker count, then priority/age. Gate: every pass records current counts and never reports malformed/unlabelled issues.
10. Close #2252 and delete this handoff in the same final documentation change only when the audit proves zero open non-orchestrator issues. Gate: live GitHub query and queue audit both return zero.

# 7. Constraints and gotchas

- This session is not the structural orchestrator. Do not accept or implement structural issues.
- Use only Muse Spark Contributor, Grok 4.6, and GLM 5.3 during Kimi's outage. The durable roster name for Muse is currently `muse-spark-1.2-contributor`.
- Exact-head review becomes stale after every rebase or push. Green tests do not substitute for review; review does not substitute for checks or live deployment proof.
- Use isolated worktrees. Preserve the dirty root checkout and other sessions' files.
- No production database write is authorized by this sweep. Production app deployment for #2169 is authorized; live verification is read-only.
- Documentation-only PRs may be merged immediately after confirming all changed files are prose. Code/config/workflow PRs require normal gates.
- Do not expose secrets in commands, logs, commits, issues, or handoffs. Use 1Password vault `vibe_coding` for durable secret references.

# 8. Access and environment

- Machine: EDGE-DEV, Windows PowerShell.
- GitHub CLI is authenticated as the `u2giants` owner and can read/write issues, PRs, workflows, refs, and branches.
- Reviewer wrappers available through the governed adapter: `ai-grok-review`, `ai-glm`, and the Muse wrapper selected by the manager. Do not call reviewers outside the governed adapter for merge authorization.
- DB Data Admin URL: `https://data.designflow.app/`.
- Browser authentication may need normal Microsoft sign-in; never copy tokens into chat or files.
- Secrets belong in 1Password vault `vibe_coding`; no new password or API key was created or rotated.

# 9. Open questions and risks

- Reviewer capacity is shared with the active structural orchestrator and can be temporarily unavailable. Wait or work another issue; do not steal or fabricate a lease.
- `main` changes frequently. A review that finishes after main moves must be refreshed even if content did not change.
- #2169 still lacks live production proof until the deploy and authenticated UI check complete.
- #1941, #1031, and production-data portions of #771 are genuine human/authority gates listed in section 0; do not silently guess them away to reach zero.
- Several large remaining trackers may be partly completed by newer merges. Reassess each against current evidence before implementing or closing.

## Final self-audit

1. Yes: sections 1–3 define the application, goal, exact branches, SHAs, PRs, checks, and remaining queue; section 6 gives executable continuation gates.
2. Yes: sections 4–5 preserve the failed commands, reviewer-format failure, worktree mistake, root-cause discoveries, and exact recovery knowledge needed to continue at current effectiveness.
3. Yes: sections 0–9 cover background, goals, current state, failures, findings, decisions, constraints, risks, access, exact actions, and verification evidence. No secret values are present.
4. Yes: a line-by-line sweep of sections 1–9 found owner judgement only for #1941, #1031, #771 production-data access, #2169 deployment authority, Kimi/reviewer choice, and the zero-issue terminal condition; every one appears in section 0 with a recommendation or settled instruction.
