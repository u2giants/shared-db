-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `companyCode` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Company scope (EDGEHOME)
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."companyCode" (
    "comCode_id" integer NOT NULL,
    "compCode_cl_id" character varying NOT NULL,
    company_name character varying(100) NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."companyCode"
    ADD CONSTRAINT "companyCode_pkey" PRIMARY KEY ("comCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."companyCode" IS 'Company scope (EDGEHOME)';
