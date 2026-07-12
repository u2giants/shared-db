-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedVersion` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized version config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedVersion" (
    id integer NOT NULL,
    title character varying,
    std_prod_id_fk integer,
    treatment_id_fk integer
);

CREATE SEQUENCE IF NOT EXISTS plm."StandardizedVersion_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedVersion"
    ADD CONSTRAINT "StandardizedVersion_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedVersion" IS 'Standardized version config';
