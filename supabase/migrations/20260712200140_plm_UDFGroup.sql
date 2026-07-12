-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFGroup` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF group config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFGroup" (
    "UDFGroup_id" integer NOT NULL,
    "UDFGroup_name" character varying(50) NOT NULL,
    "UDFGroup_layer" character varying(50) NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFGroup"
    ADD CONSTRAINT "UDFGroup_pkey" PRIMARY KEY ("UDFGroup_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFGroup" IS 'UDF group config';
