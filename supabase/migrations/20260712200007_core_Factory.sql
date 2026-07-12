-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `Factory` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Shared factory identity
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."Factory" (
    id integer NOT NULL,
    factory_name character varying,
    factory_nickname character varying,
    factory_status character varying,
    factory_access character varying,
    sort_order integer,
    factory_country character varying(255)
);

DO $$ BEGIN
  ALTER TABLE ONLY core."Factory"
    ADD CONSTRAINT "Factory_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."Factory" IS 'Shared factory identity';
