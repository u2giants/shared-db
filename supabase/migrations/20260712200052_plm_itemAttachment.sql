-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `itemAttachment` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Item file attachments
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."itemAttachment" (
    item_attachment_id integer NOT NULL,
    attachment_type character varying(50) NOT NULL,
    attachment_display_name character varying NOT NULL,
    attachment_link character varying NOT NULL,
    item_num_id_fk integer NOT NULL,
    "item_attachment_createdTime" character varying,
    "item_attachment_createdUser" character varying,
    "item_attachment_modTime" character varying,
    "item_attachment_modUser" character varying,
    "item_attachment_fileName" character varying,
    "companyCode_name" character varying,
    "divisionCode_name" character varying(100),
    "item_attachment_colorCode" character varying(100),
    "item_attachment_resourceId" integer,
    comment_id integer,
    uuid uuid,
    primary_image boolean DEFAULT false,
    licensing_attachment boolean,
    licensing_feedback_id_fk integer,
    license_status character varying,
    dsn_ref_num character varying(50)
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."itemAttachment"
    ADD CONSTRAINT "itemPackage_pkey" PRIMARY KEY (item_attachment_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."itemAttachment" IS 'Item file attachments';
