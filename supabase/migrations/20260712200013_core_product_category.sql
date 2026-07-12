-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `product_category` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: PM/DAM/PLM shared product category taxonomy
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core.product_category (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer NOT NULL,
    updated_at timestamp with time zone,
    updated_by integer,
    is_active boolean DEFAULT true
);

CREATE SEQUENCE IF NOT EXISTS core.product_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE core.product_category_id_seq OWNED BY core.product_category.id;

ALTER TABLE ONLY core.product_category ALTER COLUMN id SET DEFAULT nextval('core.product_category_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT product_category_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS product_category_created_by_fkey ON core.product_category USING btree (created_by);

CREATE INDEX IF NOT EXISTS product_category_updated_by_fkey ON core.product_category USING btree (updated_by);

COMMENT ON TABLE core.product_category IS 'PM/DAM/PLM shared product category taxonomy';
