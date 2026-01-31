'use server';
import { createClient } from '@/lib/supabase-server';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { createApiKeySchema } from '@/lib/validators';

export async function generateApiKey(formData: FormData) {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) {
        return { error: 'Unauthorized' };
    }

    const name = formData.get('name') as string;
    const days = formData.get('expires_in_days');
    const expiresInDays = days ? parseInt(days as string) : undefined;

    // Validate input
    const validation = createApiKeySchema.safeParse({ name, expires_in_days: expiresInDays });
    if (!validation.success) {
        return { error: validation.error.issues[0].message };
    }

    // Call the database function
    const { data, error } = await supabase.rpc('generate_api_key', {
        p_user_id: user.id,
        p_key_name: name,
        p_expires_in_days: expiresInDays
    });

    if (error) {
        console.error('Error generating key:', error);
        return { error: error.message };
    }

    revalidatePath('/dashboard/api-keys');
    
    // Return the full key to show to the user (ONLY ONCE)
    return {
        success: true,
        key: data[0].full_key,
        prefix: data[0].key_prefix
    };
}

export async function revokeApiKey(keyId: string) {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) {
        return { error: 'Unauthorized' };
    }

    const { data, error } = await supabase.rpc('revoke_api_key', {
        p_user_id: user.id,
        p_key_id: keyId
    });

    if (error) {
        return { error: error.message };
    }

    revalidatePath('/dashboard/api-keys');
    return { success: true };
}

export async function updateLeadStatus(leadId: string, newStatus: string, currentVersion: number) {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) return { error: 'Unauthorized' };

    const { data, error } = await supabase.rpc('update_lead_status', {
        p_lead_id: leadId,
        p_user_id: user.id,
        p_new_status: newStatus,
        p_current_version: currentVersion
    });

    if (error) return { error: error.message };

    // If function returns success=false (e.g. version mismatch), handle it
    if (data && !data[0].success) {
        return { error: data[0].error_message };
    }

    revalidatePath('/dashboard');
    return { success: true };
}
