-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `FactoryTimes` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Legacy parallel factory time table
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."FactoryTimes" (
    id integer NOT NULL,
    sampling_time integer,
    resampling_time integer,
    mass_production_time integer,
    nickname_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY plm."FactoryTimes"
    ADD CONSTRAINT "FactoryTimes_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm."FactoryTimes" IS 'Legacy parallel factory time table';
