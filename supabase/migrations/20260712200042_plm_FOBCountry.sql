-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `FOBCountry` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: FOB country reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."FOBCountry" (
    "FOBCountry_id" integer NOT NULL,
    "FOBCountry_title" character varying(255),
    "FOBCountry_status" character varying(255)
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."FOBCountry"
    ADD CONSTRAINT "FOBCountry_pkey" PRIMARY KEY ("FOBCountry_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."FOBCountry" IS 'FOB country reference';
