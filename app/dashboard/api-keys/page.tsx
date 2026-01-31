import { createClient } from '@/lib/supabase-server';
import ApiKeysClient from './client-page';

export default async function ApiKeysPage() {
    const supabase = await createClient();

    // Fetch keys (RLS will filter to own keys)
    const { data: keys } = await supabase
        .from('api_keys')
        .select('*')
        .order('created_at', { ascending: false });

    return (
        <div className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
            <div className="px-4 py-6 sm:px-0">
                <h1 className="text-2xl font-bold text-gray-900 mb-6">API Keys</h1>
                <ApiKeysClient initialKeys={keys || []} />
            </div>
        </div>
    );
}
