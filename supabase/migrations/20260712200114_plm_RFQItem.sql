-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `RFQItem` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: RFQ line items
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."RFQItem" (
    "rfqItem_id" integer NOT NULL,
    "rfqItem_style_number" character varying(255),
    "rfqItem_notes" character varying(255),
    "rfqItem_depth" integer,
    "rfqItem_freight" character varying(255),
    "rfqItem_picture" character varying(255),
    "rfqItem_auditlog" character varying(255),
    "rfqItem_customer" integer,
    "rfqItem_dilution" character varying(255),
    "rfqItem_fob_cost" character varying(255),
    "rfqItem_quantity" character varying(255),
    "rfqItem_size_l_w" integer,
    "rfqItem_case_pack" character varying(255),
    "rfqItem_duty_rate" character varying(255),
    "rfqItem_tech_pack_link" character varying(255),
    "rfqItem_wholesale" character varying(255),
    "rfqItem_gen_fob_margin" character varying(255),
    "rfqItem_gen_ldp_margin" character varying(255),
    "rfqItem_gen_poe_margin" character varying(255),
    "rfqItem_comp_retail" character varying(255),
    "rfqItem_default_cbm" character varying(255),
    "rfqItem_description" character varying(255),
    "rfqItem_gen_fob_netsell" character varying(255),
    "rfqItem_gen_fob_royalty" character varying(255),
    "rfqItem_landed_cost" character varying(255),
    "rfqItem_gen_whse_netsell" character varying(255),
    "rfqItem_gen_whse_royalty" character varying(255),
    "rfqItem_gen_poe_netsell" character varying(255),
    "rfqItem_gen_poe_royalty" character varying(255),
    "rfqItem_created_date" timestamp with time zone,
    "rfqItem_date_modified" timestamp without time zone,
    "rfqItem_delivery_loc" integer,
    "rfqItem_picturethumb" character varying(255),
    "rfqItem_quote_update" character varying(255),
    "rfqItem_cbm_per_piece" character varying(255),
    "rfqItem_gen_fob_pricesale" character varying(255),
    "rfqItem_gen_fob_sellprice" character varying(255),
    "rfqItem_gen_whse_pricesale" character varying(255),
    "rfqItem_gen_whse_sellprice" character varying(255),
    "rfqItem_logistic_load" character varying(255),
    "rfqItem_gen_poe_pricesale" character varying(255),
    "rfqItem_gen_poe_sellprice" character varying(255),
    "rfqItem_price_per_cbm" character varying(255),
    "rfqItem_standardized_products" character varying(255),
    "rfqItem_gen_mddp_pricesale" character varying(255),
    "rfqItem_gen_mddp_sellprice" character varying(255),
    "rfqItem_gen_mddp_royalty" character varying(255),
    "rfqItem_warehouse" character varying(255),
    "rfqItem_active" integer,
    "rfqItem_archive" integer,
    "rfqItem_rfq_group" integer,
    "rfqItem_step" integer,
    "rfqItem_cbm_per_price" character varying,
    "rfqItem_agent" character varying,
    "rfqItem_udf1" integer,
    "rfqItem_udf2" integer,
    "rfqItem_udf3" integer,
    "rfqItem_udf4" integer,
    "rfqItem_gen_mddp_netsell" character varying,
    "rfqItem_gen_mddp_margin" character varying,
    "rfqItem_lic_mddp_pricesale" character varying,
    "rfqItem_lic_mddp_sellprice" character varying,
    "rfqItem_lic_mddp_royalty" character varying,
    "rfqItem_lic_mddp_netsell" character varying,
    "rfqItem_lic_mddp_margin" character varying,
    "rfqItem_lic_poe_pricesale" character varying,
    "rfqItem_lic_poe_sellprice" character varying,
    "rfqItem_lic_poe_royalty" character varying,
    "rfqItem_lic_poe_netsell" character varying,
    "rfqItem_lic_poe_margin" character varying,
    "rfqItem_lic_fob_pricesale" character varying,
    "rfqItem_lic_fob_sellprice" character varying,
    "rfqItem_lic_fob_royalty" character varying,
    "rfqItem_lic_fob_netsell" character varying,
    "rfqItem_lic_fob_margin" character varying,
    "rfqItem_lic_whse_pricesale" character varying,
    "rfqItem_lic_whse_sellprice" character varying,
    "rfqItem_lic_whse_royalty" character varying,
    "rfqItem_lic_whse_netsell" character varying,
    "rfqItem_lic_whse_margin" character varying,
    "rfqItem_gen_whse_margin" character varying,
    "rfqItem_license" character varying,
    "rfqItem_royalty" double precision,
    "rfqItem_gen_fob_entered_sell_price" double precision,
    "rfqItem_gen_mddp_entered_sell_price" double precision,
    "rfqItem_gen_poe_entered_sell_price" double precision,
    "rfqItem_gen_whse_entered_sell_price" double precision,
    "rfqItem_lic_fob_entered_sell_price" double precision,
    "rfqItem_lic_mddp_entered_sell_price" double precision,
    "rfqItem_lic_poe_entered_sell_price" double precision,
    "rfqItem_lic_whse_entered_sell_price" double precision,
    "rfqItem_gen_fob_entered_margin" double precision,
    "rfqItem_gen_mddp_entered_margin" double precision,
    "rfqItem_gen_poe_entered_margin" double precision,
    "rfqItem_gen_whse_entered_margin" double precision,
    "rfqItem_lic_fob_entered_margin" double precision,
    "rfqItem_lic_poe_entered_margin" double precision,
    "rfqItem_lic_mddp_entered_margin" double precision,
    "rfqItem_lic_whse_entered_margin" double precision,
    "rfqItem_divCode_id_fk" character varying,
    "rfqItem_duty_rate_dollar_amount" character varying,
    "rfqItem_choosen_vendor" integer,
    "rfqItem_adam_fix" character varying,
    rfq_container_id_fk integer,
    "rfqItem_container_price" double precision,
    "rfqItem_copied_from_id" integer,
    "rfqItem_is_landed_cost_manual" boolean DEFAULT false NOT NULL,
    "rfqItem_requested_price_cells" text,
    "rfqItem_factories_step_at" timestamp without time zone,
    "rfqItem_copied_by" integer,
    "rfqItem_copied_on" timestamp with time zone,
    "rfqItem_duty_rate_equation" character varying(500),
    "rfqItem_price_sales_snapshots" text,
    "rfqItem_source_item_id" integer,
    "rfqItem_source_item_num" character varying(255)
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQItem"
    ADD CONSTRAINT "RFQItem_pkey" PRIMARY KEY ("rfqItem_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm."RFQItem"
    ADD CONSTRAINT "fk_rfqItem_copied_from" FOREIGN KEY ("rfqItem_copied_from_id") REFERENCES plm."RFQItem"("rfqItem_id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "idx_rfqItem_copied_from_id" ON plm."RFQItem" USING btree ("rfqItem_copied_from_id") WHERE ("rfqItem_copied_from_id" IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_rfqitem_choosen_vendor ON plm."RFQItem" USING btree ("rfqItem_choosen_vendor");

CREATE INDEX IF NOT EXISTS idx_rfqitem_container ON plm."RFQItem" USING btree (rfq_container_id_fk);

CREATE INDEX IF NOT EXISTS idx_rfqitem_customer ON plm."RFQItem" USING btree ("rfqItem_customer");

CREATE INDEX IF NOT EXISTS idx_rfqitem_delivery_loc ON plm."RFQItem" USING btree ("rfqItem_delivery_loc");

CREATE INDEX IF NOT EXISTS idx_rfqitem_divcode ON plm."RFQItem" USING btree ("rfqItem_divCode_id_fk");

CREATE INDEX IF NOT EXISTS idx_rfqitem_home_list ON plm."RFQItem" USING btree ("rfqItem_active", "rfqItem_id" DESC) WHERE ("rfqItem_archive" IS NULL);

CREATE INDEX IF NOT EXISTS idx_rfqitem_rfq_group ON plm."RFQItem" USING btree ("rfqItem_rfq_group");

CREATE INDEX IF NOT EXISTS idx_rfqitem_step ON plm."RFQItem" USING btree ("rfqItem_step");

COMMENT ON TABLE plm."RFQItem" IS 'RFQ line items';
