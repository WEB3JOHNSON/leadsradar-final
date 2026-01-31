export const RATE_LIMITS = {
    pitch_generation: {
        hourly: 3,
        daily: 10
    },
    webhook_ingestion: {
        hourly: 100,
        daily: 1000 // Soft limit
    }
};

export const AI_CONFIG = {
    provider: 'gemini',
    model: 'gemini-pro',
    max_tokens: 300,
    temperature: 0.7,
    timeout_ms: 10000
};

export const API_KEY_PREFIX = {
    LIVE: 'ldr_live_',
    TEST: 'ldr_test_'
};

export const LEAD_STATUSES = ['Found', 'Contacted', 'Negotiating', 'Won', 'Lost'] as const;

export const APP_CONFIG = {
    name: 'LeadsRadar',
    url: process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000',
    max_bio_length: 500,
    max_tweet_length: 500
};
