-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedSize` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized size config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedSize" (
    id integer NOT NULL,
    size_in_id_fk integer,
    size_cm_id_fk integer,
    std_group_id_fk integer,
    std_prod_id_fk integer,
    status character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedSize"
    ADD CONSTRAINT "StandardizedSize_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedSize" IS 'Standardized size config';
