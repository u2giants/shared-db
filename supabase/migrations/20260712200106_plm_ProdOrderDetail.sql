-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `ProdOrderDetail` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Production order lines
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."ProdOrderDetail" (
    id integer NOT NULL,
    "CompanyCode" character varying,
    "DivisionCode" character varying,
    "CustomerCode" character varying,
    "ProdSeq" integer,
    "prodLineSeq" integer,
    "StageSeq" integer,
    "StageCode" character varying,
    "itemNo" character varying,
    "colorCode" character varying,
    "labelCode" character varying,
    "dimCode" character varying,
    "prepackCode" character varying,
    "sizeCode" character varying,
    "wipQty" integer,
    "CancelledQty" integer,
    "MovedQty" integer,
    "ProdCost" integer,
    "UOMCode" character varying,
    "ShipDate" date,
    "OrigShipDate" date,
    "DueDate" date,
    "OrigDueDate" date,
    "ShipCancelDate" date,
    "OrigShipCancelDate" date,
    "WarehouseCode" character varying,
    "ShipmentFkey" integer,
    "ContainerFkey" integer,
    "ReceiveFkey" integer,
    "prodQty" integer,
    "VendorCode" character varying,
    "createdTime" timestamp with time zone,
    "createdUser" character varying,
    "modTime" timestamp without time zone,
    "modUser" character varying,
    "ProdLineFkey" integer,
    "ContainerDtlFkey" integer,
    "RecvDtlFkey" integer,
    "SalesOrderFkey" integer,
    "SalesOrderNo" integer,
    "CostSheetFkey" integer,
    "BOMFKey" integer,
    "AllocatableWip" character varying,
    "ProdOrderCancelType" character varying,
    "UDF01" character varying,
    "VendorInvoiceFKey" integer,
    "EDI943Proc" character varying,
    "SizeExplosionCode" character varying,
    "CustPONumber" character varying,
    "prodOrderNo" character varying,
    "itemPkey" integer,
    "merchGroup05Desc" character varying,
    "itemDesc" character varying,
    pkey integer NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."ProdOrderDetail"
    ADD CONSTRAINT "ProdOrderDetail_pkey1" PRIMARY KEY (pkey);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "ProdOrderDetail_pkey" ON plm."ProdOrderDetail" USING btree (id);

COMMENT ON TABLE plm."ProdOrderDetail" IS 'Production order lines';
