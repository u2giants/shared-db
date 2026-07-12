-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `properties_and_characters` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Properties and characters discriminated by type column
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.properties_and_characters (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    licensor_id integer NOT NULL,
    source_licensed_property_id character varying(100),
    source_character_id character varying(100),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY core.properties_and_characters
    ADD CONSTRAINT properties_and_characters_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.properties_and_characters
    ADD CONSTRAINT properties_and_characters_licensor_id_fkey FOREIGN KEY (licensor_id) REFERENCES core."licenseList"("licenseList_id") ON UPDATE CASCADE ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_properties_licensor_id ON core.properties_and_characters USING btree (licensor_id);

CREATE INDEX IF NOT EXISTS idx_properties_name ON core.properties_and_characters USING btree (name);

CREATE UNIQUE INDEX IF NOT EXISTS unique_character_entity ON core.properties_and_characters USING btree (licensor_id, source_licensed_property_id, source_character_id) WHERE ((type)::text = 'CHARACTER'::text);

CREATE UNIQUE INDEX IF NOT EXISTS unique_property_entity ON core.properties_and_characters USING btree (licensor_id, source_licensed_property_id) WHERE ((type)::text = 'PROPERTY'::text);

COMMENT ON TABLE core.properties_and_characters IS 'Properties and characters discriminated by type column';
