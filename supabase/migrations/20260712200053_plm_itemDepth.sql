-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `itemDepth` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Depth reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."itemDepth" (
    "itemDepth_id" integer NOT NULL,
    "itemDepth_code" character varying,
    "itemDepth_title" character varying,
    "itemDepth_status" character varying,
    "itemDepth_auditlog" character varying,
    "itemDepth_airbyte_emitted_at" timestamp with time zone,
    "itemDepth_airbyte_depths_hashid" text
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."itemDepth"
    ADD CONSTRAINT "itemDepth_pkey" PRIMARY KEY ("itemDepth_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."itemDepth" IS 'Depth reference';
