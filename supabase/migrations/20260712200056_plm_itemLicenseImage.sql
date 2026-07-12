-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `itemLicenseImage` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Licensing phase images
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."itemLicenseImage" (
    id integer NOT NULL,
    itemheader_id_fk integer NOT NULL,
    phase character varying,
    image_link character varying NOT NULL,
    thumb_link character varying,
    created_user character varying,
    created_time timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."itemLicenseImage"
    ADD CONSTRAINT "itemLicenseImage_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm."itemLicenseImage"
    ADD CONSTRAINT "itemLicenseImage_itemheader_id_fk_fkey" FOREIGN KEY (itemheader_id_fk) REFERENCES plm."itemHeader"(item_id_pk) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "idx_itemLicenseImage_item" ON plm."itemLicenseImage" USING btree (itemheader_id_fk);

CREATE INDEX IF NOT EXISTS idx_itemlicenseimage_item ON plm."itemLicenseImage" USING btree (itemheader_id_fk);

COMMENT ON TABLE plm."itemLicenseImage" IS 'Licensing phase images';
