-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `merchGroupHeaders` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: MG header grouping by division
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."merchGroupHeaders" (
    id integer NOT NULL,
    "companyCode" character varying,
    "divisionCode" character varying,
    "mgTypeCode" character varying,
    "mgTypeDesc" character varying,
    "createdTime" character varying,
    "createdUser" character varying,
    "modTime" character varying,
    "modUser" character varying,
    "divisionCode_id_fk" integer,
    "companyCode_id_fk" integer
);

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupHeaders"
    ADD CONSTRAINT "merchGroupHeaders_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."merchGroupHeaders" IS 'MG header grouping by division';
