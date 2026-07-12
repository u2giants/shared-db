-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQStep` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ workflow steps
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQStep" (
    "RFQStep_id" integer NOT NULL,
    "RFQStep_title" character varying,
    "RFQStep_status" character varying,
    "RFQStep_access_level" character varying,
    "RFQStep_notified_user_level" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQStep"
    ADD CONSTRAINT "RFQStep_pkey" PRIMARY KEY ("RFQStep_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQStep" IS 'RFQ workflow steps';
