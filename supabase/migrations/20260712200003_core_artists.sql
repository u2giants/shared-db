-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `artists` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Shared artist lookup
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.artists (
    id integer NOT NULL,
    name text NOT NULL,
    email text,
    art_source_id integer,
    artist_type_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer,
    is_active boolean DEFAULT true NOT NULL,
    divisioncode_id integer
);

CREATE SEQUENCE IF NOT EXISTS core.artists_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core.artists_id_seq OWNED BY core.artists.id;

ALTER TABLE ONLY core.artists ALTER COLUMN id SET DEFAULT nextval('core.artists_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_art_source_id_fkey FOREIGN KEY (art_source_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_artist_type_id_fkey FOREIGN KEY (artist_type_id) REFERENCES core.artist_types(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_divisioncode_id_fkey FOREIGN KEY (divisioncode_id) REFERENCES plm."divisionCode"("divCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.artists
    ADD CONSTRAINT artists_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS artists_art_source_id_fkey ON core.artists USING btree (art_source_id);

CREATE INDEX IF NOT EXISTS artists_artist_type_id_fkey ON core.artists USING btree (artist_type_id);

CREATE INDEX IF NOT EXISTS artists_created_by_fkey ON core.artists USING btree (created_by);

CREATE INDEX IF NOT EXISTS artists_divisioncode_id_fkey ON core.artists USING btree (divisioncode_id);

CREATE INDEX IF NOT EXISTS artists_updated_by_fkey ON core.artists USING btree (updated_by);

COMMENT ON TABLE core.artists IS 'Shared artist lookup';
