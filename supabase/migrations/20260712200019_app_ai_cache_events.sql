-- Additive: create DesignFlow table in shared schema app.
-- Mapped from DesignFlow `ai_cache_events` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.2.
-- Purpose: AI telemetry / cache events
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS app.ai_cache_events (
    id uuid NOT NULL,
    feature character varying(80) DEFAULT 'unknown'::character varying NOT NULL,
    provider character varying(40) NOT NULL,
    api_backend character varying(40) NOT NULL,
    model character varying(160) NOT NULL,
    cache_strategy character varying(40) NOT NULL,
    session_id character varying(160),
    telemetry_available boolean DEFAULT false NOT NULL,
    prompt_tokens integer DEFAULT 0 NOT NULL,
    cache_hit_tokens integer DEFAULT 0 NOT NULL,
    cache_miss_tokens integer DEFAULT 0 NOT NULL,
    cache_creation_tokens integer DEFAULT 0 NOT NULL,
    completion_tokens integer DEFAULT 0 NOT NULL,
    reasoning_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    cache_hit_rate_pct double precision DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

DO $$ BEGIN
  ALTER TABLE ONLY app.ai_cache_events
    ADD CONSTRAINT ai_cache_events_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS ai_cache_events_created_at_idx ON app.ai_cache_events USING btree (created_at DESC);

CREATE INDEX IF NOT EXISTS ai_cache_events_feature_created_at_idx ON app.ai_cache_events USING btree (feature, created_at DESC);

COMMENT ON TABLE app.ai_cache_events IS 'AI telemetry / cache events';
