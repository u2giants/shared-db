-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `ContainerHeader` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Container/shipment logistics
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."ContainerHeader" (
    id integer NOT NULL,
    fkey integer,
    "CompanyCode" character varying,
    "ContainerNo" character varying,
    "ShipmentNo" character varying,
    "ContainerType" character varying,
    "SealNo" character varying,
    "ProNo" character varying,
    "ContainerVolume" character varying,
    "WarehouseCode" character varying,
    "TotalCartons" character varying,
    "EstWhseArrivalDate" character varying,
    "WhseArrivalDate" character varying,
    "ContainerRecvd" character varying,
    "ReceiveFkey" character varying,
    "ReceiveNo" character varying,
    "ContainerSize" character varying,
    "EDI943Proc" character varying,
    "EDI943ProcDate" character varying,
    "ContainerStatus" character varying,
    "LFDDate" character varying,
    "ContainerPriority" character varying,
    "Remarks" character varying,
    "TotalQty" character varying,
    "ShipViaCode" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."ContainerHeader"
    ADD CONSTRAINT "ContainerHeader_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."ContainerHeader" IS 'Container/shipment logistics';
