'use client';

import { useState } from 'react';
import { Lead } from '@/lib/types';
import { generateLeadPitch } from '@/app/dashboard/pitch-actions';
import { updateLeadStatus } from '@/app/dashboard/actions';
import { Loader2, Copy, Check, Sparkles, ExternalLink } from 'lucide-react';
import { toast } from 'sonner';

export default function LeadCard({ lead }: { lead: Lead }) {
    const [isGenerating, setIsGenerating] = useState(false);
    const [pitch, setPitch] = useState<string | null>(null);
    const [copied, setCopied] = useState(false);

    async function handleGenerate() {
        setIsGenerating(true);
        try {
            const result = await generateLeadPitch(lead.id, 'professional');
            if (result.success && result.pitch) {
                setPitch(result.pitch);
                toast.success('Pitch generated!');
            } else {
                toast.error(result.error || 'Failed to generate');
            }
        } catch (e) {
            toast.error('Something went wrong');
        } finally {
            setIsGenerating(false);
        }
    }

    async function handleStatusChange(newStatus: string) {
        const result = await updateLeadStatus(lead.id, newStatus, lead.version);
        if (result.success) {
            toast.success(`Moved to ${newStatus}`);
        } else {
            toast.error(result.error || 'Failed to update status');
        }
    }

    const copyToClipboard = () => {
        if (pitch) {
            navigator.clipboard.writeText(pitch);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
            toast.success('Copied to clipboard');
        }
    };

    return (
        <div className="bg-white p-4 rounded-lg shadow border border-gray-200 space-y-3">
            {/* Header */}
            <div className="flex justify-between items-start">
                <div className="flex items-center space-x-2">
                    <span className="font-bold text-gray-900">@{lead.tweet_author}</span>
                    <a
                        href={`https://twitter.com/${lead.tweet_author}/status/${lead.tweet_id}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-gray-400 hover:text-blue-500"
                    >
                        <ExternalLink size={14} />
                    </a>
                </div>
                <span className={`text-xs px-2 py-1 rounded-full font-medium
          ${lead.status === 'Won' ? 'bg-green-100 text-green-800' :
                        lead.status === 'Lost' ? 'bg-red-100 text-red-800' :
                            'bg-blue-100 text-blue-800'}`}>
                    {lead.status}
                </span>
            </div>

            {/* Tweet Content */}
            <p className="text-sm text-gray-600 line-clamp-3">
                {lead.tweet_text}
            </p>

            {/* Stats/Meta */}
            <div className="flex space-x-4 text-xs text-gray-400">
                <span>Detected: {new Date(lead.created_at).toLocaleDateString()}</span>
                {lead.estimated_value > 0 && (
                    <span className="text-green-600 font-medium">${lead.estimated_value} est.</span>
                )}
            </div>

            {/* Pitch Section */}
            {pitch ? (
                <div className="bg-gray-50 p-3 rounded-md text-sm border border-gray-200 mt-2">
                    <p className="text-gray-800 whitespace-pre-wrap">{pitch}</p>
                    <div className="mt-2 flex justify-end space-x-2">
                        <button
                            onClick={() => setPitch(null)}
                            className="text-xs text-gray-500 hover:text-gray-700"
                        >
                            Discard
                        </button>
                        <button
                            onClick={copyToClipboard}
                            className="flex items-center text-xs text-blue-600 font-medium hover:text-blue-700"
                        >
                            {copied ? <Check size={14} className="mr-1" /> : <Copy size={14} className="mr-1" />}
                            {copied ? 'Copied' : 'Copy Pitch'}
                        </button>
                    </div>
                </div>
            ) : (
                <button
                    onClick={handleGenerate}
                    disabled={isGenerating}
                    className="w-full flex items-center justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none disabled:opacity-50"
                >
                    {isGenerating ? (
                        <Loader2 className="animate-spin h-4 w-4 mr-2" />
                    ) : (
                        <Sparkles className="h-4 w-4 mr-2" />
                    )}
                    Generate Pitch
                </button>
            )}

            {/* Actions */}
            <div className="pt-2 border-t border-gray-100 flex justify-between">
                <select
                    value={lead.status}
                    onChange={(e) => handleStatusChange(e.target.value)}
                    className="text-xs border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                >
                    <option value="Found">Found</option>
                    <option value="Contacted">Contacted</option>
                    <option value="Negotiating">Negotiating</option>
                    <option value="Won">Won</option>
                    <option value="Lost">Lost</option>
                </select>
            </div>
        </div>
    );
}
