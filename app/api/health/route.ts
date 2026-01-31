import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase-server';

export async function GET() {
    const supabase = await createClient();

    // Check database connection
    const { error } = await supabase.from('profiles').select('count').limit(1).single();

    if (error) {
        return NextResponse.json(
            { status: 'error', database: 'disconnected', error: error.message },
            { status: 503 }
        );
    }

    return NextResponse.json(
        { status: 'ok', database: 'connected', version: '1.0.0' },
        { status: 200 }
    );
}
