-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `LicenseFeedBacks` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Feedback phase definitions
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."LicenseFeedBacks" (
    id integer NOT NULL,
    phase character varying,
    status character varying,
    explanation character varying,
    duplicable boolean,
    "order" character varying,
    access character varying,
    item_order integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."LicenseFeedBacks"
    ADD CONSTRAINT "LicenseFeedBacks_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."LicenseFeedBacks" IS 'Feedback phase definitions';
