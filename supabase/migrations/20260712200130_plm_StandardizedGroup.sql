-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedGroup` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized product group config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedGroup" (
    id integer NOT NULL,
    title character varying,
    customer_id_fk integer,
    std_prod_id_fk integer,
    depth_id_fk integer,
    "casePack" character varying,
    qty character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedGroup"
    ADD CONSTRAINT "StandardizedGroup_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedGroup" IS 'Standardized product group config';
