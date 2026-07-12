-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `LicensingTime` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Licensor submission timing
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."LicensingTime" (
    id integer NOT NULL,
    licensor_name character varying(100) NOT NULL,
    submission_days integer DEFAULT 0,
    resubmission_days integer DEFAULT 0,
    pps_approval_days integer DEFAULT 0,
    total_days integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS plm."LicensingTime_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm."LicensingTime_id_seq" OWNED BY plm."LicensingTime".id;

ALTER TABLE ONLY plm."LicensingTime" ALTER COLUMN id SET DEFAULT nextval('plm."LicensingTime_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm."LicensingTime"
    ADD CONSTRAINT "LicensingTime_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."LicensingTime" IS 'Licensor submission timing';
