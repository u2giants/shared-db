-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `quote_auth_token` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: Quote session tokens
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.quote_auth_token (
    id integer NOT NULL,
    initiated_token character varying,
    start_date timestamp without time zone,
    expired_date timestamp without time zone,
    user_email character varying,
    replaced_token character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY app.quote_auth_token
    ADD CONSTRAINT auth_token_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS quote_auth_token_pkey ON app.quote_auth_token USING btree (id);

COMMENT ON TABLE app.quote_auth_token IS 'Quote session tokens';
