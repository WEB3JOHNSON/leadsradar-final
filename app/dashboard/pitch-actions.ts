'use server';

import { createClient } from '@/lib/supabase-server';
import { generatePitch } from '@/lib/ai-service';
import { logger } from '@/lib/logger';
import { GeneratePitchParams } from '@/lib/ai-service';

export async function generateLeadPitch(leadId: string, tone: GeneratePitchParams['tone'] = 'professional') {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
        return { error: 'Unauthorized' };
    }

    // 1. Check Rate Limit
    const { data: limitData, error: limitError } = await supabase.rpc('check_and_increment_rate_limit', {
        p_user_id: user.id,
        p_resource_type: 'pitch_generation'
    });

    if (limitError || !limitData || !limitData[0]?.allowed) {
        return { error: 'Daily pitch generation limit reached. Please upgrade to continue.' };
    }

    // 2. Fetch Lead Context (and User Bio)
    const { data: lead, error: leadError } = await supabase
        .from('leads')
        .select('tweet_text, tweet_author')
        .eq('id', leadId)
        .single();

    if (leadError || !lead) {
        return { error: 'Lead not found' };
    }

    const { data: profile } = await supabase
        .from('profiles')
        .select('bio')
        .eq('id', user.id)
        .single();

    // 3. Generate Pitch
    try {
        const pitch = await generatePitch({
            tweetText: lead.tweet_text,
            userBio: profile?.bio || undefined,
            leadName: lead.tweet_author, // Or extract name if available
            tone
        });

        // 4. Log API Usage (Cost Tracking)
        // Note: Gemini Free tier -> cost 0, but we log tokens if possible. 
        // For now we estimate or just log success.
        await supabase.rpc('log_api_request', {
            p_user_id: user.id,
            p_request_id: crypto.randomUUID(),
            p_endpoint: 'ai/generate_pitch',
            p_method: 'ACTION',
            p_status_code: 200,
            p_model: 'gemini-pro',
            p_success: true
        });

        return { success: true, pitch, remaining: limitData[0].remaining_daily };

    } catch (error: any) {
        logger.error('Pitch generation failed', { leadId }, error);
        return { error: 'Failed to generate pitch. Please try again.' };
    }
}
