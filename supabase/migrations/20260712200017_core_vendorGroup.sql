-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `vendorGroup` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Vendor/factory grouping metadata
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."vendorGroup" (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    factory_ids integer[] DEFAULT '{}'::integer[]
);

CREATE SEQUENCE IF NOT EXISTS core."vendorGroup_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core."vendorGroup_id_seq" OWNED BY core."vendorGroup".id;

ALTER TABLE ONLY core."vendorGroup" ALTER COLUMN id SET DEFAULT nextval('core."vendorGroup_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core."vendorGroup"
    ADD CONSTRAINT "vendorGroup_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."vendorGroup" IS 'Vendor/factory grouping metadata';
