# Shared-db merge queue operation

Issue [#1435](https://github.com/u2giants/shared-db/issues/1435) replaces the first-come-first-served
merge race with GitHub's native merge queue. This is repository maintenance; it changes no database.

## Safety contract

- GitHub builds and merges one pull request at a time (`ALLGREEN`, build 1, merge 1, method `MERGE`).
- The reviewed pull-request head is immutable. The queue tests a separate synthetic commit containing
  that exact head plus current `main`; queue admission is revoked when the PR head moves.
- Migration PRs enter in ascending reserved-version order. A later reservation cannot jump an older
  open non-draft migration PR. Guard B then rechecks ordering on the synthetic queue commit.
- `guarded-migration-merge.yml` validates and queues; it does not merge. GitHub is the sole merger.
- After a migration merges, the next queue check waits for the bounded preview workflow to mark that
  exact `main` SHA `Post-merge preview rehearsal: success`. A non-migration merge does not need this.
- Every old required check runs for `merge_group`. Checks whose PR-only payload is absent defer their
  event-specific operation to `Merge queue gate`, which resolves the one PR from GitHub's queue ref,
  verifies it independently through the live PR API as open and targeting `main`, and fails closed on
  malformed or contradictory identity.

The queue does not make prose review evidence stronger than it was before #1435. The durable reviewer
assignment and verdict remain exact-head evidence governed by AGENTS.md §4. Queue admission continues
to require the operator to supply that exact reviewed head; the queue proves that the head did not move.

## Activation sequence

Activation must happen only after the implementation PR is merged and green on `main`:

1. Add `Merge queue gate` to required contexts with the existing additive-only
   `scripts/update-required-checks.mjs` tool. Preserve all existing contexts and `strict: false`.
2. Run `node scripts/configure-merge-queue.mjs`. Its default is a read-only dry run and it refuses if
   the workflow or required contexts are not live.
3. Save the dry-run JSON as the settings backup/evidence, then run the same command with `--apply`.
4. Read back the ruleset and branch protection. No required context may disappear and `strict` must
   remain false.
5. Queue one harmless non-migration pull request. Prove all required `merge_group` checks ran on the
   synthetic SHA and GitHub alone performed the merge.
6. Queue the next suitable migration only after its exact-head review. Prove it merges once, preview
   rehearses the exact merge SHA, and only then can the following queue group pass.

Do not activate the ruleset from the implementation branch: GitHub would request `merge_group` checks
from `main`, where the workflows do not exist yet, and the queue would correctly deadlock.

## Rollback

Disable or delete only the repository ruleset named `main merge queue`; do not remove required checks,
change `strict`, or weaken the guarded workflow. The pre-queue guarded workflow can be restored from the
commit immediately before #1435 if a platform defect requires rollback. Record the exact ruleset JSON
before any settings write so the operation remains recoverable.
