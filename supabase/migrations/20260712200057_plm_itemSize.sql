-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `itemSize` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Size reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."itemSize" (
    "itemSize_id" integer NOT NULL,
    "itemSize_code" character varying(255),
    "itemSize_title" character varying(255),
    "itemSize_status" character varying(255),
    "itemSize_auditlog" character varying(255),
    "itemSize_airbyte_emitted_at" timestamp with time zone,
    "itemSize_airbyte_sizes_hashid" text,
    "itemSize_unit" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."itemSize"
    ADD CONSTRAINT "itemSize_pkey" PRIMARY KEY ("itemSize_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."itemSize" IS 'Size reference';
