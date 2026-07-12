-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `app_settings` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: Application settings
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.app_settings (
    key character varying(100) NOT NULL,
    value text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE ONLY app.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app.app_settings IS 'Application settings';
