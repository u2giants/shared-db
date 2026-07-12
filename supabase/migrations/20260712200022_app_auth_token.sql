-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `auth_token` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: PLM session tokens; service-role only
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.auth_token (
    id integer NOT NULL,
    email character varying,
    token character varying,
    status boolean
);

DO $$ BEGIN
  ALTER TABLE ONLY app.auth_token
    ADD CONSTRAINT "signUpToken_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app.auth_token IS 'PLM session tokens; service-role only';
