'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface ConfigEntry {
  key: string;
  value: string;
  updated_at: string;
}

const CONFIG_META: Record<string, { label: string; description: string; unit: string; type: 'number' | 'text' }> = {
  delivery_base_fee: {
    label: 'Base Delivery Fee',
    description: 'Fixed fee charged on every order regardless of distance',
    unit: 'ETB',
    type: 'number',
  },
  delivery_rate_per_km: {
    label: 'Rate per Kilometre',
    description: 'Additional fee charged per km of delivery distance',
    unit: 'ETB/km',
    type: 'number',
  },
  rider_search_radius_km: {
    label: 'Rider Search Radius',
    description: 'Maximum distance to search for available riders',
    unit: 'km',
    type: 'number',
  },
  rider_timeout_seconds: {
    label: 'Rider Response Timeout',
    description: 'Seconds a rider has to accept a delivery request before moving to the next',
    unit: 'seconds',
    type: 'number',
  },
  dispatch_max_duration_minutes: {
    label: 'Max Dispatch Duration',
    description: 'Maximum minutes to search for a rider before cancelling the order',
    unit: 'minutes',
    type: 'number',
  },
  order_acceptance_timeout_seconds: {
    label: 'Order Acceptance Timeout',
    description: 'Seconds a restaurant has to accept or reject an order',
    unit: 'seconds',
    type: 'number',
  },
};

export default function ConfigPage() {
  const [config, setConfig] = useState<ConfigEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  const load = () => {
    setLoading(true);
    api.get('/admin/config')
      .then((res) => setConfig(res.data.data as ConfigEntry[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  const startEdit = (key: string, currentValue: string) => {
    setEditing((prev) => ({ ...prev, [key]: currentValue }));
  };

  const cancelEdit = (key: string) => {
    setEditing((prev) => { const n = { ...prev }; delete n[key]; return n; });
  };

  const save = async (key: string) => {
    const value = editing[key];
    if (value === undefined) return;
    setSaving(key);
    try {
      await api.put(`/admin/config/${key}`, { value });
      setSaved(key);
      setTimeout(() => setSaved(null), 2000);
      cancelEdit(key);
      load();
    } catch (e) {
      console.error(e);
    } finally {
      setSaving(null);
    }
  };

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Platform Configuration</h1>
        <p className="text-gray-500 text-sm mt-0.5">Adjust platform-wide settings. Changes take effect immediately.</p>
      </div>

      <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 flex items-start gap-3">
        <svg className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <p className="text-sm text-amber-800">
          Changes to fees and timeouts affect all active orders and new orders immediately. Review carefully before saving.
        </p>
      </div>

      {loading ? (
        <div className="space-y-3 animate-pulse">
          {[1, 2, 3, 4, 5].map((i) => <div key={i} className="h-24 bg-gray-200 rounded-2xl" />)}
        </div>
      ) : (
        <div className="space-y-3">
          {config.map((entry) => {
            const meta = CONFIG_META[entry.key];
            const isEditing = entry.key in editing;
            const isSaving = saving === entry.key;
            const isSaved = saved === entry.key;

            return (
              <div key={entry.key} className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-semibold text-gray-900 text-sm">
                        {meta?.label ?? entry.key.replaceAll('_', ' ')}
                      </h3>
                      <span className="text-xs text-gray-400 font-mono bg-gray-50 px-2 py-0.5 rounded">
                        {entry.key}
                      </span>
                    </div>
                    {meta?.description && (
                      <p className="text-xs text-gray-500 mb-3">{meta.description}</p>
                    )}

                    {isEditing ? (
                      <div className="flex items-center gap-2">
                        <div className="relative">
                          <input
                            type={meta?.type ?? 'text'}
                            value={editing[entry.key]}
                            onChange={(e) => setEditing((prev) => ({ ...prev, [entry.key]: e.target.value }))}
                            className="border border-orange-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 w-36"
                            autoFocus
                          />
                          {meta?.unit && (
                            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-gray-400">
                              {meta.unit}
                            </span>
                          )}
                        </div>
                        <button
                          onClick={() => save(entry.key)}
                          disabled={isSaving}
                          className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
                        >
                          {isSaving ? 'Saving…' : 'Save'}
                        </button>
                        <button
                          onClick={() => cancelEdit(entry.key)}
                          className="border border-gray-200 px-4 py-2 rounded-lg text-sm hover:bg-gray-50 transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    ) : (
                      <div className="flex items-center gap-3">
                        <span className="text-2xl font-bold text-gray-900">{entry.value}</span>
                        {meta?.unit && <span className="text-sm text-gray-500">{meta.unit}</span>}
                        {isSaved && (
                          <span className="text-xs text-green-600 font-medium flex items-center gap-1">
                            <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
                              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                            </svg>
                            Saved
                          </span>
                        )}
                      </div>
                    )}
                  </div>

                  {!isEditing && (
                    <button
                      onClick={() => startEdit(entry.key, entry.value)}
                      className="flex items-center gap-1.5 text-xs text-gray-500 hover:text-gray-800 border border-gray-200 px-3 py-1.5 rounded-lg hover:bg-gray-50 transition-colors shrink-0"
                    >
                      <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                      Edit
                    </button>
                  )}
                </div>

                <p className="text-xs text-gray-400 mt-3">
                  Last updated: {new Date(entry.updated_at).toLocaleString()}
                </p>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
