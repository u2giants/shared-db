-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `divisionCode` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Division codes 01, 08, 09
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."divisionCode" (
    "divCode_id" integer NOT NULL,
    "divCode_code" character varying NOT NULL,
    division_name character varying(50) NOT NULL,
    company_name_fk character varying,
    external_divisoncode character varying,
    is_divcode_active boolean
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."divisionCode"
    ADD CONSTRAINT "DivisionCode_pkey" PRIMARY KEY ("divCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."divisionCode" IS 'Division codes 01, 08, 09';
