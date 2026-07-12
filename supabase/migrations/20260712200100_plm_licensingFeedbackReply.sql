-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `licensingFeedbackReply` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Licensing feedback replies
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."licensingFeedbackReply" (
    id integer NOT NULL,
    licensing_status_id_fk integer NOT NULL,
    comment text NOT NULL,
    created_by integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tagged_user_ids jsonb DEFAULT '[]'::jsonb,
    attachments jsonb DEFAULT '[]'::jsonb
);

CREATE SEQUENCE IF NOT EXISTS plm."licensingFeedbackReply_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE plm."licensingFeedbackReply_id_seq" OWNED BY plm."licensingFeedbackReply".id;

ALTER TABLE ONLY plm."licensingFeedbackReply" ALTER COLUMN id SET DEFAULT nextval('plm."licensingFeedbackReply_id_seq"'::regclass);

DO $$ BEGIN
  ALTER TABLE ONLY plm."licensingFeedbackReply"
    ADD CONSTRAINT "licensingFeedbackReply_pkey" PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE ONLY plm."licensingFeedbackReply"
    ADD CONSTRAINT "licensingFeedbackReply_licensing_status_id_fk_fkey" FOREIGN KEY (licensing_status_id_fk) REFERENCES plm."licensingStatus"(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_licensing_feedback_reply_status ON plm."licensingFeedbackReply" USING btree (licensing_status_id_fk);

COMMENT ON TABLE plm."licensingFeedbackReply" IS 'Licensing feedback replies';
