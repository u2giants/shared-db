-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedProductElement` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized product element config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedProductElement" (
    id integer NOT NULL,
    title character varying,
    std_prod_id_fk integer,
    type character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedProductElement"
    ADD CONSTRAINT "StandardizedProductElement_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedProductElement" IS 'Standardized product element config';
