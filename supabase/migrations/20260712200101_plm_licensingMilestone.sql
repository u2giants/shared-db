-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `licensingMilestone` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Licensing milestones
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."licensingMilestone" (
    id integer NOT NULL,
    itemheader_id_fk integer NOT NULL,
    stage character varying(50) NOT NULL,
    milestone_date timestamp without time zone NOT NULL,
    checked_by_user_id integer,
    checked_by_name character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);

CREATE SEQUENCE IF NOT EXISTS plm."licensingMilestone_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm."licensingMilestone_id_seq" OWNED BY plm."licensingMilestone".id;

ALTER TABLE ONLY plm."licensingMilestone" ALTER COLUMN id SET DEFAULT nextval('plm."licensingMilestone_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm."licensingMilestone"
    ADD CONSTRAINT "licensingMilestone_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm."licensingMilestone"
    ADD CONSTRAINT unique_item_stage_designflow_1774369813518 UNIQUE (itemheader_id_fk, stage);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS unique_item_stage ON plm."licensingMilestone" USING btree (itemheader_id_fk, stage);

COMMENT ON TABLE plm."licensingMilestone" IS 'Licensing milestones';
