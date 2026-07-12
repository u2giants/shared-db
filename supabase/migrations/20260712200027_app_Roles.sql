-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `Roles` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: Application roles
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app."Roles" (
    "Id" integer NOT NULL,
    "Name" character varying(255) NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY app."Roles"
    ADD CONSTRAINT "Roles_pkey" PRIMARY KEY ("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app."Roles" IS 'Application roles';
