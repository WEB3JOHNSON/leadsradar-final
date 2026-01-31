-- ============================================
-- LeadsRadar Database Schema - Section 1
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- 1. CREATE ENUMS
-- ============================================

-- Lead pipeline status
CREATE TYPE lead_status AS ENUM ('Found', 'Contacted', 'Negotiating', 'Won', 'Lost');

-- API key status
CREATE TYPE api_key_status AS ENUM ('active', 'revoked', 'expired');


-- ============================================
-- 2. PROFILES TABLE
-- Links to Supabase auth.users
-- ============================================

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    bio TEXT CHECK (char_length(bio) <= 500),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    deleted_at TIMESTAMPTZ -- Soft delete
);

-- Indexes for profiles
CREATE INDEX idx_profiles_email_active ON profiles(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_deleted ON profiles(deleted_at) WHERE deleted_at IS NOT NULL;

COMMENT ON TABLE profiles IS 'User profiles linked to Supabase auth';
COMMENT ON COLUMN profiles.bio IS 'User bio for AI pitch personalization (max 500 chars)';
COMMENT ON COLUMN profiles.deleted_at IS 'Soft delete timestamp - NULL means active';


-- ============================================
-- 3. API_KEYS TABLE
-- For webhook authentication
-- ============================================

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    key_prefix TEXT NOT NULL, -- First 16 chars for display: "ldr_live_abc123..."
    key_hash TEXT NOT NULL, -- bcrypt hash of full key
    name TEXT NOT NULL CHECK (char_length(name) <= 50), -- User-friendly name
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ, -- NULL = never expires
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    revoked_at TIMESTAMPTZ -- NULL = not revoked
    -- Note: status is computed at query time, not stored
    -- Use: CASE WHEN revoked_at IS NOT NULL THEN 'revoked' 
    --           WHEN expires_at < NOW() THEN 'expired' 
    --           ELSE 'active' END
);

-- Unique constraint: user can't have duplicate key names (only for active keys)
CREATE UNIQUE INDEX idx_api_keys_user_name_active 
    ON api_keys(user_id, name) 
    WHERE revoked_at IS NULL;

-- Fast lookup by prefix
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);

-- Find non-revoked keys for a user (expiry checked at query time)
CREATE INDEX idx_api_keys_user_active ON api_keys(user_id) WHERE revoked_at IS NULL;

COMMENT ON TABLE api_keys IS 'API keys for webhook authentication';
COMMENT ON COLUMN api_keys.key_hash IS 'bcrypt hash - full key is NEVER stored';
COMMENT ON COLUMN api_keys.key_prefix IS 'First 16 chars for display (e.g., ldr_live_abc123)';


-- ============================================
-- 4. LEADS TABLE
-- Twitter leads with audit trail
-- ============================================

CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    
    -- Tweet data
    tweet_id VARCHAR(30) NOT NULL CHECK (tweet_id ~ '^[0-9]+$'), -- Numeric only
    tweet_text TEXT NOT NULL CHECK (char_length(tweet_text) BETWEEN 1 AND 500),
    tweet_author VARCHAR(100) NOT NULL CHECK (tweet_author ~ '^[a-zA-Z0-9_]{1,15}$'), -- Twitter username format
    tweet_url TEXT GENERATED ALWAYS AS (
        'https://twitter.com/' || tweet_author || '/status/' || tweet_id
    ) STORED,
    
    -- Lead metadata
    status lead_status DEFAULT 'Found' NOT NULL,
    spam_score INT DEFAULT 0 CHECK (spam_score BETWEEN 0 AND 100),
    estimated_value INT DEFAULT 0 CHECK (estimated_value BETWEEN 0 AND 1000000),
    
    -- Status timestamps
    contacted_at TIMESTAMPTZ,
    won_at TIMESTAMPTZ,
    lost_at TIMESTAMPTZ,
    
    -- Source tracking
    source VARCHAR(50) DEFAULT 'webhook',
    source_metadata JSONB,
    
    -- Audit fields
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_by UUID REFERENCES profiles(id),
    version INT DEFAULT 1 NOT NULL, -- Optimistic locking
    deleted_at TIMESTAMPTZ, -- Soft delete
    
    -- Status consistency constraints
    CONSTRAINT chk_contacted_timestamp CHECK (
        status != 'Contacted' OR contacted_at IS NOT NULL
    ),
    CONSTRAINT chk_won_timestamp CHECK (
        status != 'Won' OR won_at IS NOT NULL
    ),
    CONSTRAINT chk_lost_timestamp CHECK (
        status != 'Lost' OR lost_at IS NOT NULL
    )
);

-- CRITICAL: Partial unique index for soft delete support
-- This allows re-adding leads that were previously deleted
CREATE UNIQUE INDEX leads_user_tweet_unique 
    ON leads(user_id, tweet_id) 
    WHERE deleted_at IS NULL;

-- Performance indexes
CREATE INDEX idx_leads_user_status ON leads(user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_leads_user_created ON leads(user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_leads_user_contacted ON leads(user_id, contacted_at) 
    WHERE deleted_at IS NULL AND status = 'Contacted';
CREATE INDEX idx_leads_tweet ON leads(tweet_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_leads_deleted ON leads(deleted_at) WHERE deleted_at IS NOT NULL;

COMMENT ON TABLE leads IS 'Twitter leads from webhook ingestion';
COMMENT ON COLUMN leads.version IS 'For optimistic locking - increments on each update';
COMMENT ON COLUMN leads.tweet_url IS 'Auto-generated URL to the original tweet';


-- ============================================
-- 5. WEBHOOK_EVENTS TABLE
-- Complete audit trail for debugging
-- ============================================

CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    api_key_id UUID REFERENCES api_keys(id) ON DELETE SET NULL,
    request_id UUID UNIQUE NOT NULL, -- For distributed tracing
    
    -- Request data
    signature TEXT,
    signature_valid BOOLEAN,
    payload JSONB NOT NULL,
    headers JSONB,
    ip_address INET,
    
    -- Processing status
    processed BOOLEAN DEFAULT FALSE,
    processed_at TIMESTAMPTZ,
    lead_id UUID REFERENCES leads(id) ON DELETE SET NULL,
    
    -- Error tracking
    error_message TEXT,
    error_stack TEXT,
    retry_count INT DEFAULT 0,
    
    received_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for webhook_events
CREATE INDEX idx_webhook_user_received ON webhook_events(user_id, received_at DESC);
CREATE INDEX idx_webhook_unprocessed ON webhook_events(processed, received_at) WHERE NOT processed;
CREATE INDEX idx_webhook_errors ON webhook_events(received_at DESC) WHERE error_message IS NOT NULL;

COMMENT ON TABLE webhook_events IS 'Complete audit trail of all webhook requests';
COMMENT ON COLUMN webhook_events.request_id IS 'Unique ID for distributed tracing and replay prevention';


-- ============================================
-- 6. API_USAGE_LOGS TABLE
-- Cost tracking for OpenAI
-- ============================================

CREATE TABLE api_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    request_id UUID NOT NULL,
    
    -- Request info
    endpoint VARCHAR(100) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status_code INT NOT NULL,
    
    -- OpenAI usage
    model VARCHAR(50),
    prompt_tokens INT,
    completion_tokens INT,
    total_tokens INT,
    estimated_cost DECIMAL(10, 6), -- In USD
    
    -- Result
    success BOOLEAN,
    error_type VARCHAR(100),
    latency_ms INT,
    
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for api_usage_logs
CREATE INDEX idx_usage_user_created ON api_usage_logs(user_id, created_at DESC);
CREATE INDEX idx_usage_endpoint ON api_usage_logs(endpoint, created_at DESC);
CREATE INDEX idx_usage_time ON api_usage_logs(created_at); -- Time-series queries

COMMENT ON TABLE api_usage_logs IS 'Tracks all API calls for cost monitoring';
COMMENT ON COLUMN api_usage_logs.estimated_cost IS 'Estimated cost in USD based on token usage';


-- ============================================
-- 7. RATE_LIMIT_USAGE TABLE
-- Rate limiting counters
-- ============================================

CREATE TABLE rate_limit_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    resource_type VARCHAR(50) NOT NULL, -- 'pitch_generation', 'webhook_ingestion'
    
    -- Counters
    count_hourly INT DEFAULT 0,
    count_daily INT DEFAULT 0,
    
    -- Reset timestamps
    last_reset_hour TIMESTAMPTZ DEFAULT date_trunc('hour', NOW()),
    last_reset_date DATE DEFAULT CURRENT_DATE,
    
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- One row per user per resource type
    CONSTRAINT rate_limit_user_resource_unique UNIQUE (user_id, resource_type)
);

-- Index for fast lookup
CREATE INDEX idx_rate_limit_user ON rate_limit_usage(user_id);

COMMENT ON TABLE rate_limit_usage IS 'Tracks rate limit usage per user per resource';


-- ============================================
-- 8. AUTO-UPDATE TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to profiles
CREATE TRIGGER trigger_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Apply to leads
CREATE TRIGGER trigger_leads_updated_at
    BEFORE UPDATE ON leads
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Apply to rate_limit_usage
CREATE TRIGGER trigger_rate_limit_updated_at
    BEFORE UPDATE ON rate_limit_usage
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();


-- ============================================
-- 9. VERSION INCREMENT TRIGGER (Optimistic Locking)
-- ============================================

CREATE OR REPLACE FUNCTION increment_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to leads
CREATE TRIGGER trigger_leads_increment_version
    BEFORE UPDATE ON leads
    FOR EACH ROW
    EXECUTE FUNCTION increment_version();


-- ============================================
-- VERIFICATION QUERIES
-- Run these after migration to verify success
-- ============================================

-- Check enums exist
-- SELECT enum_range(NULL::lead_status);
-- Expected: {Found,Contacted,Negotiating,Won,Lost}

-- SELECT enum_range(NULL::api_key_status);
-- Expected: {active,revoked,expired}

-- Check tables exist
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_schema = 'public' 
-- ORDER BY table_name;
-- Expected: api_keys, api_usage_logs, leads, profiles, rate_limit_usage, webhook_events

-- ============================================
-- END OF SECTION 1 MIGRATION
-- ============================================
