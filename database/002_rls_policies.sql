-- ============================================
-- LeadsRadar RLS Policies - Section 2
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- 1. ENABLE RLS ON ALL TABLES
-- ============================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limit_usage ENABLE ROW LEVEL SECURITY;


-- ============================================
-- 2. PROFILES POLICIES
-- ============================================

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

-- Users can insert their own profile (during signup)
CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- Service role can manage all profiles
CREATE POLICY "Service role can manage all profiles"
    ON profiles FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- 3. API_KEYS POLICIES
-- ============================================

-- Users can view their own API keys
CREATE POLICY "Users can view own API keys"
    ON api_keys FOR SELECT
    USING (user_id = auth.uid());

-- Users can create their own API keys
CREATE POLICY "Users can create own API keys"
    ON api_keys FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can update their own API keys (for revoking)
CREATE POLICY "Users can update own API keys"
    ON api_keys FOR UPDATE
    USING (user_id = auth.uid());

-- Users can delete their own API keys
CREATE POLICY "Users can delete own API keys"
    ON api_keys FOR DELETE
    USING (user_id = auth.uid());

-- Service role can manage all API keys
CREATE POLICY "Service role can manage all API keys"
    ON api_keys FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- 4. LEADS POLICIES
-- ============================================

-- Users can view their own leads (excluding soft-deleted)
CREATE POLICY "Users can view own leads"
    ON leads FOR SELECT
    USING (user_id = auth.uid() AND deleted_at IS NULL);

-- Users can create their own leads
CREATE POLICY "Users can create own leads"
    ON leads FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can update their own leads (including soft delete)
CREATE POLICY "Users can update own leads"
    ON leads FOR UPDATE
    USING (user_id = auth.uid());

-- Service role can manage all leads
CREATE POLICY "Service role can manage all leads"
    ON leads FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- 5. WEBHOOK_EVENTS POLICIES
-- ============================================

-- Users can view their own webhook events (for debugging)
CREATE POLICY "Users can view own webhook events"
    ON webhook_events FOR SELECT
    USING (user_id = auth.uid());

-- Service role can manage all webhook events
CREATE POLICY "Service role can manage all webhook events"
    ON webhook_events FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- 6. API_USAGE_LOGS POLICIES
-- ============================================

-- Users can view their own usage logs
CREATE POLICY "Users can view own usage logs"
    ON api_usage_logs FOR SELECT
    USING (user_id = auth.uid());

-- Service role can insert usage logs (from API routes)
CREATE POLICY "Service role can manage usage logs"
    ON api_usage_logs FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- 7. RATE_LIMIT_USAGE POLICIES
-- ============================================

-- Users can view their own rate limits
CREATE POLICY "Users can view own rate limits"
    ON rate_limit_usage FOR SELECT
    USING (user_id = auth.uid());

-- Service role can manage all rate limits
CREATE POLICY "Service role can manage rate limits"
    ON rate_limit_usage FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);


-- ============================================
-- VERIFICATION: Test RLS is working
-- ============================================

-- After running, test with these queries in Supabase:
-- 
-- 1. Check RLS is enabled:
-- SELECT tablename, rowsecurity FROM pg_tables 
-- WHERE schemaname = 'public';
-- Expected: all tables show 'true' for rowsecurity
--
-- 2. Check policies exist:
-- SELECT tablename, policyname FROM pg_policies 
-- WHERE schemaname = 'public'
-- ORDER BY tablename;
-- Expected: multiple policies per table

-- ============================================
-- END OF SECTION 2 MIGRATION
-- ============================================
