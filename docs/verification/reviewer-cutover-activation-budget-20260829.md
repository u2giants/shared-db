# Reviewer cutover activation - request budget and sequencing

Issue: #1798. PR: #1799. Scope: repository coordination only; no database,
preview, production, or application data changes.

This records what the reviewer operations actually cost on the wire, because two
successive review rounds on this branch found tests that passed by charging less
than production does. Every price below was read off `githubIo`, not off a
fixture.

## Production request prices

| Call | Requests | Why |
| --- | --- | --- |
| `getRateLimit` | 2 | REST `rate_limit` plus a GraphQL `rateLimit` |
| `readReviewRecords(refs, prefix)` | 2 | one GraphQL read for the explicit refs, one REST listing for the prefix |
| `readReviewRecords(refs, null)` | 1 | no prefix listing |
| `listReviewRefsPaged` | 1 per 100-ref page | each page is a counted request |
| `readActiveReviewLeases` | 1 | one GraphQL read; also warms the commit base |

The rows returned by the prefix listing carry **no commit message**. Anything
that needs the message must look it up separately, and must test the message
rather than the record object - `record.commit` is `{message}` and stays truthy
even when GraphQL returned nothing.

## The page ceiling's headroom is illusory

`REVIEW_REF_PAGE_LIMIT` is 6, which reads like 600 refs of room per namespace.
It is not. The page limit is not the ceiling; the wire-request budget is, and
the two durable namespaces share it - one counted request per page each. Against
the current budget the cutover audit has room for roughly **500 assignment refs
and 200 replacement refs combined**, not 600 apiece.

Today the repository holds 370 assignment refs (4 pages) and 106 replacement
refs (2 pages), in namespaces that only ever grow. The operation will hit the
request budget before it ever reaches the page limit. The next person to read
the page constant will otherwise draw exactly the wrong conclusion from it, as
this lane did.

## Slot >=2 assignment costs more than slot 1

A fresh second-reviewer assignment spends 6 requests before taking the mutex, and
RESERVES `REVIEW_SLOT_N_LOCKED_WINDOW_REQUESTS` (15) for the locked window: 21
reserved in total. It therefore does not fit a 19-request ceiling and does fit
the 22-request ceiling PR #1813 introduces.

Reserved is not spent. The measured spend inside the lock on the fresh atomic
path is about 12 including cleanup, so the reserve is deliberately conservative -
a reserve must be at least the spend, and erring the other way is what put the
operation into the hard wall mid-window in the first place. Anyone re-deriving
these numbers should compare a measured spend against the reserve and expect the
reserve to be the larger of the two.

Two things follow, and both are now in the code:

- Resolving slot 1's reviewer (2 requests) moved from before the mutex to inside
  it. Done before the lock it pushed the count to 7-8 where the capacity
  precheck demands 6 or less, so a fresh slot-2 assignment could never clear its
  own precheck on the real wire, in any configuration.
- The capacity reserve is slot-aware. Reserving slot 1's 13 for both meant the
  precheck passed and the operation then hit the hard budget wall mid-window,
  with the mutex already held and its reads half done - the exact outcome a
  precheck exists to prevent. Slot >=2 now reserves what it spends and is
  refused cleanly before the mutex when it will not fit.

The tests assert this in both directions against the imported ceiling: below the
honest cost they require a clean pre-mutex refusal with no mutex taken; at or
above it they require the operation to complete within that cost.

## Sequencing decision: activate in the same session as the merge

The cutover is activated in the session that merges, not deferred to a later
one. A request-budget throw can land after the write has already succeeded, so
the operation reports failure for work that was done; recovery then depends on
the next run self-healing, which is a property being relied on rather than one
that was designed. Keeping activation in the merging session means a human is
present for that window instead of a later run inheriting it.

Merge order: PR #1799 lands only after PR #1813 raises the request ceiling. The
budget tests here assert against the imported constant, so they track the raise,
but they are re-run against merged `main` before merging rather than assumed.
