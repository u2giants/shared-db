-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `item_character_associations` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Item â†” character links
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm.item_character_associations (
    id integer NOT NULL,
    item_header_id integer NOT NULL,
    character_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS plm.item_character_associations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm.item_character_associations_id_seq OWNED BY plm.item_character_associations.id;

ALTER TABLE ONLY plm.item_character_associations ALTER COLUMN id SET DEFAULT nextval('plm.item_character_associations_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm.item_character_associations
    ADD CONSTRAINT item_character_associations_item_header_id_key UNIQUE (item_header_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.item_character_associations
    ADD CONSTRAINT item_character_associations_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.item_character_associations
    ADD CONSTRAINT item_character_associations_character_id_fkey FOREIGN KEY (character_id) REFERENCES core.properties_and_characters(id) ON UPDATE CASCADE ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.item_character_associations
    ADD CONSTRAINT item_character_associations_item_header_id_fkey FOREIGN KEY (item_header_id) REFERENCES plm."itemHeader"(item_id_pk) ON UPDATE CASCADE ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_item_character_associations_character_id ON plm.item_character_associations USING btree (character_id);

COMMENT ON TABLE plm.item_character_associations IS 'Item â†” character links';
