-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `GridChildrenLayoutOrder` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Column order
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."GridChildrenLayoutOrder" (
    id integer NOT NULL,
    field character varying,
    layout_name character varying,
    user_id_fk integer,
    col_order integer,
    hide character varying,
    "cellRenderer" character varying,
    "checkboxSelection" character varying,
    "rowDrag" character varying,
    "rowGroup" character varying,
    width integer,
    col_pinned character varying,
    "GridLayout_id_fk" character varying,
    grid_id character varying,
    std_prod_id_fk integer,
    "columnGroupShow" character varying,
    "headerName" character varying,
    factory_id_fk integer,
    filter character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."GridChildrenLayoutOrder"
    ADD CONSTRAINT "GridChildrenLayoutOrder_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."GridChildrenLayoutOrder" IS 'Column order';
