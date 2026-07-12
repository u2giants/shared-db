-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `user_notification` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: User notifications
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.user_notification (
    id integer NOT NULL,
    type character varying,
    created_date date,
    event character varying,
    unread boolean,
    message character varying,
    title character varying,
    user_id_fk integer
);

DO $$ BEGIN
  ALTER TABLE ONLY app.user_notification
    ADD CONSTRAINT user_notification_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE app.user_notification IS 'User notifications';
