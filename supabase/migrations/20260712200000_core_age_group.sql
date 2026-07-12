-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `age_group` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: Shared age-group reference for items/art
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.age_group (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer
);

CREATE SEQUENCE IF NOT EXISTS core.age_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core.age_group_id_seq OWNED BY core.age_group.id;

ALTER TABLE ONLY core.age_group ALTER COLUMN id SET DEFAULT nextval('core.age_group_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core.age_group
    ADD CONSTRAINT age_group_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.age_group
    ADD CONSTRAINT age_group_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY core.age_group
    ADD CONSTRAINT age_group_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS age_group_created_by_fkey ON core.age_group USING btree (created_by);

CREATE INDEX IF NOT EXISTS age_group_updated_by_fkey ON core.age_group USING btree (updated_by);

COMMENT ON TABLE core.age_group IS 'Shared age-group reference for items/art';
