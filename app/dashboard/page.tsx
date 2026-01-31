import { createClient } from '@/lib/supabase-server';
import { signOut } from '@/app/auth/actions';
import { redirect } from 'next/navigation';
import Link from 'next/link';
import LeadsDashboard from './leads-view';

export default async function DashboardPage() {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
        redirect('/login');
    }

    // Fetch leads
    const { data: leads } = await supabase
        .from('leads')
        .select('*')
        .order('created_at', { ascending: false });

    // Mock leads if empty (for demo purposes if requested, but better to keep clean)
    // We'll just pass the real data.

    return (
        <div className="min-h-screen bg-gray-100">
            <nav className="bg-white shadow-sm sticky top-0 z-10">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div className="flex justify-between h-16">
                        <div className="flex items-center space-x-8">
                            <span className="text-xl font-bold text-gray-800">LeadsRadar</span>
                            <div className="hidden md:flex space-x-4">
                                <Link href="/dashboard" className="text-gray-900 border-b-2 border-indigo-500 px-1 pt-1 text-sm font-medium">
                                    Leads
                                </Link>
                                <Link href="/dashboard/api-keys" className="text-gray-500 hover:text-gray-900 px-1 pt-1 text-sm font-medium">
                                    API Keys
                                </Link>
                            </div>
                        </div>
                        <div className="flex items-center">
                            <span className="text-sm text-gray-500 mr-4 hidden sm:block">{user.email}</span>
                            <form action={signOut}>
                                <button
                                    type="submit"
                                    className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-gray-600 hover:bg-gray-700 focus:outline-none"
                                >
                                    Sign Out
                                </button>
                            </form>
                        </div>
                    </div>
                </div>
            </nav>

            <main className="max-w-[1600px] mx-auto py-6 sm:px-6 lg:px-8">
                <div className="px-4 sm:px-0">
                    <LeadsDashboard leads={leads || []} />
                </div>
            </main>
        </div>
    );
}
