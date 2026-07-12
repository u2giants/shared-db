-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFTable` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF table config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFTable" (
    "UDFTable_id" integer NOT NULL,
    "UDFTable_name" character varying(50) NOT NULL,
    "UDFTable_primary_id" character varying NOT NULL,
    "UDFElement_id_fk" integer NOT NULL,
    "UDFTable_associate_type" character varying(50) NOT NULL,
    "UDFComponent_id_fk" integer NOT NULL,
    "UDFTable_foreignKey" character varying(100) NOT NULL,
    "UDFTable_targetKey" character varying(100) NOT NULL,
    "UDFTable_query_id_fk" integer,
    container_id character varying,
    nickname character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFTable"
    ADD CONSTRAINT "UDFTable_pkey" PRIMARY KEY ("UDFTable_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFTable" IS 'UDF table config';
