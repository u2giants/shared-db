-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `users` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: PLM users; map to app.profile + Auth cross-ref; do not copy passw
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.users (
    id integer NOT NULL,
    name character varying(255),
    email character varying(255),
    level character varying(255),
    notes character varying(255),
    passw character varying(255),
    expire character varying(255),
    status character varying(255),
    adddate character varying(255),
    auditlog character varying(255),
    lastname character varying(255),
    phonenum character varying(255),
    subscription character varying(255),
    subleveladmin character varying(255),
    notificationsms character varying(255),
    notificationemail character varying(255),
    _airbyte_emitted_at timestamp with time zone,
    _airbyte_users_hashid text,
    profile_photo text,
    graph_photo text,
    graph_photo_synced_at timestamp with time zone
);

DO $$ BEGIN
  ALTER TABLE ONLY app.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app.users IS 'PLM users; map to app.profile + Auth cross-ref; do not copy passw';
