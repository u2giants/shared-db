-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQVendor` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Vendor quotes per RFQ item
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQVendor" (
    "RFQVendor_id" integer NOT NULL,
    "RFQVendor_amount" character varying(255),
    "RFQVendor_cbm_pc" character varying(255),
    "RFQVendor_status" character varying(255),
    "RFQitem_id_fk" integer,
    "RFQVendor_note" character varying,
    carton_width double precision,
    carton_height double precision,
    carton_length double precision,
    req_status integer,
    vendor_id_fk integer,
    quote_date date,
    std_vendor_id_fk character varying,
    "RFQVendor_suggested_note" character varying,
    "RFQVendor_suggested_amount" character varying(255),
    "RFQVendor_suggested_cbm_pc" character varying(255),
    suggested_carton_height double precision,
    suggested_carton_width double precision,
    suggested_carton_length double precision,
    lead_time integer,
    price_terms character varying(255),
    fob_country character varying(255),
    fob_port character varying(255),
    requote_requested boolean DEFAULT false,
    "RFQVendor_archive_optout" boolean DEFAULT false,
    "RFQVendor_archived" boolean DEFAULT false
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQVendor"
    ADD CONSTRAINT "RFQVendor_pkey" PRIMARY KEY ("RFQVendor_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_rfqvendor_item_fk ON plm."RFQVendor" USING btree ("RFQitem_id_fk");

CREATE INDEX IF NOT EXISTS idx_rfqvendor_vendor_archived ON plm."RFQVendor" USING btree (vendor_id_fk, "RFQVendor_archived");

COMMENT ON TABLE plm."RFQVendor" IS 'Vendor quotes per RFQ item';
