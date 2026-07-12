-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQGroup` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ grouping
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQGroup" (
    "RFQGroup_id" integer NOT NULL,
    "RFQGroup_name" character varying,
    "IsLegacy" boolean,
    data_added timestamp without time zone DEFAULT now(),
    user_id_fk integer,
    "HasDuplicates" boolean
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQGroup"
    ADD CONSTRAINT "RFQGroup_pkey" PRIMARY KEY ("RFQGroup_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQGroup" IS 'RFQ grouping';
