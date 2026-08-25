# ColdLion approved mapping gate — Paramount five

This artifact widens the frozen Phase 4 mapping only for the five exact Property codes Albert
approved under Paramount on issue #539: `AM1`, `AM2`, `MGM`, `WND`, and `EP`. Each code has one
typed identity in `CW001` and one in `SP001`, both pointing to the same new canonical Property.

The original 542 mappings remain present. The widened contract is:

- schema: `coldlion_phase4_approved_mapping_input/v2`
- mappings: **552** (542 original plus 10 typed rows)
- distinct canonical UUIDs: **276** (271 original plus five)
- md5: `09e18e47d67181b06483d6cf4454e053`
- approval: Albert Hazan, 2026-08-18, issue #539
- implementation: issue #1177, migration `20260825050407`

The fingerprint uses the established Phase 4 encoding: sorted
`<entity_type>|<company>/<division>/<mgTypeCode>/<mgCode>|<canonical_id>` rows joined by newline,
then MD5 over UTF-8. The readiness tool recomputes the fingerprint and refuses any difference.

No other formerly excluded code is admitted. The migration also applies §6.4 matched-row
abstention: any existing canonical code/name, Property alias, or taxonomy source reference aborts
the transaction instead of updating a possible match or creating a duplicate.
