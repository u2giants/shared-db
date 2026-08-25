-- Make the Sample Tracking inventory read index-backed.
--
-- The previous view grouped dflow.sample_balance_by_location, then joined the
-- movement ledger back to itself through an OR predicate to recover
-- available_since.  That forced repeated scans and a nested-loop join.  Build
-- balance and recency from the same two movement legs instead, while retaining
-- the existing row grain and terminal-office normalization exactly.
BEGIN;

CREATE INDEX IF NOT EXISTS sample_movement_inventory_destination_normalized_idx
  ON dflow.sample_movement (
    (CASE
      WHEN to_location_type = 'terminal'
       AND to_location_id IN ('nyc_office_inventory', 'ningbo_office_inventory')
        THEN 'office'
      ELSE to_location_type
    END),
    (CASE
      WHEN to_location_id = 'nyc_office_inventory' THEN 'nyc'
      WHEN to_location_id = 'ningbo_office_inventory' THEN 'ningbo'
      ELSE to_location_id
    END),
    sample_id_fk,
    occurred_at DESC
  );

CREATE INDEX IF NOT EXISTS sample_movement_inventory_source_normalized_idx
  ON dflow.sample_movement (
    (CASE
      WHEN from_location_type = 'terminal'
       AND from_location_id IN ('nyc_office_inventory', 'ningbo_office_inventory')
        THEN 'office'
      ELSE from_location_type
    END),
    (CASE
      WHEN from_location_id = 'nyc_office_inventory' THEN 'nyc'
      WHEN from_location_id = 'ningbo_office_inventory' THEN 'ningbo'
      ELSE from_location_id
    END),
    sample_id_fk,
    occurred_at DESC
  );

CREATE OR REPLACE VIEW dflow.sample_inventory AS
WITH movement_legs AS (
  SELECT
    m.sample_id_fk,
    m.to_location_type AS location_type,
    m.to_location_id AS location_id,
    CASE
      WHEN m.to_location_type = 'terminal'
       AND m.to_location_id IN ('nyc_office_inventory', 'ningbo_office_inventory')
        THEN 'office'
      ELSE m.to_location_type
    END AS product_location_type,
    CASE
      WHEN m.to_location_id = 'nyc_office_inventory' THEN 'nyc'
      WHEN m.to_location_id = 'ningbo_office_inventory' THEN 'ningbo'
      ELSE m.to_location_id
    END AS product_location_id,
    m.quantity::bigint AS quantity_delta,
    m.occurred_at
  FROM dflow.sample_movement m

  UNION ALL

  SELECT
    m.sample_id_fk,
    m.from_location_type AS location_type,
    m.from_location_id AS location_id,
    CASE
      WHEN m.from_location_type = 'terminal'
       AND m.from_location_id IN ('nyc_office_inventory', 'ningbo_office_inventory')
        THEN 'office'
      ELSE m.from_location_type
    END AS product_location_type,
    CASE
      WHEN m.from_location_id = 'nyc_office_inventory' THEN 'nyc'
      WHEN m.from_location_id = 'ningbo_office_inventory' THEN 'ningbo'
      ELSE m.from_location_id
    END AS product_location_id,
    -m.quantity::bigint AS quantity_delta,
    m.occurred_at
  FROM dflow.sample_movement m
), inventory_balance AS (
  SELECT
    l.sample_id_fk,
    l.location_type,
    l.location_id,
    l.product_location_type,
    l.product_location_id,
    sum(l.quantity_delta)::bigint AS quantity,
    max(l.occurred_at) AS available_since
  FROM movement_legs l
  GROUP BY
    l.sample_id_fk,
    l.location_type,
    l.location_id,
    l.product_location_type,
    l.product_location_id
  HAVING sum(l.quantity_delta) > 0
)
SELECT
  b.sample_id_fk,
  b.location_type,
  b.product_location_type,
  b.product_location_id,
  b.quantity,
  b.available_since,
  EXISTS (
    SELECT 1
    FROM dflow.sample_shipment_item si
    WHERE si.sample_id_fk = b.sample_id_fk
      AND si.box_id_fk IS NOT NULL
  ) AS is_boxed,
  (b.location_type = 'in_transit') AS is_in_transit,
  (b.location_type <> 'in_transit') AS is_eligible,
  CASE
    WHEN b.location_type = 'in_transit' THEN 'in_transit'
    ELSE NULL
  END AS ineligibility_reason
FROM inventory_balance b;

COMMENT ON VIEW dflow.sample_inventory IS
  'Server inventory read model derived in one pass from indexed movement legs, including parked office leftovers.';

REVOKE ALL ON dflow.sample_inventory FROM anon, authenticated;

DO $$
BEGIN
  IF to_regclass('dflow.sample_movement_inventory_destination_normalized_idx') IS NULL
     OR to_regclass('dflow.sample_movement_inventory_source_normalized_idx') IS NULL THEN
    RAISE EXCEPTION 'Sample inventory normalized movement indexes are missing';
  END IF;

  IF has_table_privilege('anon', 'dflow.sample_inventory', 'SELECT')
     OR has_table_privilege('authenticated', 'dflow.sample_inventory', 'SELECT') THEN
    RAISE EXCEPTION 'Sample inventory view has a forbidden direct table privilege';
  END IF;
END $$;

COMMIT;
