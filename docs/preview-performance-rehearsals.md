# Preview performance rehearsals

Performance fixtures must run inside one transaction that is always rolled back. This preserves immutable ledgers such as `dflow.sample_movement`, leaves planner statistics and application rows unchanged, and removes the old need to rebuild the shared preview branch merely to clear test data.

Use `scripts/run-preview-rehearsal-transaction.mjs` with a fixture ID shaped like `AI-PERF-YYYYMMDD-name`. Put the seed, `ANALYZE`, benchmark queries, and evidence queries in one SQL file. Refer to the ID inside SQL with `current_setting('app.fixture_id')` so every generated row remains visibly attributable during the run.

Provide the database URL only through `SUPABASE_DB_URL`; never put it in a command or file. The runner requires the URL to contain the requested preview project ref, prints the safe ref as target proof before executing, and hard-refuses production `qsllyeztdwjgirsysgai`. It rejects transaction-control commands, psql includes, and statements that cannot be rolled back. Any SQL or connection failure closes the session with its transaction uncommitted.

Example invocation:

`node scripts/run-preview-rehearsal-transaction.mjs --project-ref <current-preview-ref> --fixture-id AI-PERF-20260830-inventory --sql-file <rehearsal.sql>`

Successful completion ends with `REHEARSAL_ROLLED_BACK`. Confirm representative fixture rows are absent with a separate read-only query before treating cleanup as proven. Never use branch deletion or rebuild as fixture teardown.
