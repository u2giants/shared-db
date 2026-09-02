# Migration verification cost guard

Migration verification runs inside the apply transaction. It must establish an
end state without scanning data whose size differs between an empty test
database and production.

`scripts/check-sql.sh` therefore rejects added migrations whose verification
`DO` block **reads** `api.source_capture_inventory` or any `plm.*` object.

## What it means by "reads"

The rule is a read context, not a name. A migration is refused when, inside a
verification block, one of the prohibited objects appears:

- after `from`, `join`, `into`, `update`, `delete from`, `truncate`, `analyze`
  or `copy` (optionally through `only`), or
- as a called routine — `plm.something(...)`, or
- indirectly, because the block does `set search_path to ... plm ...`, which
  makes every unqualified name a possible `plm` read that no `plm.` pattern can
  see. That construct is refused outright rather than guessed at.

Naming a prohibited object inside a catalogue lookup or an error message is
**allowed**, because nothing scans it: `to_regclass('api.source_capture_inventory')`,
`pg_get_viewdef('...'::regclass)`, `has_table_privilege(...)`,
`to_regprocedure('plm.finalize_capture(uuid)')`,
`information_schema.columns where table_schema = 'plm'`, and
`raise exception 'no plm.wildbrain_* tables exist'` all pass. That catalogue-only
shape is what the guard exists to steer verification towards, so it must not
refuse it. Migration `20260820004338` is the worked example in the repository.

The one place a string literal is still read as SQL is when it is handed to
`execute` or `format`, because there it is about to run.

## Which blocks are inspected

Dollar-quoted `DO` bodies, including `do language plpgsql $verify$` and a `DO`
separated from its tag by a comment. A body counts as verification when its tag
names verify/verification, when it raises a verification message, or when a
verification heading sits immediately above it.

## Fail closed

If the scanner cannot parse a file — an unterminated string, comment,
dollar-quoted body or quoted identifier — the migration is **refused**, with the
line of the unclosed construct. It is never passed. The only thing that passes
without inspection is a branch that adds no migration at all, which
`check-sql.sh` establishes before this script runs.

## Known false-negative surface

This is a static text scanner, not a SQL executor. It still cannot see an
expensive read when:

- the object name is assembled from fragments or built by `format('%I.%I', ...)`
  from identifier variables, or comes from a variable or another table;
- the read goes through an unlisted view, function or foreign table that itself
  touches the prohibited objects;
- a verification block carries no verification tag, message or heading, so it is
  not recognised as verification in the first place;
- the read uses a construct outside the listed read contexts — for example a
  scalar subquery reached some other way, or a `with` clause naming the object
  through an alias defined elsewhere.

It also does not estimate the cost of allowed catalogue queries, and it inspects
only migrations added by the branch, never historical SQL.

These limits are stated so a later incident expands the guard and its regression
corpus, instead of treating this check as complete SQL cost analysis. Review
remains responsible for the cases above.
