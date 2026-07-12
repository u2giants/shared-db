-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `art_piece` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Operational art records; FKs to core + merchGroup
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm.art_piece (
    id integer NOT NULL,
    art_description text,
    art_display_description character varying(255),
    licensor_id integer,
    property_id integer,
    style_guide_id integer,
    big_theme_id integer,
    little_theme_id integer,
    art_type_id integer,
    art_source_id integer,
    artist_id integer,
    season_code_id integer,
    age_group_id integer,
    divisioncode_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer,
    is_active boolean DEFAULT true,
    tags character varying(500),
    art_number character varying(50)
);

CREATE SEQUENCE IF NOT EXISTS plm.art_piece_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm.art_piece_id_seq OWNED BY plm.art_piece.id;

ALTER TABLE ONLY plm.art_piece ALTER COLUMN id SET DEFAULT nextval('plm.art_piece_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_art_number_key UNIQUE (art_number);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_age_group_id_fkey FOREIGN KEY (age_group_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_art_source_id_fkey FOREIGN KEY (art_source_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_art_type_id_fkey FOREIGN KEY (art_type_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_artist_id_fkey FOREIGN KEY (artist_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_big_theme_id_fkey FOREIGN KEY (big_theme_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_divisioncode_id_fkey FOREIGN KEY (divisioncode_id) REFERENCES plm."divisionCode"("divCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_licensor_id_fkey FOREIGN KEY (licensor_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_little_theme_id_fkey FOREIGN KEY (little_theme_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_property_id_fkey FOREIGN KEY (property_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_season_code_id_fkey FOREIGN KEY (season_code_id) REFERENCES plm."SeasonCode"(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_style_guide_id_fkey FOREIGN KEY (style_guide_id) REFERENCES core."merchGroup"(mg_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece
    ADD CONSTRAINT art_piece_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS art_piece_created_by_fkey ON plm.art_piece USING btree (created_by);

CREATE INDEX IF NOT EXISTS art_piece_divisioncode_id_fkey ON plm.art_piece USING btree (divisioncode_id);

CREATE INDEX IF NOT EXISTS art_piece_updated_by_fkey ON plm.art_piece USING btree (updated_by);

CREATE INDEX IF NOT EXISTS fki_art_piece_artist_id_fkey ON plm.art_piece USING btree (artist_id);

COMMENT ON TABLE plm.art_piece IS 'Operational art records; FKs to core + merchGroup';
