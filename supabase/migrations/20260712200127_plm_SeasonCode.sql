-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `SeasonCode` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Season reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."SeasonCode" (
    id integer NOT NULL,
    "seasonCode" character varying,
    "seasonDesc" character varying,
    active character varying,
    "shipStartDate" character varying,
    "shipEndDate" character varying,
    "startDate" character varying,
    "endDate" character varying,
    "companyCode" character varying,
    "divisionCode" character varying,
    "modTime" character varying,
    "modUser" character varying,
    "createdUser" character varying,
    "createdTime" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."SeasonCode"
    ADD CONSTRAINT "SeasonCode_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."SeasonCode" IS 'Season reference';
