'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Dispute {
  id: string;
  order_id: string;
  customer_email: string;
  reason: string;
  status: string;
  order_total: number;
  created_at: string;
  evidence_url?: string;
}

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1, 2, 3].map((i) => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-20 bg-gray-200 rounded" />
          <div className="h-4 w-36 bg-gray-200 rounded" />
          <div className="h-4 w-48 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

export default function DisputesPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Dispute | null>(null);
  const [resolution, setResolution] = useState<'refund' | 'partial_refund' | 'no_action'>('no_action');
  const [refundAmount, setRefundAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [resolving, setResolving] = useState(false);

  const load = () => {
    setLoading(true);
    api.get('/disputes')
      .then((res) => setDisputes(res.data.data as Dispute[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  const resolve = async () => {
    if (!selected) return;
    setResolving(true);
    try {
      await api.put(`/disputes/${selected.id}/resolve`, {
        resolution,
        refundAmount: refundAmount ? parseFloat(refundAmount) : undefined,
        adminNotes: notes,
      });
      setSelected(null);
      setResolution('no_action');
      setRefundAmount('');
      setNotes('');
      load();
    } catch (e) { console.error(e); }
    finally { setResolving(false); }
  };

  const openCount = disputes.filter((d) => d.status === 'open').length;

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Disputes</h1>
        <p className="text-gray-500 text-sm mt-0.5">
          {openCount > 0 ? (
            <span className="text-amber-600 font-medium">{openCount} open · </span>
          ) : null}
          {disputes.length - openCount} resolved
        </p>
      </div>

      {loading ? <TableSkeleton /> : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-100">
              <tr>
                {['Order', 'Customer', 'Reason', 'Amount', 'Status', 'Date', 'Actions'].map((h) => (
                  <th key={h} className="text-left px-5 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {disputes.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-center py-16">
                    <div className="text-gray-300 text-4xl mb-3">⚖️</div>
                    <p className="text-gray-400 text-sm">No disputes found</p>
                  </td>
                </tr>
              )}
              {disputes.map((d) => (
                <tr key={d.id} className="hover:bg-gray-50/50 transition-colors">
                  <td className="px-5 py-4 font-mono text-xs text-gray-500">{d.order_id.substring(0, 8)}…</td>
                  <td className="px-5 py-4 text-gray-700">{d.customer_email}</td>
                  <td className="px-5 py-4 max-w-xs">
                    <p className="truncate text-gray-600" title={d.reason}>{d.reason}</p>
                  </td>
                  <td className="px-5 py-4 font-semibold text-gray-800">ETB {Number(d.order_total).toFixed(2)}</td>
                  <td className="px-5 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${
                      d.status === 'open'
                        ? 'bg-amber-50 text-amber-700'
                        : 'bg-green-50 text-green-700'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${d.status === 'open' ? 'bg-amber-400' : 'bg-green-400'}`} />
                      {d.status.charAt(0).toUpperCase() + d.status.slice(1)}
                    </span>
                  </td>
                  <td className="px-5 py-4 text-gray-400 text-xs whitespace-nowrap">
                    {new Date(d.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-5 py-4">
                    {d.status === 'open' && (
                      <button
                        onClick={() => setSelected(d)}
                        className="text-xs bg-blue-500 hover:bg-blue-600 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                      >
                        Resolve
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Resolve Modal */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-md shadow-2xl">
            <div className="flex items-center gap-3 mb-5">
              <div className="w-10 h-10 bg-blue-50 rounded-xl flex items-center justify-center">
                <svg className="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3" />
                </svg>
              </div>
              <div>
                <h2 className="font-bold text-gray-900">Resolve Dispute</h2>
                <p className="text-gray-400 text-xs">Order {selected.order_id.substring(0, 8)}…</p>
              </div>
            </div>

            {/* Reason */}
            <div className="bg-gray-50 rounded-xl px-4 py-3 mb-4">
              <p className="text-xs text-gray-500 font-medium mb-1">Customer reason</p>
              <p className="text-sm text-gray-700">{selected.reason}</p>
            </div>

            {selected.evidence_url && (
              <a
                href={selected.evidence_url}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1.5 text-blue-500 text-sm hover:underline mb-4"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                </svg>
                View Evidence
              </a>
            )}

            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Resolution</label>
                <select
                  value={resolution}
                  onChange={(e) => setResolution(e.target.value as typeof resolution)}
                  className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                >
                  <option value="no_action">No Action</option>
                  <option value="partial_refund">Partial Refund</option>
                  <option value="refund">Full Refund</option>
                </select>
              </div>

              {(resolution === 'refund' || resolution === 'partial_refund') && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1.5">
                    Refund Amount (ETB)
                    <span className="text-gray-400 font-normal ml-1">— order total: ETB {Number(selected.order_total).toFixed(2)}</span>
                  </label>
                  <input
                    type="number"
                    value={refundAmount}
                    onChange={(e) => setRefundAmount(e.target.value)}
                    placeholder={`Max ETB ${Number(selected.order_total).toFixed(2)}`}
                    className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
                  />
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Admin Notes</label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Internal notes about this resolution..."
                  className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 resize-none"
                  rows={3}
                />
              </div>
            </div>

            <div className="flex gap-3 mt-5">
              <button
                onClick={() => { setSelected(null); setResolution('no_action'); setRefundAmount(''); setNotes(''); }}
                className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-medium hover:bg-gray-50 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={resolve}
                disabled={resolving}
                className="flex-1 bg-orange-500 hover:bg-orange-600 text-white rounded-xl py-2.5 text-sm font-medium disabled:opacity-50 transition-colors flex items-center justify-center gap-2"
              >
                {resolving ? (
                  <>
                    <svg className="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                    </svg>
                    Resolving…
                  </>
                ) : 'Confirm Resolution'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
