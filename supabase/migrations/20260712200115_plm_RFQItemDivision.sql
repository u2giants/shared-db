-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQItemDivision` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ item â†” division
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQItemDivision" (
    "RFQItemDivision_id" integer NOT NULL,
    "RFQItem_id_fk" integer,
    "divisionCode_id_fk" integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQItemDivision"
    ADD CONSTRAINT "RFQItemLicense_pkey" PRIMARY KEY ("RFQItemDivision_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."RFQItemDivision" IS 'RFQ item â†” division';
