# Issue #853 explicit-transaction ledger safety proof

Date: 2026-08-16. Environment: disposable `postgres:15` container on hetz.
No preview or production database was contacted. The container and temporary
files were destroyed after each run.

The test used the repository-pinned Supabase CLI 2.105.0 with TLS enabled and a
successful CLI connection preflight. A valid migration shaped as
`BEGIN; CREATE TABLE ...; COMMIT;` was run while a `BEFORE INSERT` trigger
deliberately rejected only that migration's ledger row.

Counts-only/result-only evidence:

```text
supabase_version=2.105.0
container_tls=on
cli_preflight=pass
push_exit=1
ledger_exception_seen=t
probe_table_present=t
ledger_row_present=f
VERDICT=EXPLICIT_COMMIT_SEPARATES_SQL_FROM_LEDGER
```

This disproves per-file ledger atomicity for migration 20260816045130 because
that file contains explicit transaction control. It must never be applied to
production. Version 20260816110750 is the safe fix-forward: it carries the same
database body but no `BEGIN` or `COMMIT`, leaving Supabase CLI 2.105.0 to place
the SQL and ledger insert in its measured single transaction. The existing #611
Q5 disposable test proves the no-transaction-control shape rolls back both valid
DDL and the ledger row when the ledger insert fails.
