-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedProductElementValue` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized product element values
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedProductElementValue" (
    id integer NOT NULL,
    value character varying,
    std_prod_el_id_fk integer,
    std_prod_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedProductElementValue"
    ADD CONSTRAINT "StandardizedProductElementValue_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedProductElementValue" IS 'Standardized product element values';
