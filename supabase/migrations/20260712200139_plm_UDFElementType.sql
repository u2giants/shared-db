-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFElementType` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF element type config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFElementType" (
    "UDFElementType_id" integer NOT NULL,
    "UDFElementType_name" character varying(50) NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFElementType"
    ADD CONSTRAINT "UDFElementType_pkey" PRIMARY KEY ("UDFElementType_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFElementType" IS 'UDF element type config';
