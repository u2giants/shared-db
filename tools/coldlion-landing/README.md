# ColdLion history landing loader

Fills `coldlion.order_history_*` and `coldlion.prod_history_*` from the ColdLion
ERP API. The landing tables and their guards shipped on 2026-09-05; this is the
loader that puts rows in them.

Sales-order history and production-order history only. The masters half of plan
Step 7 (`sync-masters.mjs`) is **not** built here.

## What it does

One *window* + one *scope* at a time, atomically:

1. Fetch every page of a fixed 7-day window from the vendor.
2. Prove the pages are complete — contiguous page numbers, and the row count
   agreeing with the vendor's own `totalElements`.
3. Project the rows into parent lines, components and reference rows.
4. Load them in a single transaction that also writes the page evidence, the
   `sync_run` record and the window ledger state.

A window is either fully loaded or not loaded at all. There is no partial state
to reconcile by hand.

## Running it

Both entry points need `DATABASE_URL` (or `SUPABASE_DB_URL`) and the ColdLion
API key — `COLDLION_API_KEY`, or 1Password via the documented reference. The
target database is proved before any write, and a database with no `coldlion`
schema is refused.

Ongoing sync — re-reads the most recent windows, skipping any already loaded:

```bash
node tools/coldlion-landing/sync-history.mjs --windows 3
```

Backfill — resumable from the ledger, so re-running after an interruption
continues where the evidence stops:

```bash
node tools/coldlion-landing/backfill-history.mjs --from 2019-01-01 --limit 50
```

Add `--dry-run` to either to see the outstanding work without fetching or
writing anything.

## The vendor behaviours this is built around

**The page size is silently capped.** Asking for 2000 returns 200 with no error
and no warning. The requested size and the returned size are stored separately,
and completion is proven page by page rather than assumed from one response.

**A refused request lies about its own status.** The wire status is 400 while the
body claims 500. The loader branches on the wire status and stores both. This
matters: treating it as a 500 would mean retrying a permanent input error
forever.

**Production history must be asked for one stage at a time.** A request with no
stage silently returns only ISS, so ISS, INTRAN and REC are three separate
fetches. If a returned row carries a different stage than the one requested, the
window aborts rather than landing mislabelled rows. Sales history has no stage
and the database refuses one.

**Windows are a fixed 7-day grid anchored at 2019-01-01**, because the vendor
refuses a wider span and because a floating window would make two runs
disagree about what "a week" covers. The database enforces the grid.

**Parent totals repeat verbatim on every exploded row.** `lineQty`,
`prepackQty`, `totalPpkQty` and `prodOrderQty` are header values appearing once
per component row. They are stored once on the parent and never summed. The one
quantity that *is* summed is the per-component `ppkDetailQty`, and only to check
it reconciles against the parent total — when it does not, the row is stored
without the assertion rather than being quietly adjusted.

**A changed row is a new version, not an edit.** Identity includes a hash of the
row's own projection, so two differing versions of the same order line are two
rows. Nothing is merged and nothing is overwritten.

## What is deliberately excluded

The EP001 division is not loaded. The exclusion is counted in every run's notes
rather than being silent, so any gap between rows fetched and rows landed has a
stated cause.

## Tests

`tools/coldlion-landing-history.test.mjs` covers the grid, the scopes, both
vendor defects, both projections and the shape of the generated transaction. It
runs offline with no secrets and no database, as part of the tools offline suite.

No real ColdLion values appear in this directory. The fixtures are synthetic and
the loaders print counts, scopes and window dates only — this repository is
public.
