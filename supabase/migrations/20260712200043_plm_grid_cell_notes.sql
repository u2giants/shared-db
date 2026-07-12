-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `grid_cell_notes` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Cell-level notes
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm.grid_cell_notes (
    id uuid NOT NULL,
    grid_type character varying(50) NOT NULL,
    row_id character varying(255) NOT NULL,
    col_id character varying(255) NOT NULL,
    note_text text,
    note_author character varying(255),
    note_read_only boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY plm.grid_cell_notes
    ADD CONSTRAINT grid_cell_notes_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS grid_cell_notes_grid_row_col_uq ON plm.grid_cell_notes USING btree (grid_type, row_id, col_id);

CREATE INDEX IF NOT EXISTS grid_cell_notes_grid_type_idx ON plm.grid_cell_notes USING btree (grid_type);

COMMENT ON TABLE plm.grid_cell_notes IS 'Cell-level notes';
