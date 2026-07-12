-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `art_piece_attachment` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Art piece files
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm.art_piece_attachment (
    id integer NOT NULL,
    uuid uuid NOT NULL,
    type character varying(100),
    display_type character varying(50),
    primary_image boolean DEFAULT true NOT NULL,
    link character varying(255),
    file_name character varying(255),
    company_code integer NOT NULL,
    divisioncode_id integer NOT NULL,
    art_piece_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer,
    is_active boolean DEFAULT true NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS plm.art_piece_attachment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm.art_piece_attachment_id_seq OWNED BY plm.art_piece_attachment.id;

ALTER TABLE ONLY plm.art_piece_attachment ALTER COLUMN id SET DEFAULT nextval('plm.art_piece_attachment_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_art_piece_id_fkey FOREIGN KEY (art_piece_id) REFERENCES plm.art_piece(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_company_code_fkey FOREIGN KEY (company_code) REFERENCES plm."companyCode"("comCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_divisioncode_id_fkey FOREIGN KEY (divisioncode_id) REFERENCES plm."divisionCode"("divCode_id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm.art_piece_attachment
    ADD CONSTRAINT art_piece_attachment_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS art_piece_attachment_art_piece_id_fkey ON plm.art_piece_attachment USING btree (art_piece_id);

CREATE INDEX IF NOT EXISTS art_piece_attachment_company_code_fkey ON plm.art_piece_attachment USING btree (company_code);

CREATE INDEX IF NOT EXISTS art_piece_attachment_created_by_fkey ON plm.art_piece_attachment USING btree (created_by);

CREATE INDEX IF NOT EXISTS art_piece_attachment_divisioncode_id_fkey ON plm.art_piece_attachment USING btree (divisioncode_id);

CREATE INDEX IF NOT EXISTS art_piece_attachment_updated_by_fkey ON plm.art_piece_attachment USING btree (updated_by);

COMMENT ON TABLE plm.art_piece_attachment IS 'Art piece files';
