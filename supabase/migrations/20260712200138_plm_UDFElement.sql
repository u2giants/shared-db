-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `UDFElement` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: UDF element config
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."UDFElement" (
    "UDFElement_id" integer NOT NULL,
    "UDFElement_display_name" character varying NOT NULL,
    "UDFElement_layer" integer NOT NULL,
    "UDFElement_visibility" character varying(1) NOT NULL,
    "UDFElement_width" character varying(10) NOT NULL,
    "UDFElement_height" character varying(10) NOT NULL,
    "UDFElement_data_key" character varying(50) NOT NULL,
    "UDFGroup_id_fk" integer NOT NULL,
    "UDFElement_component_id_fk" integer NOT NULL,
    "UDFElement_type_id_fk" integer NOT NULL,
    "UDFElement_table_id_fk" integer NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."UDFElement"
    ADD CONSTRAINT "UDFElement_pkey" PRIMARY KEY ("UDFElement_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."UDFElement" IS 'UDF element config';
