-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `LicensingTimes` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Legacy parallel licensing time table
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."LicensingTimes" (
    id integer NOT NULL,
    linesheet_submission_time integer,
    linesheet_resubmission_time integer,
    submission_time integer,
    resubmission_time integer,
    pps_approval_time integer,
    licensor_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."LicensingTimes"
    ADD CONSTRAINT "LicensingTimes_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."LicensingTimes" IS 'Legacy parallel licensing time table';
