-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `RolePermissions` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: Links users/roles/UI elements
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app."RolePermissions" (
    "Id" integer NOT NULL,
    "RoleId" integer NOT NULL,
    "UserId" integer,
    "ElementId" integer NOT NULL,
    "Access" boolean NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY app."RolePermissions"
    ADD CONSTRAINT "RolePermissions_RoleId_UserId_ElementId_key" UNIQUE ("RoleId", "UserId", "ElementId");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY app."RolePermissions"
    ADD CONSTRAINT "RolePermissions_pkey" PRIMARY KEY ("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY app."RolePermissions"
    ADD CONSTRAINT "RolePermissions_ElementId_fkey" FOREIGN KEY ("ElementId") REFERENCES app."UIElements"("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY app."RolePermissions"
    ADD CONSTRAINT "RolePermissions_RoleId_fkey" FOREIGN KEY ("RoleId") REFERENCES app."Roles"("Id");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY app."RolePermissions"
    ADD CONSTRAINT "RolePermissions_UserId_fkey" FOREIGN KEY ("UserId") REFERENCES app.users(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "RolePermissions_ElementId_fkey" ON app."RolePermissions" USING btree ("ElementId");

CREATE INDEX IF NOT EXISTS "RolePermissions_RoleId_fkey" ON app."RolePermissions" USING btree ("RoleId");

CREATE INDEX IF NOT EXISTS "RolePermissions_UserId_fkey" ON app."RolePermissions" USING btree ("UserId");

CREATE UNIQUE INDEX IF NOT EXISTS "RolePermissions_unique_role_user_element" ON app."RolePermissions" USING btree ("RoleId", "UserId", "ElementId");

COMMENT ON TABLE app."RolePermissions" IS 'Links users/roles/UI elements';
