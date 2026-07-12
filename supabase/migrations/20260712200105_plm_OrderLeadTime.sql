-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `OrderLeadTime` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Computed lead-time rollup
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."OrderLeadTime" (
    order_id integer NOT NULL,
    product_type_id_fk integer,
    licensor_id_fk integer,
    design_number integer,
    design_techpacking_time integer,
    licensing_time integer,
    sampling_time integer,
    mass_production_time integer,
    total_lead_time integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."OrderLeadTime"
    ADD CONSTRAINT "OrderLeadTime_pkey" PRIMARY KEY (order_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."OrderLeadTime" IS 'Computed lead-time rollup';
