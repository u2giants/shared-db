-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `deliveryLocation` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Delivery locations
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."deliveryLocation" (
    "deliveryLocation_id" integer NOT NULL,
    "deliveryLocation_code" character varying(255),
    "deliveryLocation_title" character varying(255),
    "deliveryLocation_status" character varying(255),
    "deliveryLocation_auditlog" character varying(255),
    "deliveryLocation_airbyte_emitted_at" timestamp with time zone,
    "deliveryLocation_airbyte_deliverys_hashid" text
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."deliveryLocation"
    ADD CONSTRAINT "deliveryLocation_pkey" PRIMARY KEY ("deliveryLocation_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."deliveryLocation" IS 'Delivery locations';
