-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `merchGroupRelations` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Parent/child MG hierarchy metadata
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."merchGroupRelations" (
    id integer NOT NULL,
    grand_parent_mg_id integer,
    parent_mg_id integer NOT NULL,
    child_mg_id integer NOT NULL,
    "divisionCode_id_fk" integer NOT NULL,
    "createdTime" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "createdUser" integer NOT NULL,
    "modTime" timestamp without time zone,
    "modUser" integer,
    is_active boolean DEFAULT true,
    CONSTRAINT "merchGroupRelations_check" CHECK ((parent_mg_id <> child_mg_id))
);

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupRelations"
    ADD CONSTRAINT "merchGroupRelations_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupRelations"
    ADD CONSTRAINT "merchGroupRelations_child_mg_id_fkey" FOREIGN KEY (child_mg_id) REFERENCES core."merchGroupMaster"(mg_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupRelations"
    ADD CONSTRAINT "merchGroupRelations_grand_parent_mg_id_fkey" FOREIGN KEY (grand_parent_mg_id) REFERENCES core."merchGroupMaster"(mg_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core."merchGroupRelations"
    ADD CONSTRAINT "merchGroupRelations_parent_mg_id_fkey" FOREIGN KEY (parent_mg_id) REFERENCES core."merchGroupMaster"(mg_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_relations_child ON core."merchGroupRelations" USING btree (child_mg_id);

CREATE INDEX IF NOT EXISTS idx_relations_grand_parent ON core."merchGroupRelations" USING btree (grand_parent_mg_id);

CREATE INDEX IF NOT EXISTS idx_relations_parent ON core."merchGroupRelations" USING btree (parent_mg_id);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_grand_parent_parent_child ON core."merchGroupRelations" USING btree (grand_parent_mg_id, parent_mg_id, child_mg_id);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_parent_child_no_grand ON core."merchGroupRelations" USING btree (parent_mg_id, child_mg_id) WHERE (grand_parent_mg_id IS NULL);

COMMENT ON TABLE core."merchGroupRelations" IS 'Parent/child MG hierarchy metadata';
