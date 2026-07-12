-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `licenseList` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Legacy licensor list; reconcile with MG05
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."licenseList" (
    "licenseList_id" integer NOT NULL,
    "licenseList_code" character varying(255),
    "licenseList_title" character varying(255),
    "licenseList_status" character varying(255),
    "licenseList_auditlog" character varying(255),
    "licenseList_royalty_rate" double precision,
    "licenseList_airbyte_emitted_at" timestamp with time zone,
    "licenseList_airbyte_licenses_hashid" text,
    "licenseList_fob_royalty_rate" double precision
);

DO $$ BEGIN
  ALTER TABLE ONLY core."licenseList"
    ADD CONSTRAINT "licenseList_pkey" PRIMARY KEY ("licenseList_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."licenseList" IS 'Legacy licensor list; reconcile with MG05';
