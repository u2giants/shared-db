-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `externalApi` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: External API config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."externalApi" (
    "externalApi_id" integer NOT NULL,
    "externalApi_method" character varying(50) NOT NULL,
    "externalApi_hostname" character varying NOT NULL,
    "externalApi_company_id" character varying(50) NOT NULL,
    "externalApi_path" character varying,
    "externalApi_port" integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."externalApi"
    ADD CONSTRAINT "externalApi_pkey" PRIMARY KEY ("externalApi_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."externalApi" IS 'External API config';
