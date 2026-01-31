import { z } from 'zod';
import { LEAD_STATUSES } from './constants';

export const generatePitchSchema = z.object({
    tweet_text: z.string().min(1).max(500),
    tweet_author: z.string().optional(),
    tone: z.enum(['professional', 'casual', 'friendly']).default('professional')
});

export const webhookPayloadSchema = z.object({
    tweet_id: z.string().regex(/^[0-9]+$/, "Tweet ID must be numeric").min(1).max(30),
    tweet_text: z.string().min(1).max(500),
    tweet_author: z.string().regex(/^[a-zA-Z0-9_]{1,15}$/, "Invalid Twitter username"),
    spam_score: z.number().min(0).max(100).optional().default(0),
    estimated_value: z.number().min(0).max(1000000).optional().default(0)
});

export const updateLeadSchema = z.object({
    status: z.enum(LEAD_STATUSES).optional(),
    estimated_value: z.number().min(0).max(1000000).optional(),
    spam_score: z.number().min(0).max(100).optional()
});

export const createApiKeySchema = z.object({
    name: z.string().min(1).max(50),
    expires_in_days: z.number().int().positive().optional()
});

export const updateProfileSchema = z.object({
    bio: z.string().max(500).optional()
});
