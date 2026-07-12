-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedProductType` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized product type config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedProductType" (
    id integer NOT NULL,
    prod_name character varying,
    prod_status character varying,
    prod_img_thumbnail character varying,
    prod_img_fullsize character varying,
    material_id_fk integer,
    construction_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedProductType"
    ADD CONSTRAINT "StandardizedProduct_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedProductType" IS 'Standardized product type config';
