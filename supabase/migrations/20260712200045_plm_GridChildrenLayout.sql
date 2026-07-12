-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `GridChildrenLayout` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Child column layout
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."GridChildrenLayout" (
    id integer NOT NULL,
    field character varying NOT NULL,
    filter character varying,
    hide character varying,
    "cellRenderer" character varying,
    "checkboxSelection" character varying,
    "rowDrag" character varying,
    "rowGroup" character varying,
    width integer,
    col_pinned character varying,
    col_order integer,
    user_id_fk integer,
    layout_name character varying,
    "GridLayout_id_fk" integer,
    grid_id character varying,
    std_prod_id_fk integer,
    "columnGroupShow" character varying,
    "headerName" character varying,
    factory_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."GridChildrenLayout"
    ADD CONSTRAINT "GridChildrenLayout_pkey" PRIMARY KEY (field);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."GridChildrenLayout" IS 'Child column layout';
