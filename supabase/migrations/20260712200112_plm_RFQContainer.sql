-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQContainer` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ container pricing
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQContainer" (
    "RFQContainer_id" integer NOT NULL,
    "RFQContainer_price" double precision,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQContainer"
    ADD CONSTRAINT "RFQContainer_pkey" PRIMARY KEY ("RFQContainer_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQContainer" IS 'RFQ container pricing';
