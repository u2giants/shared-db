-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `DesignTeamTime` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Design/production time tracking
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."DesignTeamTime" (
    id integer NOT NULL,
    product_category character varying(100),
    product_subtype character varying(200) NOT NULL,
    brief_mins integer DEFAULT 0,
    design_mins integer DEFAULT 0,
    techpack_mins integer DEFAULT 0,
    revision_mins integer DEFAULT 0,
    files_mins integer DEFAULT 0,
    total_hours numeric(10,4),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS plm."DesignTeamTime_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm."DesignTeamTime_id_seq" OWNED BY plm."DesignTeamTime".id;

ALTER TABLE ONLY plm."DesignTeamTime" ALTER COLUMN id SET DEFAULT nextval('plm."DesignTeamTime_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm."DesignTeamTime"
    ADD CONSTRAINT "DesignTeamTime_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."DesignTeamTime" IS 'Design/production time tracking';
