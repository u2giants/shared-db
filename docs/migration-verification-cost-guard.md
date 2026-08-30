# Migration verification cost guard

Migration verification runs inside the apply transaction. It must establish an
end state without scanning data whose size differs between an empty test
database and production.

`scripts/check-sql.sh` therefore rejects added migrations whose verification
`DO` block names `api.source_capture_inventory` or any `plm.*` object. The check
recognises explicitly tagged `$verify$` / `$verification$` blocks, nearby
verification headings, and verification messages. It scans quoted dynamic SQL
as well as ordinary statements. Shape checks should use PostgreSQL catalogues;
data-scale checks belong in a bounded rehearsal outside the apply transaction.

## Known false-negative surface

This is a static text check, not a SQL executor. It cannot reliably identify an
expensive read when an object name is assembled from fragments, obtained from a
variable or another table, hidden behind an unlisted view or function, or when
a verification block carries no verification marker or message. It also does
not estimate the cost of allowed catalogue queries. Review remains responsible
for those cases. These limits are explicit so a later incident expands the
guard and its regression corpus instead of treating this check as complete SQL
cost analysis.
