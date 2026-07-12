-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `groups` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Tagged user groups (Teams integration)
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm.groups (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    member_user_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    teams_chat_id character varying(255),
    teams_conversation_id character varying(255),
    teams_service_url character varying(500),
    teams_app_installed_at timestamp with time zone,
    teams_members_hash character varying(64),
    teams_sync_status character varying(50),
    teams_sync_error text,
    teams_conversation_reference jsonb
);

CREATE SEQUENCE IF NOT EXISTS plm.groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm.groups_id_seq OWNED BY plm.groups.id;

ALTER TABLE ONLY plm.groups ALTER COLUMN id SET DEFAULT nextval('plm.groups_id_seq'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE plm.groups IS 'Tagged user groups (Teams integration)';
