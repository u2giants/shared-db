# Non-orchestrator issue queue — five pull requests open, none merged yet

- **UTC written:** 2026-09-04T03:30Z
- **Machine:** EDGE-DEV
- **Agent:** claude (Opus 5), worktree `shared-db-open-issues-c01c25`
- **Continuation issue:** #2252
- **Predecessor handoff:** `HANDOFF.d/2026-09-04T0045Z-edge-dev-codex-non-orchestrator-zero.md` (codex; leave it alone, it is not mine)

## 1. Owner instruction (verbatim, still in force)

> "let's go through all the open shared-db Issues on github.com that are NOT for
> the orchestrator and complete them all through to production. don't stop until
> this session gets too long, then stop and tell me to hand over to a new session."

Settled scope, recorded 2026-09-03: continue until zero open non-orchestrator
issues remain, prioritising downstream blockers, then oldest work. This session
reached its length limit; Albert asked for a wrap-up and a fresh session.

## 2. State right now

Everything below is pushed. Working tree clean. Nothing is half-written on disk.

| PR | Issue | Head | Where it stands |
|----|-------|------|-----------------|
| #2260 | #2207 persist refused-review output | `54ae87d9d83d8a80de8e535982c070f7804f03cc` | glm-5.3 slot 1 assigned and LIVE. An APPROVE exists at the OLD head `55fd906c…` and is spent. The re-review at the current head **failed on a local transport fault**, not a reviewer fault. Re-run it. |
| #2261 | #2116 freeze revokes authorizations and never restores | `a4e9e26ff4130ed970b7c6d15dd90c9edcfe0ad4` | Revised. All four real REVISE findings fixed and the guard proven able to fail. Needs a FRESH review at this head; the REVISE at `e7469651…` is spent. No reviewer assigned. |
| #2264 | #2037 refuse edits to already-applied migrations | `b79d2518cff246f11f698598b53cb90ae3bcef4f` | Both red checks addressed this session (see §4). Checks re-running. Then review, guarded merge. |
| #2265 | #2029 superseded catalog contracts | `dcf9f216890f92025183c3bc724922d193285764` | Opened, checks not yet inspected. No reviewer. |
| #2266 | #2106 replacement blocked by an unrelated lease | `8bb65bfaaed3e9e0ee2525798c553b6f3d56e2fe` | Opened, checks not yet inspected. No reviewer. |
| #2245 | #2157 verdict unknown | `6b2d08ba0808…` | Codex-authored. `Cross-PR object collision` red. GLM and Codex are durably excluded for this PR, so it needs grok or muse. |

**Reviewer pool is the binding constraint.** Effective roster is three:
grok-4.6 (`ai-grok-review`), glm-5.3 (`ai-glm`), muse-spark-1.2-contributor
(`ai-muse`). codex-gpt-5.6-sol is structurally dead (#2244); deepseek fabricates.
At the moment all three are held: grok on 2228, glm on 2260, muse on 2200 for
9+ hours. 2228 and 2200 are the structural orchestrator's work — do not touch them.

## 3. What was completed this session

- **#2029** implemented and shipped as PR #2265. Catalog contracts may now declare
  `superseded_by`; the design decision is that supersession must be DECLARED
  because `CATALOG_CONTRACTS` carries no machine-readable subject, so "the last
  contract touching each object" is not derivable. It fails closed on every
  malformed declaration. 169 Python tests pass.
- **#2106** implemented and shipped as PR #2266. A failed reviewer holding an
  UNRELATED live lease no longer blocks its own replacement. The safety argument:
  a reviewer holds at most one active lease, so a lease naming different work
  PROVES the failure's own lease was already released. 426 JS tests pass.
- **#2116** revised after a REVISE verdict: the restore step now also runs when
  the revoke step FAILED (partial damage was previously never repaired), compares
  the FULL marker description instead of a run-id substring, and fails the step
  when the status cannot be READ instead of printing "left as-is".
- **#2037** two red checks diagnosed and one fixed (§4).

## 4. The two red checks on #2264, and what I learned

- **`Tools offline tests`** — nothing to do with the network. The new guard file
  contains a comment with the phrase "not applied", and the throughput truth
  audit discovers call sites by regex across `scripts/` and `.github/workflows/`.
  The inventory moved 235 → 236 and the audit failed closed. Fixed by recording
  an `excluded` disposition for `scripts/check-applied-migration-edit.mjs:35`
  and recomputing the count and digest.
  `node scripts/check-throughput-truth-audit.mjs` now prints
  `truth audit OK: call_sites=236`.
  **Lesson worth keeping: any new script whose prose contains "missing",
  "never created", "not applied" or `NOT_DERIVABLE` moves this inventory.**
- **`Cross-PR object collision`** — failed on `git cat-file -e 46f281ac…` for a
  commit that is not the head of any currently open PR. It was an open PR's head
  at 02:46 and was force-pushed away mid-run. This is a RACE in the guard, not a
  defect in #2264, and #2245 is red for the same reason. A re-run should pass.
  If it recurs, the guard needs to tolerate a head that vanished between listing
  and fetching — that is a separate issue worth filing.

## 5. Traps this session hit — do not re-learn these

- `run-governed-review.mjs --worktree <path>` requires the path to ALREADY EXIST,
  checked out detached at the exact PR head. Create it with
  `git worktree add --detach <path> <head-sha>` first, or the run REFUSES instantly.
- `ai-glm` / `ai-grok-review` exist only as `.cmd` shims in
  `C:/Users/ahazan/.local/bin`. They are not callable from the Bash tool directly;
  the review runner finds them, but a manual `ai-glm abort` must go through PowerShell.
- A REFUSED round with an empty stdout and a stderr about the "local permission
  endpoint" is a transport fault. Do NOT mark the reviewer failed or replace it —
  just re-run. Replacement burns a scarce reviewer.
- The main-tip freshness rule and the exact-head approval rule fight each other.
  Run update-from-main, review, and guarded merge back to back with no gap.
- Windows Python cannot read git-bash `/tmp` paths. Use the session scratchpad.
- Editing a file by reading and rewriting its text silently converts CRLF to LF
  across the whole file. This repo is CRLF. Patch at byte level.

## 6. Exact next actions, in order

1. Re-run the #2260 review at `54ae87d9…`. glm-5.3 already holds the slot, so no
   new assignment is needed. Create a detached worktree at that head first, then
   run `scripts/run-governed-review.mjs` with `--issue 2207 --pr 2260
   --head-sha 54ae87d9d83d8a80de8e535982c070f7804f03cc --reviewer glm-5.3
   --wrapper ai-glm --review-slot 1` and a fresh wrapper session name.
2. On APPROVE, dispatch the guarded merge IMMEDIATELY (main moves and voids
   verdicts): `gh workflow run guarded-migration-merge.yml --repo u2giants/shared-db
   -f pull_request=2260 -f head_sha=54ae87d9d83d8a80de8e535982c070f7804f03cc`,
   then close #2207 and free glm for #2261.
3. Confirm #2264's checks are green, then review and merge it, then close #2037.
4. Inspect checks on #2265 and #2266, review, merge, close #2029 and #2106.
5. #2245 needs grok or muse; both are on orchestrator work, so it waits.

## 7. Remaining queue after those

#2043, #2140 (deferred, priority 300), #1984, #1868, #1663, #1403, #1322, #1223,
#1201, #1090, #810, #770 (blocked by #771), and #2263.

**Owner-gated — do not guess these away:** #1941 (Laura and Ilona's dated review),
#1031 (Albert's ColdLion question), #771 (production Cloud SQL table data needs
new explicit authorization from Albert).

## 8. Terminal condition

Close #2252 and delete THIS file only when a live GitHub query and
`node scripts/manage-migration-author-lanes.mjs --queue-audit` BOTH return zero
open non-orchestrator issues.

## 9. Risks

- Reviewer starvation is the real schedule risk, not implementation time. Review
  ONE pull request at a time; two concurrent ones exhaust the pool of three.
- Five open PRs all touch guard scripts and the migrations workflow. Merge order
  matters: each merge moves main and can void the others' verdicts. Merge one,
  then update the next from main, then review it.
