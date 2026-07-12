-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQWhse` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ warehouse pricing
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQWhse" (
    "RFQWhse_id" integer NOT NULL,
    "RFQWhse_price" double precision
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQWhse"
    ADD CONSTRAINT "RFQWhse_pkey" PRIMARY KEY ("RFQWhse_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQWhse" IS 'RFQ warehouse pricing';
