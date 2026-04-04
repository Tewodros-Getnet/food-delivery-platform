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

export default function DisputesPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Dispute | null>(null);
  const [resolution, setResolution] = useState<'refund' | 'partial_refund' | 'no_action'>('no_action');
  const [refundAmount, setRefundAmount] = useState('');
  const [notes, setNotes] = useState('');

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
    await api.put(`/disputes/${selected.id}/resolve`, {
      resolution,
      refundAmount: refundAmount ? parseFloat(refundAmount) : undefined,
      adminNotes: notes,
    });
    setSelected(null);
    load();
  };

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Disputes</h1>

      {loading ? <div className="text-center py-8">Loading...</div> : (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>{['Order', 'Customer', 'Reason', 'Amount', 'Status', 'Date', 'Actions'].map((h) => (
                <th key={h} className="text-left px-4 py-3 font-medium text-gray-600">{h}</th>
              ))}</tr>
            </thead>
            <tbody>
              {disputes.map((d) => (
                <tr key={d.id} className="border-b last:border-0 hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono text-xs">{d.order_id.substring(0, 8)}...</td>
                  <td className="px-4 py-3">{d.customer_email}</td>
                  <td className="px-4 py-3 max-w-xs truncate">{d.reason}</td>
                  <td className="px-4 py-3">ETB {Number(d.order_total).toFixed(2)}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                      d.status === 'open' ? 'bg-yellow-100 text-yellow-800' : 'bg-green-100 text-green-800'
                    }`}>{d.status}</span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">{new Date(d.created_at).toLocaleDateString()}</td>
                  <td className="px-4 py-3">
                    {d.status === 'open' && (
                      <button onClick={() => setSelected(d)}
                        className="text-xs bg-blue-500 text-white px-2 py-1 rounded hover:bg-blue-600">
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
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-6 w-full max-w-md shadow-xl">
            <h2 className="text-lg font-bold mb-4">Resolve Dispute</h2>
            <p className="text-sm text-gray-600 mb-4">{selected.reason}</p>
            {selected.evidence_url && (
              <a href={selected.evidence_url} target="_blank" rel="noreferrer"
                className="text-blue-500 text-sm underline block mb-4">View Evidence</a>
            )}
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-medium mb-1">Resolution</label>
                <select value={resolution} onChange={(e) => setResolution(e.target.value as typeof resolution)}
                  className="w-full border rounded-lg px-3 py-2 text-sm">
                  <option value="no_action">No Action</option>
                  <option value="partial_refund">Partial Refund</option>
                  <option value="refund">Full Refund</option>
                </select>
              </div>
              {(resolution === 'refund' || resolution === 'partial_refund') && (
                <div>
                  <label className="block text-sm font-medium mb-1">Refund Amount (ETB)</label>
                  <input type="number" value={refundAmount} onChange={(e) => setRefundAmount(e.target.value)}
                    className="w-full border rounded-lg px-3 py-2 text-sm" />
                </div>
              )}
              <div>
                <label className="block text-sm font-medium mb-1">Admin Notes</label>
                <textarea value={notes} onChange={(e) => setNotes(e.target.value)}
                  className="w-full border rounded-lg px-3 py-2 text-sm" rows={3} />
              </div>
            </div>
            <div className="flex gap-3 mt-4">
              <button onClick={() => setSelected(null)}
                className="flex-1 border rounded-lg py-2 text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={resolve}
                className="flex-1 bg-orange-500 text-white rounded-lg py-2 text-sm hover:bg-orange-600">
                Confirm Resolution
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
