-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `property_character_associations` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Property â†” character â†” licensor junction
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.property_character_associations (
    property_id integer NOT NULL,
    character_id integer NOT NULL,
    licensor_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE ONLY core.property_character_associations
    ADD CONSTRAINT property_character_associations_pkey PRIMARY KEY (property_id, character_id, licensor_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.property_character_associations
    ADD CONSTRAINT property_character_associations_character_id_fkey FOREIGN KEY (character_id) REFERENCES core.properties_and_characters(id) ON UPDATE CASCADE ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.property_character_associations
    ADD CONSTRAINT property_character_associations_licensor_id_fkey FOREIGN KEY (licensor_id) REFERENCES core."licenseList"("licenseList_id") ON UPDATE CASCADE ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.property_character_associations
    ADD CONSTRAINT property_character_associations_property_id_fkey FOREIGN KEY (property_id) REFERENCES core.properties_and_characters(id) ON UPDATE CASCADE ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_property_character_associations_character_id ON core.property_character_associations USING btree (character_id);

CREATE INDEX IF NOT EXISTS idx_property_character_associations_licensor_id ON core.property_character_associations USING btree (licensor_id);

CREATE INDEX IF NOT EXISTS idx_property_character_associations_property_id ON core.property_character_associations USING btree (property_id);

COMMENT ON TABLE core.property_character_associations IS 'Property â†” character â†” licensor junction';
