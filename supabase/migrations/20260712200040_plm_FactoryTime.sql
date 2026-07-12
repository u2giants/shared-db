-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `FactoryTime` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Factory lead-time reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."FactoryTime" (
    id integer NOT NULL,
    product_category character varying(100),
    product_subtype character varying(200) NOT NULL,
    sampling_days integer DEFAULT 0,
    resampling_days integer DEFAULT 0,
    mass_production_days integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS plm."FactoryTime_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm."FactoryTime_id_seq" OWNED BY plm."FactoryTime".id;

ALTER TABLE ONLY plm."FactoryTime" ALTER COLUMN id SET DEFAULT nextval('plm."FactoryTime_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm."FactoryTime"
    ADD CONSTRAINT "FactoryTime_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."FactoryTime" IS 'Factory lead-time reference';
