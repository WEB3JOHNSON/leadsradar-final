export type LeadStatus = 'Found' | 'Contacted' | 'Negotiating' | 'Won' | 'Lost';
export type ApiKeyStatus = 'active' | 'revoked' | 'expired';

export interface Profile {
    id: string;
    email: string;
    bio: string | null;
    created_at: string;
    updated_at: string;
    deleted_at: string | null;
}

export interface ApiKey {
    id: string;
    user_id: string;
    key_prefix: string;
    name: string;
    last_used_at: string | null;
    expires_at: string | null;
    created_at: string;
    revoked_at: string | null;
    status?: ApiKeyStatus; // Computed client-side or via query
}

export interface Lead {
    id: string;
    user_id: string;
    tweet_id: string;
    tweet_text: string;
    tweet_author: string;
    tweet_url?: string; // Computed
    status: LeadStatus;
    spam_score: number;
    estimated_value: number;
    contacted_at: string | null;
    won_at: string | null;
    lost_at: string | null;
    source: string;
    source_metadata: Record<string, any> | null;
    created_at: string;
    updated_at: string;
    updated_by: string | null;
    version: number;
    deleted_at: string | null;
}

export interface WebhookEvent {
    id: string;
    user_id: string | null;
    api_key_id: string | null;
    request_id: string;
    signature: string | null;
    signature_valid: boolean | null;
    payload: Record<string, any>;
    headers: Record<string, any> | null;
    ip_address: string | null;
    processed: boolean;
    processed_at: string | null;
    lead_id: string | null;
    error_message: string | null;
    error_stack: string | null;
    retry_count: number;
    received_at: string;
}

export interface ApiUsageLog {
    id: string;
    user_id: string;
    request_id: string;
    endpoint: string;
    method: string;
    status_code: number;
    model: string | null;
    prompt_tokens: number | null;
    completion_tokens: number | null;
    total_tokens: number | null;
    estimated_cost: number | null;
    success: boolean | null;
    error_type: string | null;
    latency_ms: number | null;
    created_at: string;
}

export interface RateLimitUsage {
    id: string;
    user_id: string;
    resource_type: 'pitch_generation' | 'webhook_ingestion';
    count_hourly: number;
    count_daily: number;
    last_reset_hour: string;
    last_reset_date: string;
    created_at: string;
    updated_at: string;
}
