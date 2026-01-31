'use client';

import { Lead } from '@/lib/types';
import LeadCard from '@/components/LeadCard';
import { Toaster } from 'sonner';

export default function LeadsDashboard({ leads }: { leads: Lead[] }) {
    if (leads.length === 0) {
        return (
            <div className="text-center py-12">
                <h3 className="mt-2 text-sm font-medium text-gray-900">No leads yet</h3>
                <p className="mt-1 text-sm text-gray-500">Waiting for webhooks to populate leads.</p>
            </div>
        );
    }

    // Group by status (Simple columnar view)
    const columns = ['Found', 'Contacted', 'Negotiating', 'Won', 'Lost'];

    return (
        <>
            <Toaster position="top-right" />
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4 overflow-x-auto min-h-[calc(100vh-200px)]">
                {columns.map(status => (
                    <div key={status} className="bg-gray-50 rounded-lg p-2 min-w-[250px]">
                        <h3 className="font-medium text-gray-700 mb-3 px-2 flex justify-between items-center">
                            {status}
                            <span className="bg-gray-200 text-gray-600 py-0.5 px-2 rounded-full text-xs">
                                {leads.filter(l => l.status === status).length}
                            </span>
                        </h3>
                        <div className="space-y-3">
                            {leads
                                .filter(l => l.status === status)
                                .map(lead => (
                                    <LeadCard key={lead.id} lead={lead} />
                                ))}
                        </div>
                    </div>
                ))}
            </div>
        </>
    );
}
