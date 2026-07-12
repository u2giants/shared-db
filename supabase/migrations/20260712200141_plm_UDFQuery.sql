-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFQuery` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF query config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFQuery" (
    "UDFQuery_id" integer NOT NULL,
    "UDFQuery_column_name" character varying NOT NULL,
    "UDFQuery_condition" character varying NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFQuery"
    ADD CONSTRAINT "UDFQuery_pkey" PRIMARY KEY ("UDFQuery_column_name");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFQuery" IS 'UDF query config';
