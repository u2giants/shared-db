-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `UIElements` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: UI permission tree
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app."UIElements" (
    "Id" integer NOT NULL,
    "Name" character varying(255) NOT NULL,
    "Type" character varying(50) NOT NULL,
    "ParentId" integer,
    CONSTRAINT "UIElements_Type_check" CHECK ((("Type")::text = ANY (ARRAY[('Tab'::character varying)::text, ('Menu'::character varying)::text, ('Submenu'::character varying)::text])))
);

DO $$ BEGIN
  ALTER TABLE ONLY app."UIElements"
    ADD CONSTRAINT "UIElements_pkey" PRIMARY KEY ("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY app."UIElements"
    ADD CONSTRAINT "UIElements_ParentId_fkey" FOREIGN KEY ("ParentId") REFERENCES app."UIElements"("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "UIElements_ParentId_fkey" ON app."UIElements" USING btree ("ParentId");

COMMENT ON TABLE app."UIElements" IS 'UI permission tree';
