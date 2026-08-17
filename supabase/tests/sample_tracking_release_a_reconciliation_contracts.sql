-- Transactional proof for the owner-authorized Release A reconciliation.
BEGIN;

DO $$
DECLARE
  v_present integer;
  v_missing text[];
BEGIN
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version IN ('20260814130000','20260814193402','20260817190000')) <> 3 THEN
    RAISE EXCEPTION 'Release A reconciliation ledger is incomplete';
  END IF;

  SELECT array_agg(name ORDER BY name) INTO v_missing
  FROM (VALUES
    ('dflow.sample_creation_batch'),('dflow.sample_workflow'),
    ('dflow.sample_path_revision'),('dflow.sample_inventory')
  ) AS expected(name)
  WHERE to_regclass(expected.name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Release A reconciliation relations are incomplete: %',v_missing;
  END IF;

  IF (SELECT count(DISTINCT p.proname)
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='dflow' AND p.proname IN (
        'validate_sample_path_revision','require_sample_path_revision',
        'apply_sample_path_revision','reject_sample_path_revision_mutation',
        'validate_sample_shipment_line_header')) <> 5 THEN
    RAISE EXCEPTION 'Release A reconciliation functions are incomplete';
  END IF;
  IF (SELECT count(*) FROM pg_trigger
      WHERE NOT tgisinternal AND tgname IN (
        'sample_path_revision_validate','sample_workflow_path_revision_required',
        'sample_path_revision_apply','sample_path_revision_immutable',
        'sample_shipment_line_header_route')) <> 5 THEN
    RAISE EXCEPTION 'Release A reconciliation triggers are incomplete';
  END IF;
  IF to_regclass('dflow.sample_workflow_queue_idx') IS NULL
     OR to_regclass('dflow.sample_movement_inventory_idx') IS NULL THEN
    RAISE EXCEPTION 'Release A reconciliation indexes are incomplete';
  END IF;
  IF (SELECT count(*) FROM dflow.sample_carrier WHERE is_active) <> 4
     OR (SELECT count(*) FROM dflow.sample_carrier
         WHERE is_active AND carrier_code IN ('ups','fedex','dhl','usps')) <> 4 THEN
    RAISE EXCEPTION 'Release A carrier seed contract is incomplete';
  END IF;
  IF has_table_privilege('anon','dflow.sample_creation_batch','SELECT')
     OR has_table_privilege('authenticated','dflow.sample_workflow','SELECT')
     OR has_table_privilege('authenticated','dflow.sample_path_revision','SELECT')
     OR has_table_privilege('authenticated','dflow.sample_inventory','SELECT') THEN
    RAISE EXCEPTION 'Release A reconciliation exposed a direct relation privilege';
  END IF;

  -- A PostgreSQL exception block is a subtransaction. The deliberately dropped
  -- table and its dependent objects must be restored when the exact mixed-state
  -- guard refuses the 2-of-3 catalog shape.
  BEGIN
    DROP TABLE dflow.sample_path_revision CASCADE;
    SELECT count(*) INTO v_present
    FROM (VALUES
      ('dflow.sample_creation_batch'),('dflow.sample_workflow'),
      ('dflow.sample_path_revision')
    ) AS expected(name)
    WHERE to_regclass(expected.name) IS NOT NULL;
    IF v_present NOT IN (0,3) THEN
      RAISE EXCEPTION USING ERRCODE='P9750',
        MESSAGE='expected Release A mixed-state refusal';
    END IF;
    RAISE EXCEPTION 'Release A mixed-state guard did not refuse 2-of-3 tables';
  EXCEPTION WHEN SQLSTATE 'P9750' THEN
    IF to_regclass('dflow.sample_path_revision') IS NULL
       OR to_regprocedure('dflow.validate_sample_path_revision()') IS NULL THEN
      RAISE EXCEPTION 'Release A mixed-state refusal did not roll back its catalog changes';
    END IF;
  END;
END $$;

ROLLBACK;
