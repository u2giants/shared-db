-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `artist_types` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Artist type reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.artist_types (
    id integer NOT NULL,
    code character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer
);

CREATE SEQUENCE IF NOT EXISTS core.artist_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core.artist_types_id_seq OWNED BY core.artist_types.id;

ALTER TABLE ONLY core.artist_types ALTER COLUMN id SET DEFAULT nextval('core.artist_types_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core.artist_types
    ADD CONSTRAINT artist_types_code_key UNIQUE (code);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artist_types
    ADD CONSTRAINT artist_types_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artist_types
    ADD CONSTRAINT artist_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artist_types
    ADD CONSTRAINT artist_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS artist_types_created_by_fkey ON core.artist_types USING btree (created_by);

CREATE INDEX IF NOT EXISTS artist_types_updated_by_fkey ON core.artist_types USING btree (updated_by);

COMMENT ON TABLE core.artist_types IS 'Artist type reference';
