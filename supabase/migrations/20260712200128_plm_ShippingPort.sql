-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `ShippingPort` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Port reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."ShippingPort" (
    id integer NOT NULL,
    "PortCode" character varying,
    "PortDesc" character varying,
    "CountryCode" character varying,
    "UNLcode" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."ShippingPort"
    ADD CONSTRAINT "ShippingPort_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."ShippingPort" IS 'Port reference';
