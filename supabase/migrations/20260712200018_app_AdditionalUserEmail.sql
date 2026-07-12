-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `AdditionalUserEmail` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: Additional emails for users
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app."AdditionalUserEmail" (
    id integer NOT NULL,
    email character varying,
    "userType" character varying,
    user_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY app."AdditionalUserEmail"
    ADD CONSTRAINT "AdditionalUserEmail_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app."AdditionalUserEmail" IS 'Additional emails for users';
