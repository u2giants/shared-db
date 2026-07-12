-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `merchGroupMaster` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Master MG tree used by relations
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."merchGroupMaster" (
    mg_id integer NOT NULL,
    mg_code character varying,
    mg_desc character varying,
    "ItemNoCode" character varying,
    "mgTypeCode" character varying,
    "createdTime" timestamp without time zone,
    "createdUser" character varying(100),
    "modTime" timestamp without time zone,
    "modUser" character varying(100),
    "companyCode_fk" character varying,
    "divisionCode_fk" character varying,
    "divisionCode_id_fk" integer,
    "companyCode_id_fk" integer,
    is_active boolean DEFAULT true,
    "mgCode2" character varying(20),
    "mgCategory" character varying(20)
);

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupMaster"
    ADD CONSTRAINT "merchGroupMaster_pkey" PRIMARY KEY (mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."merchGroupMaster" IS 'Master MG tree used by relations';
