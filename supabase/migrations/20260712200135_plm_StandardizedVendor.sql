-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `StandardizedVendor` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Standardized vendor config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."StandardizedVendor" (
    id integer NOT NULL,
    price double precision,
    std_item_id_fk integer,
    factory_id_fk integer,
    std_prod_id_fk integer,
    "pKey" character varying NOT NULL,
    highlighted character varying,
    width character varying,
    length character varying,
    height character varying,
    quote_date date
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."StandardizedVendor"
    ADD CONSTRAINT "StandardizedVendor_pkey" PRIMARY KEY ("pKey");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."StandardizedVendor" IS 'Standardized vendor config';
