# Issue #1015 forward-test evidence

Date: 2026-08-14

The deterministic queue builder was exercised with fresh synthetic issue sets,
not production database state:

- Two issues writing the same exact table remain in one serial queue.
- Three unrelated object groups produce three immediate refill candidates.
- An open dependency prevents dispatch.
- `blocked`, `owner-decision`, `data-only`, and `non-structural` issues consume no lane.
- An unclassified open issue prevents the orchestrator from claiming that an
  empty lane is justified.
- Existing cross-process tests still admit exactly three unrelated authors and
  exactly one of two authors claiming the same object.
- The external-review cursor advances Grok → GLM → Kimi → Qwen → Grok, returns
  the same assignment on retry, and refuses a concurrent orchestrator that does
  not own the shared lock.

Proof command:

```powershell
node --test scripts/manage-migration-author-lanes.test.mjs scripts/check-dispatch-collision.test.mjs
```

Result: 103 passed, 0 failed. No database, preview, merge, or production call was
made by this forward test.
