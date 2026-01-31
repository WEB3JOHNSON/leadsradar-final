'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase-server';
import { logger } from '@/lib/logger';

export async function login(formData: FormData) {
    const supabase = await createClient();
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;

    const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
    });

    if (error) {
        logger.error('Login failed', { email }, error);
        redirect(`/login?error=${encodeURIComponent(error.message)}`);
    }

    revalidatePath('/', 'layout');
    redirect('/dashboard');
}

export async function signup(formData: FormData) {
    const supabase = await createClient();
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;
    const full_name = formData.get('full_name') as string;

    const { error } = await supabase.auth.signUp({
        email,
        password,
        options: {
            data: { full_name },
            emailRedirectTo: `${process.env.NEXT_PUBLIC_APP_URL}/auth/callback`,
        },
    });

    if (error) {
        logger.error('Signup failed', { email }, error);
        redirect(`/signup?error=${encodeURIComponent(error.message)}`);
    }

    revalidatePath('/', 'layout');

    // If email confirmation is enabled, redirect to a verify page
    // For now, assume auto-confirm or redirect to dashboard if allowed
    redirect('/dashboard?message=Check email to continue sign in process');
}

export async function signOut() {
    const supabase = await createClient();
    await supabase.auth.signOut();
    revalidatePath('/', 'layout');
    redirect('/login');
}
