import { NextResponse } from 'next/server';
import { createServiceRoleClient } from '@/lib/supabase-server';
import { webhookPayloadSchema } from '@/lib/validators';
import { v4 as uuidv4 } from 'uuid';
import { logger } from '@/lib/logger';
import { z } from 'zod';

export async function POST(request: Request) {
    const requestId = uuidv4();
    const startTime = Date.now();
    const supabase = createServiceRoleClient();

    try {
        // 1. Get headers
        const apiKeyHeader = request.headers.get('x-api-key');
        const signature = request.headers.get('x-signature'); // Optional for now

        if (!apiKeyHeader) {
            return NextResponse.json({ error: 'Missing API Key' }, { status: 401 });
        }

        // 2. Extract prefix (first 16 chars)
        const prefix = apiKeyHeader.substring(0, 16);

        // 3. Verify API Key using RPC
        const { data: keyData, error: keyError } = await supabase.rpc('verify_api_key', {
            p_key_prefix: prefix,
            p_full_key: apiKeyHeader
        });

        if (keyError || !keyData || !keyData[0]?.is_valid) {
            logger.warn('Invalid API Key attempt', { requestId, prefix });
            return NextResponse.json({ error: 'Invalid API Key' }, { status: 401 });
        }

        const { user_id, key_id } = keyData[0];

        // 4. Rate Limit Check
        const { data: limitData, error: limitError } = await supabase.rpc('check_and_increment_rate_limit', {
            p_user_id: user_id,
            p_resource_type: 'webhook_ingestion'
        });

        if (limitError || !limitData || !limitData[0]?.allowed) {
            logger.warn('Rate limit exceeded', { requestId, user_id });
            return NextResponse.json({ error: 'Rate limit exceeded' }, { status: 429 });
        }

        // 5. Parse Body
        const body = await request.json();
        const validation = webhookPayloadSchema.safeParse(body);

        if (!validation.success) {
            // Log failed ingress attempt
            await supabase.from('webhook_events').insert({
                request_id: requestId,
                user_id,
                api_key_id: key_id,
                payload: body,
                error_message: 'Validation failed: ' + validation.error.message,
                processed: false
            });

            return NextResponse.json({ error: 'Invalid payload', details: validation.error.errors }, { status: 400 });
        }

        const payload = validation.data;

        // 6. Insert Lead (Upsert based on tweet_id + user_id)
        // First, insert raw webhook event
        const { data: eventData, error: eventError } = await supabase.from('webhook_events').insert({
            request_id: requestId,
            user_id,
            api_key_id: key_id,
            payload: body,
            processed: true // Optimistically mapped
        }).select().single();

        if (eventError) {
            throw new Error('Failed to log webhook event: ' + eventError.message);
        }

        // Then insert/upsert lead
        const { data: leadData, error: leadError } = await supabase.from('leads').upsert({
            user_id,
            tweet_id: payload.tweet_id,
            tweet_text: payload.tweet_text,
            tweet_author: payload.tweet_author,
            spam_score: payload.spam_score,
            estimated_value: payload.estimated_value,
            source: 'webhook',
            source_metadata: { webhook_event_id: eventData.id },
            status: 'Found' // Default status
        }, {
            onConflict: 'user_id,tweet_id',
            ignoreDuplicates: true // Or update? Let's ignore duplicates to preserve state
        }).select().single();

        if (leadError) {
            // Update webhook event with error
            await supabase.from('webhook_events').update({
                error_message: 'Lead insert failed: ' + leadError.message,
                processed: false
            }).eq('id', eventData.id);

            throw new Error('Failed to insert lead: ' + leadError.message);
        }

        // 7. Success
        const latency = Date.now() - startTime;
        logger.info('Webhook processed successfully', { requestId, user_id, lead_id: leadData?.id, latency });

        return NextResponse.json({
            success: true,
            lead_id: leadData?.id,
            request_id: requestId
        });

    } catch (error: any) {
        logger.error('Webhook processing error', { requestId }, error);

        return NextResponse.json({
            error: 'Internal Server Error',
            request_id: requestId
        }, { status: 500 });
    }
}
