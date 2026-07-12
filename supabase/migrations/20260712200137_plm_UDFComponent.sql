-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFComponent` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF component config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFComponent" (
    "UDFComponent_id" integer NOT NULL,
    "UDFComponent_name" character varying(100) NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFComponent"
    ADD CONSTRAINT "UDFComponent_pkey" PRIMARY KEY ("UDFComponent_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFComponent" IS 'UDF component config';
