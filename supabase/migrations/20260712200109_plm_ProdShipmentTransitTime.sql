-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `ProdShipmentTransitTime` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Transit time reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."ProdShipmentTransitTime" (
    id integer NOT NULL,
    "ArrivalPortCode" character varying,
    "ArrivalTransitTime" character varying,
    "CompanyCode" character varying,
    "ShipPortCode" character varying,
    "WarehouseCode" character varying,
    "WhseTransitTime" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."ProdShipmentTransitTime"
    ADD CONSTRAINT "ProdShipmentTransitTime_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."ProdShipmentTransitTime" IS 'Transit time reference';
