-- ============================================
-- LeadsRadar Atomic Functions - Section 3
-- Run this in Supabase SQL Editor
-- ============================================

-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================
-- 1. CHECK AND INCREMENT RATE LIMIT
-- Atomically checks and updates rate limits
-- ============================================

CREATE OR REPLACE FUNCTION check_and_increment_rate_limit(
    p_user_id UUID,
    p_resource_type TEXT DEFAULT 'pitch_generation'
)
RETURNS TABLE (
    allowed BOOLEAN,
    remaining_hourly INT,
    remaining_daily INT,
    reset_hour_at TIMESTAMPTZ,
    reset_day_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_hourly_limit INT := 3;  -- Max per hour
    v_daily_limit INT := 10;  -- Max per day
    v_current_hour TIMESTAMPTZ := date_trunc('hour', NOW());
    v_current_date DATE := CURRENT_DATE;
    v_record rate_limit_usage%ROWTYPE;
BEGIN
    -- Try to get existing record with NOWAIT lock (prevents DoS via lock queuing)
    BEGIN
        SELECT * INTO v_record
        FROM rate_limit_usage
        WHERE user_id = p_user_id AND resource_type = p_resource_type
        FOR UPDATE NOWAIT;
    EXCEPTION
        WHEN lock_not_available THEN
            -- Lock is held by another transaction, return rate limited
            RETURN QUERY SELECT 
                FALSE,
                0,
                0,
                v_current_hour + INTERVAL '1 hour',
                (v_current_date + 1)::TIMESTAMPTZ;
            RETURN;
    END;

    -- If no record exists, create one
    IF v_record IS NULL THEN
        INSERT INTO rate_limit_usage (user_id, resource_type, count_hourly, count_daily)
        VALUES (p_user_id, p_resource_type, 0, 0)
        RETURNING * INTO v_record;
    END IF;

    -- Reset hourly counter if hour has changed
    IF v_record.last_reset_hour < v_current_hour THEN
        v_record.count_hourly := 0;
        v_record.last_reset_hour := v_current_hour;
    END IF;

    -- Reset daily counter if date has changed
    IF v_record.last_reset_date < v_current_date THEN
        v_record.count_daily := 0;
        v_record.last_reset_date := v_current_date;
    END IF;

    -- Check if over limit
    IF v_record.count_hourly >= v_hourly_limit OR v_record.count_daily >= v_daily_limit THEN
        -- Update the record (to persist reset timestamps)
        UPDATE rate_limit_usage
        SET count_hourly = v_record.count_hourly,
            count_daily = v_record.count_daily,
            last_reset_hour = v_record.last_reset_hour,
            last_reset_date = v_record.last_reset_date
        WHERE id = v_record.id;

        RETURN QUERY SELECT 
            FALSE,
            GREATEST(0, v_hourly_limit - v_record.count_hourly),
            GREATEST(0, v_daily_limit - v_record.count_daily),
            v_current_hour + INTERVAL '1 hour',
            (v_current_date + 1)::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- Increment counters
    UPDATE rate_limit_usage
    SET count_hourly = v_record.count_hourly + 1,
        count_daily = v_record.count_daily + 1,
        last_reset_hour = v_record.last_reset_hour,
        last_reset_date = v_record.last_reset_date
    WHERE id = v_record.id;

    -- Return success with remaining counts
    RETURN QUERY SELECT 
        TRUE,
        v_hourly_limit - v_record.count_hourly - 1,
        v_daily_limit - v_record.count_daily - 1,
        v_current_hour + INTERVAL '1 hour',
        (v_current_date + 1)::TIMESTAMPTZ;
END;
$$;

COMMENT ON FUNCTION check_and_increment_rate_limit IS 
'Atomically checks rate limit and increments if allowed. Uses NOWAIT to prevent DoS.';


-- ============================================
-- 2. GENERATE API KEY
-- Creates new API key with secure hashing
-- ============================================

CREATE OR REPLACE FUNCTION generate_api_key(
    p_user_id UUID,
    p_key_name TEXT,
    p_expires_in_days INT DEFAULT NULL
)
RETURNS TABLE (
    key_id UUID,
    full_key TEXT,
    key_prefix TEXT,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_full_key TEXT;
    v_prefix TEXT;
    v_hash TEXT;
    v_key_id UUID;
    v_expires TIMESTAMPTZ;
BEGIN
    -- Generate random key: ldr_live_ + 48 random chars
    v_full_key := 'ldr_live_' || encode(gen_random_bytes(36), 'base64');
    v_full_key := replace(replace(v_full_key, '+', 'x'), '/', 'y'); -- URL safe
    
    -- Extract prefix (first 16 chars for display)
    v_prefix := substring(v_full_key from 1 for 16);
    
    -- Hash the full key
    v_hash := crypt(v_full_key, gen_salt('bf', 10));
    
    -- Calculate expiration
    IF p_expires_in_days IS NOT NULL THEN
        v_expires := NOW() + (p_expires_in_days || ' days')::INTERVAL;
    ELSE
        v_expires := NULL;
    END IF;
    
    -- Insert the key
    INSERT INTO api_keys (user_id, key_prefix, key_hash, name, expires_at)
    VALUES (p_user_id, v_prefix, v_hash, p_key_name, v_expires)
    RETURNING id INTO v_key_id;
    
    -- Return the full key (only time it's ever returned!)
    RETURN QUERY SELECT v_key_id, v_full_key, v_prefix, v_expires;
END;
$$;

COMMENT ON FUNCTION generate_api_key IS 
'Generates a new API key. The full_key is only returned ONCE - user must save it!';


-- ============================================
-- 3. VERIFY API KEY
-- Validates API key and updates last_used_at
-- ============================================

CREATE OR REPLACE FUNCTION verify_api_key(
    p_key_prefix TEXT,
    p_full_key TEXT
)
RETURNS TABLE (
    is_valid BOOLEAN,
    user_id UUID,
    key_id UUID,
    key_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record api_keys%ROWTYPE;
BEGIN
    -- Find key by prefix
    SELECT * INTO v_record
    FROM api_keys
    WHERE key_prefix = p_key_prefix
      AND revoked_at IS NULL;
    
    -- Key not found
    IF v_record IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT;
        RETURN;
    END IF;
    
    -- Check if expired
    IF v_record.expires_at IS NOT NULL AND v_record.expires_at < NOW() THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT;
        RETURN;
    END IF;
    
    -- Verify hash
    IF v_record.key_hash != crypt(p_full_key, v_record.key_hash) THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT;
        RETURN;
    END IF;
    
    -- Update last_used_at
    UPDATE api_keys SET last_used_at = NOW() WHERE id = v_record.id;
    
    -- Return success
    RETURN QUERY SELECT TRUE, v_record.user_id, v_record.id, v_record.name;
END;
$$;

COMMENT ON FUNCTION verify_api_key IS 
'Verifies an API key by prefix and full key. Updates last_used_at on success.';


-- ============================================
-- 4. REVOKE API KEY
-- Safely revokes an API key
-- ============================================

CREATE OR REPLACE FUNCTION revoke_api_key(
    p_user_id UUID,
    p_key_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_updated INT;
BEGIN
    UPDATE api_keys
    SET revoked_at = NOW()
    WHERE id = p_key_id
      AND user_id = p_user_id
      AND revoked_at IS NULL;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    
    RETURN v_updated > 0;
END;
$$;

COMMENT ON FUNCTION revoke_api_key IS 
'Revokes an API key. Only works if key belongs to user and is not already revoked.';


-- ============================================
-- 5. SOFT DELETE LEAD
-- Soft deletes a lead with audit trail
-- ============================================

CREATE OR REPLACE FUNCTION soft_delete_lead(
    p_lead_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_updated INT;
BEGIN
    UPDATE leads
    SET deleted_at = NOW(),
        updated_by = p_user_id
    WHERE id = p_lead_id
      AND user_id = p_user_id
      AND deleted_at IS NULL;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    
    RETURN v_updated > 0;
END;
$$;

COMMENT ON FUNCTION soft_delete_lead IS 
'Soft deletes a lead. Sets deleted_at and updated_by for audit trail.';


-- ============================================
-- 6. UPDATE LEAD STATUS
-- Updates status with optimistic locking
-- ============================================

CREATE OR REPLACE FUNCTION update_lead_status(
    p_lead_id UUID,
    p_user_id UUID,
    p_new_status lead_status,
    p_current_version INT
)
RETURNS TABLE (
    success BOOLEAN,
    new_version INT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record leads%ROWTYPE;
BEGIN
    -- Lock the lead for update
    SELECT * INTO v_record
    FROM leads
    WHERE id = p_lead_id
      AND user_id = p_user_id
      AND deleted_at IS NULL
    FOR UPDATE;
    
    -- Lead not found
    IF v_record IS NULL THEN
        RETURN QUERY SELECT FALSE, 0, 'Lead not found or deleted'::TEXT;
        RETURN;
    END IF;
    
    -- Version mismatch (concurrent update detected)
    IF v_record.version != p_current_version THEN
        RETURN QUERY SELECT FALSE, v_record.version, 'Concurrent update detected. Please refresh.'::TEXT;
        RETURN;
    END IF;
    
    -- Update the lead
    UPDATE leads
    SET status = p_new_status,
        contacted_at = CASE WHEN p_new_status = 'Contacted' AND contacted_at IS NULL THEN NOW() ELSE contacted_at END,
        won_at = CASE WHEN p_new_status = 'Won' AND won_at IS NULL THEN NOW() ELSE won_at END,
        lost_at = CASE WHEN p_new_status = 'Lost' AND lost_at IS NULL THEN NOW() ELSE lost_at END,
        updated_by = p_user_id
    WHERE id = p_lead_id;
    
    -- Return success (version is auto-incremented by trigger)
    RETURN QUERY SELECT TRUE, v_record.version + 1, NULL::TEXT;
END;
$$;

COMMENT ON FUNCTION update_lead_status IS 
'Updates lead status with optimistic locking. Sets timestamp based on new status.';


-- ============================================
-- 7. LOG API REQUEST
-- Records API usage for cost tracking
-- ============================================

CREATE OR REPLACE FUNCTION log_api_request(
    p_user_id UUID,
    p_request_id UUID,
    p_endpoint TEXT,
    p_method TEXT,
    p_status_code INT,
    p_model TEXT DEFAULT NULL,
    p_prompt_tokens INT DEFAULT NULL,
    p_completion_tokens INT DEFAULT NULL,
    p_success BOOLEAN DEFAULT TRUE,
    p_latency_ms INT DEFAULT NULL,
    p_error_type TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_tokens INT;
    v_estimated_cost DECIMAL(10, 6);
BEGIN
    -- Calculate totals
    v_total_tokens := COALESCE(p_prompt_tokens, 0) + COALESCE(p_completion_tokens, 0);
    
    -- Calculate cost based on model
    IF p_model = 'gpt-4o-mini' THEN
        v_estimated_cost := (COALESCE(p_prompt_tokens, 0) * 0.00000015) + 
                           (COALESCE(p_completion_tokens, 0) * 0.0000006);
    ELSIF p_model = 'gpt-4o' THEN
        v_estimated_cost := (COALESCE(p_prompt_tokens, 0) * 0.000005) + 
                           (COALESCE(p_completion_tokens, 0) * 0.000015);
    ELSE
        v_estimated_cost := 0;
    END IF;
    
    -- Insert log entry
    INSERT INTO api_usage_logs (
        user_id, request_id, endpoint, method, status_code,
        model, prompt_tokens, completion_tokens, total_tokens,
        estimated_cost, success, error_type, latency_ms
    ) VALUES (
        p_user_id, p_request_id, p_endpoint, p_method, p_status_code,
        p_model, p_prompt_tokens, p_completion_tokens, v_total_tokens,
        v_estimated_cost, p_success, p_error_type, p_latency_ms
    );
END;
$$;

COMMENT ON FUNCTION log_api_request IS 
'Logs API usage with automatic cost calculation based on model pricing.';


-- ============================================
-- 8. HANDLE NEW USER (Trigger function)
-- Creates profile when auth user signs up
-- ============================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Create profile for new user
    INSERT INTO profiles (id, email)
    VALUES (NEW.id, NEW.email);
    
    -- Create initial rate limit entries
    INSERT INTO rate_limit_usage (user_id, resource_type)
    VALUES 
        (NEW.id, 'pitch_generation'),
        (NEW.id, 'webhook_ingestion');
    
    RETURN NEW;
END;
$$;

-- Create trigger on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

COMMENT ON FUNCTION handle_new_user IS 
'Trigger function: Creates profile and rate limit entries when user signs up.';


-- ============================================
-- VERIFICATION
-- ============================================

-- Test functions exist:
-- SELECT routine_name FROM information_schema.routines 
-- WHERE routine_schema = 'public' AND routine_type = 'FUNCTION';

-- Expected: check_and_increment_rate_limit, generate_api_key, verify_api_key,
--           revoke_api_key, soft_delete_lead, update_lead_status, 
--           log_api_request, handle_new_user, update_updated_at, increment_version

-- ============================================
-- END OF SECTION 3 MIGRATION
-- ============================================
