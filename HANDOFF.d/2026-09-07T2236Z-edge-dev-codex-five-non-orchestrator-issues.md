---
issue: 1090
status: OPEN
owner: codex/five-non-orchestrator-issues
---

# HANDOFF — five non-orchestrator issues (2026-09-07 22:36 UTC, edge-dev/codex)

## 0. ⚠️ DECISIONS ONLY THE OWNER CAN MAKE

Put this whole list to Albert in one message before resuming work; do not raise the items one at a time.

### BLOCKING

1. **Disney OPA capture authorization for #1090.** Albert must sign in to `https://opa.disney.com` in Chrome, complete MFA, and explicitly authorize both OPA downloads. Recommended exact reply: **“Signed in, and you may download both OPA captures.”** This blocks the private source capture that feeds the remaining licensing chain. Never enter credentials, bypass MFA, or infer permission.
2. **Keep these five issues or reselect for speed.** The requested set was #2477, #2481, #1090, #1322, and #1403; two are closed, while the other three are gated by elapsed time, curated Master Data, and human decisions. Recommendation: if the business goal is five prompt closures, replace the three gated items with the next highest-impact eligible non-orchestrator issues; otherwise preserve this set and accept that it cannot finish immediately.

### RECOVERABLE

None.

### NOT PART OF THIS WORK, AND NOBODY IS ON IT

None discovered. The 14 stale tracked handoffs named in §9 are repository housekeeping owned by their successor workstreams; this session did not delete another session's files.

### Already settled — do NOT re-ask

- 2026-09-07: #2477 and #2481 are closed with their required evidence.
- 2026-09-07: #1403's 24-hour observation clock restarted at `2026-09-07T21:26:45Z`; no earlier observation counts.
- 2026-09-07: #1322 must not close until curated issue #2541 has target-pinned before/after proof for all 66 approved property codes.
- 2026-09-07: #1090 is an umbrella tracker. Do not dispatch or implement it as one task; follow its current successor chain.
- 2026-09-07: the #2550 reviewer-budget repair must not merge before #2509/PR #2513 completes production, because the touched producer file participates in #2509's immutable evidence identity.

## 1. What this application is

`u2giants/shared-db` is POP Creations' governed source of truth for the structure and shared contracts of the Supabase database used by PM/PIM, CRM, DAM, and DesignFlow. GitHub issues coordinate database-structure work, curated Master Data, and repository-maintenance work. One marked orchestrator handles structural work; repository-maintenance issues must be completed by separate sessions in isolated worktrees. The local repository is `C:\repos\shared-db`; GitHub is `https://github.com/u2giants/shared-db`.

This handoff covers a business request to close the five non-orchestrator issues that block the most other issues, with oldest-first tie-breaking. It also records repository-maintenance issue #2550, which this session discovered and repaired while trying to unblock the selected set.

## 2. What we set out to do this session, and why

The requested set was #2477, #2481, #1090, #1322, and #1403. The intended outcome was genuine closure of all five, including reviews, merges, deployments, elapsed-time gates, and live evidence—not merely code preparation.

The session closed #2477 and #2481. It advanced #1322 and #1403 to their remaining hard gates, mapped #1090's current chain, and diagnosed a repository defect that prevented the orchestrator from drawing a replacement reviewer for #2509. That defect became #2550 and PR #2551. Albert later correctly challenged the elapsed time: the selected set contains gates that no amount of polling can compress. He then requested session closeout, so no new issue was started after scope freeze.

## 3. Current state — what is true right now

### Selected issues

- **#2477 CLOSED.** ColdLion's item loader no longer discards a stated licensor when the property slot is blank. GitHub was rechecked live at closeout.
- **#2481 CLOSED.** PM products are linked to the canonical item master. GitHub was rechecked live at closeout.
- **#1090 OPEN.** This is the licensing Master Data umbrella tracker. Its active successors are #2356, #2357, #2336, and #2358; all were open at closeout. #1941 is also open and its 2,880 business-decision cells remain for Laura and Ilona rather than an AI inference. Private source prerequisite PR #65 in `licensor-source-data` previously merged as `81281710`; the Disney OPA capture still needs Albert's login/MFA and explicit authorization described in §0.
- **#1322 OPEN.** The user-facing application work is complete: PR #2514 merged as `85015041` and production deployment run `34144596689` completed with authenticated UI proof. The remaining 66 owner-approved ColdLion property admissions are governed curated Master Data issue #2541, which was still OPEN and had no completed worker/write evidence at closeout. Do not close #1322 without target-pinned before/after aggregate proof. A local recovery branch `codex/issue-1322-status-only` was deliberately retained because it differs from the final narrow merged PR.
- **#1403 OPEN.** Activation PR #2539 merged as `4f093e3d4c97e4272d147d38e7243ec57d3c08f1`; inherited-evidence repair PR #2547 merged as `b3219f73c0a111bf06889d490cdc398c9ca1018c` at `2026-09-07T21:26:45Z`. The first post-repair live sample passed in PR #2513 run `34163486614`. The required new uninterrupted 24-hour green window cannot end before `2026-09-08T21:26:45Z` (5:26 PM ET). The legacy `objects:` alias cannot retire while legacy claims remain; the last audit named #2521, #2443, #2451, #2511, and expired-unconfirmed #2418. Re-resolve all of them live before acting.

### Reviewer-budget repair discovered during the work

- **Issue #2550 OPEN; PR #2551 OPEN and mergeable.** Worktree: `C:\repos\shared-db-worktrees\issue-2550-review-budget`; branch: `codex/issue-2550-review-budget`; exact head: `a28e6397cd64f3733bbcaa2651eb900bb41b1c44`; base at branch creation: `b3219f73c0a111bf06889d490cdc398c9ca1018c`.
- Code changes are in `scripts/manage-migration-author-lanes.mjs:91` and `scripts/manage-migration-author-lanes.mjs:1344-1385`; the end-to-end bounded-chain regression is in `scripts/manage-migration-author-lanes.test.mjs:5140-5181` (re-resolve line numbers if the branch moves).
- Commits, oldest to newest: `7418717e`, `b3edb488`, `a83432c0`, `75ebc263`, `4586aae9`, `a28e6397`.
- Verification at exact head: 476 manager tests passed; 80 exact-head/governed-review tests passed; truth audit reported `call_sites=256`; agent-contract and git-evidence validation passed. At closeout, all 13 required substantive CI checks were green; the three production jobs were correctly skipped because this is repository tooling, not a migration.
- Independent Grok review approved `b3edb488` but found that the test undercounted a `listRefs` call. That finding was fixed in `a83432c0`; Grok then approved exact head `75ebc263` with durable verdict ref `refs/db-review-verdicts/2550-2551-75ebc263...` at object `1eff3f...`.
- Later evidence-only refreshes moved the head to `a28e6397`, so the older approval is not a current exact-head approval. A governed GLM run for `a28e6397` was interrupted by the user's closeout turn after about 10 seconds. No exact-head verdict ref existed at closeout. `refs/db-review-active/glm-5.3` still existed; never hand-delete it. No reviewer process remained after excluding the closeout inspection command itself.
- **Do not merge PR #2551 yet.** `scripts/manage-migration-author-lanes.mjs` is a preview-producing source for #2509/PR #2513. The live orchestrator required this order: review #2550; run the bounded real replacement-allocation acceptance from the reviewed branch; let #2509 finish its second review, guarded merge, and production proof; then merge #2550. PR #2513 was OPEN at exact head `d41287fc4e23152412c1617f40215b3821572e87` at closeout.

### Coordinator and automation

- `node scripts/check-orchestrator-marker.mjs --resolve` still resolved open marker #2536 to Codex route `01a07ceb-249b-7dc0-8f3a-ad5091e3a085` at closeout. That coordinator was itself closing and created handover issue #2552. Re-resolve the marker before any message; do not use this recorded route as current authority.
- The 30-minute heartbeat `finish-five-shared-db-issues` was changed from ACTIVE to PAUSED during closeout so a closed session will not continue waking. Its prompt and history were preserved.
- The canonical checkout `C:\repos\shared-db` was left untouched. It was 45 commits behind and contained pre-existing changes: modified `.mcp.json`, untracked queue-audit files, `.worktrees`, and two untracked older handoffs. None belong to this session.

## 4. Everything we tried that did NOT work

1. **Treating the originally selected five as same-day closures.** This was invalid because #1403 has a clock gate, #1322 has a governed curated-data gate, and #1090 has private-source and human-decision gates. Continuing to poll would consume time without changing the earliest completion date.
2. **First governed Grok invocation for #2550 used `diff-review`.** The Grok wrapper accepts named modes such as `new` or `ask`; it rejected this before producing a verdict. The corrected named session was `issue-2550-review-b3edb488` with `AI_GROK_CALLER=codex`.
3. **The first #2550 regression claimed the wrong request count.** Grok independently noticed that the fake transport failed to count a `listRefs` call. The test was repaired to measure the real wire path before the subsequent approval.
4. **A current-head GLM review did not finish.** The user invoked closeout while it was starting. The durable current-head verdict ref was absent afterward, so no approval was inferred and no synthetic verdict was posted.
5. **Merging #2550 as soon as CI turned green was rejected.** Although PR #2551 is mergeable and green, merging it before #2509 production would change the producer identity used by immutable preview evidence and could strand PR #2513.
6. **No manual release of reviewer refs.** The remaining GLM active ref was not deleted because durable reviewer state must be recovered only through the governed scripts.
7. **The first Kimi review of this handoff used an incorrect packet base.** Its packet claimed a 16-file diff from `b3bd8c5b...`, including unrelated #2530/#2537 work, while GitHub PR #2557 and local `origin/main...HEAD` both proved the actual PR diff was exactly the declared three files from base `2fd3b721...`. Its requested-changes verdict was not recorded by the governed wrapper because provider stderr made the terminal reason unrecognized. Treat the false 16-file finding as disproven, retain the valid finding about the shortened #2539 SHA (fixed here), and obtain a fresh exact-head review.

## 5. Root causes and key findings

1. **The delay was selection, not a slow implementation loop.** Three of five chosen issues were not immediately closable. The owner was right that 7.5 hours without five closures signaled the plan needed correction.
2. **#2550 root cause:** replacement allocation repeatedly re-read predecessor failure/replacement refs and spent beyond the fixed 25-request operation ceiling before mutex acquisition. The repair batches dependent failure refs in `readReviewRecords`, reuses proven absence from a complete active-lease snapshot for active/overflow reviewers, and retains direct reads for retired reviewers. The fixed ceiling is documented at `scripts/manage-migration-author-lanes.mjs:91`; it was not widened.
3. **The realistic worst path now fits.** The test models slot-1 approval plus a released slot-2 failure chain, a reinstated reviewer, exact replacement assignment, 23-call successful allocation, and a 22-call retry. It preserves safety refusals and serializes the mutex-held section.
4. **Exact-head review is evidence, not ceremony.** Any refresh commit invalidates an earlier exact-head approval. PR #2551 therefore still needs a current-head durable verdict despite prior approvals.
5. **#1403's clock was reset by a real defect repair.** Any observation before merge `b3219f73...` is invalid. The earliest valid completion time is fixed and must not be shortened.
6. **#1322's application capability and data completeness are separate gates.** The UI is live and proven, but the 66 curated records remain under #2541; business-flow completion requires both.
7. **#1090 must remain decomposed.** Dispatching the umbrella would duplicate or conflict with its successors. Disney OPA is private licensed source work; credentials and captured rows must never enter this public repository or outside-review prompts.

## 6. Exact next steps

1. **Ask Albert the two consolidated questions in §0.** You will know this is complete when he either authorizes both OPA captures and chooses to retain/reselect the gated three, or explicitly declines one or both.
2. **Re-resolve the orchestrator marker and issue #2552.** Run `node scripts/check-orchestrator-marker.mjs --resolve` from current `origin/main`. You will know it worked when one current open marker names a reachable route and that route acknowledges the message; if no marker is open, queue rather than dispatch.
3. **Resume #2550 without deleting refs.** Inspect the current PR #2551 head, all checks, the durable verdict namespace, and the GLM active lease through the governed tools. If head remains `a28e6397...`, recover or replace the interrupted reviewer only through supported commands and obtain a durable exact-head independent approval. You will know it worked when `refs/db-review-verdicts/2550-2551-a28e6397...` exists and validates.
4. **Run #2550's bounded live acceptance only after exact-head approval.** From the reviewed repair branch, execute the supported reviewer replacement for issue #2509, PR #2513, exact head `d41287...`; stop and re-derive if that head moved. You will know it worked when the replacement is allocated and the operation stays within 25 requests with durable state intact.
5. **Hand #2509 back to the current coordinator.** It must complete its second independent review, guarded merge, production apply, and target-pinned verification. You will know it worked when PR #2513 is merged, production evidence is current and green, and issue #2509 is legitimately closed.
6. **Only then finish #2550.** Rebase/refresh if required, repeat exact-head tests/review if the head changes, merge PR #2551, verify `main`, and close #2550 with the live allocation evidence. You will know it worked when the merge commit is on `origin/main`, CI is green for that exact merge, and issue #2550 is closed.
7. **Advance #1403 no earlier than `2026-09-08T21:26:45Z`.** Verify the entire post-repair 24-hour window is green, add the required branch context, and re-audit every legacy claim. Retire the alias only when the live legacy count is zero. You will know it worked when enforcement remains active, the full window is proven, the alias is absent only after zero legacy claims, and #1403 closes.
8. **Advance #1322 through #2541.** The fresh curated worker must prove the database target, load only the 66 owner-approved codes, and capture before/after aggregate proof. You will know it worked when #2541 closes with target-pinned evidence and #1322's authenticated business flow is reverified and closed.
9. **Advance #1090 by successors, not as an umbrella.** After explicit OPA authorization, use the private source-data workflow for both captures; keep licensed evidence private. Resolve #2356 before #2357, then #2336 and #2358 as their live dependencies require, while #1941 waits for Laura/Ilona's actual rulings. You will know it worked when every successor acceptance gate is live-proven and #1090 closes without inferred business decisions.
10. **Retire this handoff only at genuine completion.** The successor that proves #1090 and the selected-set obligations complete should delete this file in that finishing PR after carrying forward any still-open obligation. You will know it worked when issue #1090 is closed and no unique decision or dead end would be lost.

## 7. Constraints and gotchas in force

- Start write-capable work in an isolated current-`origin/main` worktree. The canonical checkout is landing-only and dirty with other sessions' files.
- Re-resolve GitHub state, marker, claims, PR heads, checks, and evidence immediately before every action. This handoff is context, never live authority.
- Do not broaden, disable, bypass, or remove the reviewer capability to silence #2550. Keep the fixed 25-request ceiling and all safety refusals.
- Never hand-delete `refs/db-review-active/*` and never post a synthetic verdict. Use governed recovery/replacement commands.
- Do not merge PR #2551 ahead of #2509 production completion. This ordering is an evidence-preservation gate, not a preference.
- Do not count CI on an older SHA as exact-head proof. A changed head, base, producer identity, or evidence invalidates the gate.
- Do not shorten #1403's 24-hour window or infer a zero legacy-claim count. Verify both live.
- Do not write the 66 curated rows outside #2541's governed Master Data route. Prove the exact database target before every write.
- Do not enter Disney credentials, bypass MFA, download without explicit authorization, or expose licensed rows in this public repo, GitHub, logs, or outside reviewers.
- Do not dispatch #1090 itself. Work its current successors in dependency order.
- Do not edit or delete another session's `HANDOFF.d` file merely because its issue appears closed; successor retirement requires all three preservation checks.
- GPT-5.6 sessions use only low or medium reasoning. Commits must identify Albert Hazan `<u2giants@users.noreply.github.com>`.

## 8. Access and environment

- Machine: `edge-dev`; shell: PowerShell; local repo: `C:\repos\shared-db`.
- GitHub CLI was authenticated for `u2giants/shared-db`; live issue, PR, ref, and check reads succeeded during closeout.
- Repair worktree: `C:\repos\shared-db-worktrees\issue-2550-review-budget`; branch `codex/issue-2550-review-budget`; remote branch and PR #2551 exist. Keep both because the PR is unmerged.
- Secrets belong in 1Password vault `vibe_coding`; no secret values are recorded here. Production/shared-cloud access remains read-only unless Albert authorizes an exact mutation in the current chat.
- Disney OPA requires Albert's own Chrome login and MFA. The prior OPA sign-in tab was closed by the user; do not reopen or download until he authorizes it.
- The active orchestrator marker at closeout was #2536, but its session was closing. Always run the resolver again and require acknowledgement.
- Heartbeat automation `finish-five-shared-db-issues` is PAUSED, not deleted.

## 9. Open questions and risks

- **Owner choice:** preserve the original five or reselect the three gated issues; see §0. Without reselecting, completion time is determined partly by #1403's clock and human decisions.
- **OPA authority:** no Disney capture can begin until the exact authorization in §0 is received.
- **Reviewer leases:** the interrupted GLM active ref for PR #2551 may require governed recovery after its evidence-backed terminal state is established. Kimi sequence 1752 for PR #2557 produced an unrecorded requested-changes result from the wrong packet base; the next attempt must use governed recovery/continuation and independently verify the packet base. Never assume that an active ref means a live process, and never delete it manually.
- **PR #2513 drift:** its recorded exact head `d41287...` can change. If it does, discard the recorded replacement target and re-derive the full review/production sequence.
- **#1403 legacy claims:** the five recorded claims can close, move, or be recovered. Only a fresh live audit governs alias retirement.
- **#2541 ownership:** it was queued for a fresh curated worker, but no completed write or verification existed at closeout. A marked-busy item is not evidence of active work.
- **Stale tracked handoffs:** the closeout audit found 14 tracked handoffs whose contract issue is now CLOSED. They are:
  - `2026-08-14T2236Z-al8960ofc-claude-coldlion-history-endpoints.md` (issue #1031)
  - `2026-08-31T2340Z-edge-dev-claude-coldlion-reply-ready-to-send.md` (issue #1031)
  - `2026-09-03T1750Z-edge-dev-claude-orchestrator-2193-closeout.md` (issue #2218)
  - `2026-09-04T0030Z-edge-dev-claude-orchestrator-2224-closeout.md` (issue #2247)
  - `2026-09-04T0129Z-edge-dev-claude-coldlion-reply-20260903-ready-to-send.md` (issue #1031)
  - `2026-09-04T0310Z-edge-dev-codex-priority-orchestrator-cutover.md` (issue #2267)
  - `2026-09-04T1103Z-edge-dev-codex-priority-orchestrator-2269-closeout.md` (issue #2283)
  - `2026-09-04T1108Z-edge-dev-codex-post-cutover-closeout.md` (issue #2267)
  - `2026-09-04T1625Z-edge-dev-2-claude-orch-2297-closeout.md` (issue #2297)
  - `2026-09-04T2010Z-edge-dev-codex-unauthorized-orchestrator-handover.md` (issue #2317)
  - `2026-09-06T0030Z-edge-dev-claude-orchestrator-2330-closeout.md` (issue #2400)
  - `2026-09-06T1330Z-edge-dev-2-claude-orch-2404-closeout.md` (issue #2432)
  - `2026-09-07T0620Z-edge-dev-claude-orchestrator-blocker-issues.md` (issue #2494)
  - `20260906T205200Z-edge-dev-shared-db-orch-5e0e7c81-orchestrator-closeout.md` (issue #2469)
  This session did not delete them because it did not perform the successor-rule audit for their unique obligations and decisions.
- **Canonical checkout risk:** it is behind and dirty with pre-existing work. Do not pull, clean, stage, or overwrite it as part of this continuation.

### Mandatory self-audit results

1. **Yes, a brand-new developer can continue without asking this session a question.** Sections 1–3 establish the application, goal, exact live state, branches, SHAs, gates, and unfinished work; §6 gives an ordered executable continuation.
2. **Yes, the handoff carries all session knowledge needed to continue as effectively as this session.** Sections 4–5 preserve the failed reviewer invocation, test-count correction, interrupted review, selection mistake, causal diagnosis, and sequencing discovery.
3. **Yes, every required execution dimension is present.** Background and outcome are in §1–2; current state and evidence in §3; failures in §4; findings in §5; exact verified next actions in §6; constraints, access, and risks in §7–9. Commit, push, CI, review, deploy, and non-deploy states are explicit. No gap remained after rereading.
4. **Yes, Albert can read only §0 and see every decision needed from him.** The line-by-line sweep of §1–9 found two owner judgements: Disney OPA authorization and whether to retain or reselect the three hard-gated issues. Both are in §0 with recommendations and consequences. Laura/Ilona's #1941 rulings are explicitly not decisions for Albert or the implementing AI; all other “owner” references are settled constraints, listed under “Already settled—do NOT re-ask.”
