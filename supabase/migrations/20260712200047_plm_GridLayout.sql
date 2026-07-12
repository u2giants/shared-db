-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `GridLayout` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: AG Grid column layout
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."GridLayout" (
    id integer NOT NULL,
    field character varying,
    filter character varying,
    hide character varying,
    "cellRenderer" character varying,
    "checkboxSelection" character varying,
    "rowDrag" character varying,
    "rowGroup" character varying,
    width integer,
    "companyCode_name" character varying,
    "divisionCode_name" character varying,
    col_pinned character varying,
    col_order integer,
    user_id_fk integer,
    layout_name character varying,
    col_id character varying,
    grid_id character varying,
    "headerName" character varying,
    std_prod_id_fk integer,
    editable boolean,
    "cellEditor" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."GridLayout"
    ADD CONSTRAINT "RFQLayout_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "GridLayout_pkey" ON plm."GridLayout" USING btree (id);

COMMENT ON TABLE plm."GridLayout" IS 'AG Grid column layout';
