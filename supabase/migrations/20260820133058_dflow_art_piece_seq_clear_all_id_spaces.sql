-- Advance dflow.art_piece_id_seq past EVERY art_piece id space in play.
--
-- WHY (live bug, reported 2026-08-20, evidence re-measured against production the same day)
-- ---------------------------------------------------------------------------------------
-- `dflow.art_piece` and the leftover `designflow.art_piece` were split from a common
-- ancestor and the sequence was never advanced. Measured on production
-- qsllyeztdwjgirsysgai on 2026-08-20:
--
--     dflow.art_piece                 981 rows, ids 1..1025, sequence last_value = 1025
--     designflow.art_piece           1114 rows, ids 1..1163      (orphan, frozen 2026-07-10)
--     Cloud SQL designflow.art_piece 1408 rows, ids 1..1465      (LIVE DesignFlow production)
--
-- So dflow re-issues ids that already mean something else. It has already happened: the
-- live app created ids 1024 and 1025 on 2026-07-29 -- "Testing Art Piece" and "Testing
-- again for autocomplete" -- while those same ids in `designflow.art_piece` are real
-- Batman artwork with attachments in `plm.art_piece_attachment` pointing at them. Real
-- image links now resolve to unrelated test records. Every further art piece keeps
-- colliding until the counter clears the highest id ever issued anywhere.
--
-- WHY 10000 AND NOT 1164
-- ----------------------
-- The obvious floor is `max(designflow.art_piece.id) + 1 = 1164`. That is NOT enough, and
-- the difference is the whole point of this migration.
--
--   * The original report proposed 1114. That is the ROW COUNT of designflow.art_piece,
--     not its maximum id (1163). Stopping at 1114 would leave ids 1115..1163 colliding.
--   * Stopping at 1164 would clear the orphan but NOT Cloud SQL, whose live production
--     table is at 1465 and grew by 16 ids in the nine days to 2026-08-20. Issue #770
--     plans to move exactly that data into this database. A sequence set to 1164 today
--     re-creates this identical bug, larger, on the day that migration lands.
--
-- 10000 clears all three id spaces with several years of headroom at the observed rate,
-- and it costs nothing: the column is `integer` (ceiling 2147483647) and the sequence
-- increments by 1, so ~2.1 billion values remain.
--
-- It also buys a diagnostic that a tight number would not: after this migration, an
-- `art_piece.id` below 10000 came from a pre-split copy, and one at or above 10000 was
-- issued by dflow afterwards. That boundary makes the #770 reconciliation unambiguous.
--
-- WHAT THIS MIGRATION DOES NOT DO
-- -------------------------------
--   * It does not backfill the 133 art pieces that `designflow.art_piece` has and
--     `dflow.art_piece` does not. That is a business decision (backfill or write off) and
--     is not a structural change.
--   * It does not move the 270 `plm.art_piece_attachment` rows, and does not drop that
--     table. The PLM side owns that once the ids are safe (#778).
--   * It does not touch ids 1024 and 1025, which are already wrong. Re-pointing or
--     renumbering existing rows is a data decision with application consequences, and
--     silently renumbering a live table from a schema migration would be exactly the kind
--     of invisible change this repository exists to prevent. Advancing the sequence stops
--     the bleeding; it does not pretend to heal what already bled.
--
-- SAFETY
-- ------
--   * The sequence is only ever moved FORWARD. If it is already at or past the target the
--     migration leaves it untouched and says so. Moving a sequence backwards would hand
--     out ids that are already taken, which is worse than the bug being fixed.
--   * The target is `greatest(10000, max(dflow.art_piece.id))`, so it can never be set
--     below a value the table has already used, even if rows arrive between authoring and
--     apply.
--   * Every object is resolved through `to_regclass`, so a from-empty replay or any
--     database without `dflow` is a clean no-op rather than an abort (#1258).
--   * Apply-time reads are the sequence itself and `max(id)` over `dflow.art_piece` on its
--     primary key -- a single index scan of a 981-row table. Nothing here scales with
--     production volume, which is the failure mode that made 20260819151536 unappliable.

do $$
declare
  v_floor    bigint := 10000;
  v_target   bigint;
  v_current  bigint;
  v_max_id   bigint;
begin
  if to_regclass('dflow.art_piece_id_seq') is null then
    raise notice 'dflow.art_piece_id_seq is absent; nothing to advance (from-empty replay).';
    return;
  end if;

  if to_regclass('dflow.art_piece') is null then
    v_max_id := 0;
  else
    execute 'select coalesce(max(id), 0) from dflow.art_piece' into v_max_id;
  end if;

  execute 'select last_value from dflow.art_piece_id_seq' into v_current;

  -- Never below what the table has already issued, never below the floor.
  v_target := greatest(v_floor, v_max_id);

  if v_current >= v_target then
    raise notice 'dflow.art_piece_id_seq already at % (target %); left unchanged. Sequences are never moved backwards.',
      v_current, v_target;
    return;
  end if;

  perform setval('dflow.art_piece_id_seq', v_target, true);

  raise notice 'dflow.art_piece_id_seq advanced from % to %; next id will be %.',
    v_current, v_target, v_target + 1;
end $$;

-- Verification. Catalogue and sequence state only; the single data read is max(id) over a
-- primary key. Deliberately does NOT assert against designflow.* or Cloud SQL: the first is
-- an orphan that is absent from preview and from a from-empty replay, and the second is a
-- different database this migration cannot see. Their ceilings are why 10000 was chosen,
-- and they are recorded in the header rather than asserted here, because an assertion that
-- cannot run everywhere is not a guard.
do $$
declare
  v_current bigint;
  v_max_id  bigint;
begin
  if to_regclass('dflow.art_piece_id_seq') is null then
    raise notice 'verification skipped: dflow.art_piece_id_seq absent.';
    return;
  end if;

  execute 'select last_value from dflow.art_piece_id_seq' into v_current;

  if to_regclass('dflow.art_piece') is null then
    v_max_id := 0;
  else
    execute 'select coalesce(max(id), 0) from dflow.art_piece' into v_max_id;
  end if;

  if v_current < 10000 then
    raise exception 'dflow_art_piece_seq_below_floor: sequence is at %, expected at least 10000. The id-collision fix did not take effect.',
      v_current;
  end if;

  if v_current < v_max_id then
    raise exception 'dflow_art_piece_seq_below_max_id: sequence is at % but the table already uses id %. The next insert would collide.',
      v_current, v_max_id;
  end if;

  raise notice 'VERIFIED: dflow.art_piece_id_seq = %, table max id = %, next id = %. Clears dflow (1025), the designflow orphan (1163) and Cloud SQL production (1465 on 2026-08-20).',
    v_current, v_max_id, v_current + 1;
end $$;
