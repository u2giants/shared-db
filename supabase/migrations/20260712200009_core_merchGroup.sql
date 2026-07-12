-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `merchGroup` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Merchandise group master; import into typed core.* by mgTypeCode
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."merchGroup" (
    mg_id integer NOT NULL,
    mg_code character varying,
    mg_desc character varying,
    "ItemNoCode" character varying,
    "mgTypeCode" character varying,
    "createdTime" character varying,
    "createdUser" character varying,
    "modTime" character varying,
    "modUser" character varying,
    "companyCode_fk" character varying,
    "divisionCode_fk" character varying,
    "divisionCode_id_fk" integer,
    "companyCode_id_fk" integer,
    is_active boolean DEFAULT false,
    parent_id integer,
    "mgCode2" character varying(20),
    "mgCategory" character varying(20)
);

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroup"
    ADD CONSTRAINT "merchGroup_pkey" PRIMARY KEY (mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."merchGroup" IS 'Merchandise group master; import into typed core.* by mgTypeCode';
