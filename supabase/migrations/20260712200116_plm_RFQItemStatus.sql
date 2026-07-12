-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQItemStatus` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ status codes
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQItemStatus" (
    "RFQItemStatus_id" integer NOT NULL,
    "RFQItemStatus_code" character varying(255),
    "RFQItemStatus_title" character varying(255),
    "RFQItemStatus_status" character varying(255),
    "RFQItemStatus_auditlog" character varying(255),
    "RFQItemStatus_airbyte_emitted_at" timestamp with time zone,
    "RFQItemStatus_airbyte_productions_hashid" text
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQItemStatus"
    ADD CONSTRAINT "RFQItemStatus_pkey" PRIMARY KEY ("RFQItemStatus_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQItemStatus" IS 'RFQ status codes';
