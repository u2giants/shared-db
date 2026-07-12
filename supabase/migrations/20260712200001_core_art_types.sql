-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `art_types` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Art type taxonomy (MG07 Art Type div 09)
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.art_types (
    id integer NOT NULL,
    code character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer,
    is_active boolean DEFAULT true NOT NULL,
    divisioncode_id integer NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS core.art_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core.art_types_id_seq OWNED BY core.art_types.id;

ALTER TABLE ONLY core.art_types ALTER COLUMN id SET DEFAULT nextval('core.art_types_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_code_key UNIQUE (code);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_name_key UNIQUE (name);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_divisioncode_id_fkey FOREIGN KEY (divisioncode_id) REFERENCES plm."divisionCode"("divCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.art_types
    ADD CONSTRAINT art_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS art_types_created_by_fkey ON core.art_types USING btree (created_by);

CREATE INDEX IF NOT EXISTS art_types_divisioncode_id_fkey ON core.art_types USING btree (divisioncode_id);

CREATE INDEX IF NOT EXISTS art_types_updated_by_fkey ON core.art_types USING btree (updated_by);

COMMENT ON TABLE core.art_types IS 'Art type taxonomy (MG07 Art Type div 09)';
