'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Order {
  id: string;
  status: string;
  total: number;
  payment_status: string | null;
  cancellation_reason: string | null;
  cancelled_by: 'customer' | 'restaurant' | 'admin' | null;
  created_at: string;
  customer_email: string;
  customer_name: string | null;
  restaurant_name: string;
  rider_name: string | null;
  rider_email: string | null;
}

const STATUS_COLORS: Record<string, string> = {
  pending_payment: 'bg-gray-100 text-gray-700',
  confirmed: 'bg-blue-100 text-blue-700',
  ready_for_pickup: 'bg-yellow-100 text-yellow-700',
  rider_assigned: 'bg-purple-100 text-purple-700',
  picked_up: 'bg-teal-100 text-teal-700',
  delivered: 'bg-green-100 text-green-700',
  cancelled: 'bg-red-100 text-red-700',
  payment_failed: 'bg-red-100 text-red-700',
};

const STUCK_STATUSES = ['confirmed', 'ready_for_pickup', 'rider_assigned', 'picked_up'];

const CANCELLED_BY_COLORS: Record<string, string> = {
  customer: 'bg-blue-100 text-blue-700',
  restaurant: 'bg-orange-100 text-orange-700',
  admin: 'bg-red-100 text-red-700',
};

export default function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');
  const [cancelTarget, setCancelTarget] = useState<Order | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const load = (status?: string) => {
    setLoading(true);
    api.get('/admin/orders', { params: status ? { status } : {} })
      .then((res) => setOrders(res.data.data as Order[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  const forceCancel = async () => {
    if (!cancelTarget) return;
    setActionLoading(cancelTarget.id);
    try {
      await api.put(`/admin/orders/${cancelTarget.id}/cancel`, { reason: cancelReason || 'Cancelled by admin' });
      setCancelTarget(null);
      setCancelReason('');
      load(filter || undefined);
    } catch (e) { console.error(e); }
    finally { setActionLoading(null); }
  };

  const reassignRider = async (orderId: string) => {
    setActionLoading(orderId);
    try {
      await api.put(`/admin/orders/${orderId}/reassign-rider`);
      load(filter || undefined);
    } catch (e) { console.error(e); }
    finally { setActionLoading(null); }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Orders</h1>
        <select
          value={filter}
          onChange={(e) => { setFilter(e.target.value); load(e.target.value || undefined); }}
          className="border rounded-lg px-3 py-2 text-sm"
        >
          <option value="">All Statuses</option>
          {['pending_payment', 'confirmed', 'ready_for_pickup', 'rider_assigned', 'picked_up', 'delivered', 'cancelled', 'payment_failed'].map((s) => (
            <option key={s} value={s}>{s.replaceAll('_', ' ')}</option>
          ))}
        </select>
      </div>

      {loading ? (
        <div className="text-center py-8">Loading...</div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>
                {['Order', 'Customer', 'Restaurant', 'Rider', 'Total', 'Status', 'Cancelled By', 'Date', 'Actions'].map((h) => (
                  <th key={h} className="text-left px-4 py-3 font-medium text-gray-600">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {orders.length === 0 && (
                <tr><td colSpan={9} className="text-center py-8 text-gray-400">No orders found</td></tr>
              )}
              {orders.map((o) => (
                <tr key={o.id} className="border-b last:border-0 hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono text-xs">{o.id.substring(0, 8)}...</td>
                  <td className="px-4 py-3">
                    <div>{o.customer_name || '—'}</div>
                    <div className="text-gray-400 text-xs">{o.customer_email}</div>
                  </td>
                  <td className="px-4 py-3">{o.restaurant_name}</td>
                  <td className="px-4 py-3">
                    {o.rider_name ? (
                      <div>
                        <div>{o.rider_name}</div>
                        <div className="text-gray-400 text-xs">{o.rider_email}</div>
                      </div>
                    ) : <span className="text-gray-400">—</span>}
                  </td>
                  <td className="px-4 py-3 font-medium">ETB {Number(o.total).toFixed(2)}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${STATUS_COLORS[o.status] ?? 'bg-gray-100 text-gray-700'}`}>
                      {o.status.replaceAll('_', ' ')}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {o.status === 'cancelled' && o.cancelled_by ? (
                      <div>
                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${CANCELLED_BY_COLORS[o.cancelled_by]}`}>
                          {o.cancelled_by}
                        </span>
                        {o.cancellation_reason && (
                          <div className="text-gray-400 text-xs mt-1">{o.cancellation_reason}</div>
                        )}
                      </div>
                    ) : <span className="text-gray-400">—</span>}
                  </td>
                  <td className="px-4 py-3 text-gray-500 text-xs">
                    {new Date(o.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex gap-2">
                      {STUCK_STATUSES.includes(o.status) && (
                        <>
                          <button
                            onClick={() => setCancelTarget(o)}
                            disabled={actionLoading === o.id}
                            className="text-xs bg-red-500 text-white px-2 py-1 rounded hover:bg-red-600 disabled:opacity-50"
                          >
                            Cancel
                          </button>
                          {['ready_for_pickup', 'rider_assigned'].includes(o.status) && (
                            <button
                              onClick={() => reassignRider(o.id)}
                              disabled={actionLoading === o.id}
                              className="text-xs bg-orange-500 text-white px-2 py-1 rounded hover:bg-orange-600 disabled:opacity-50"
                            >
                              {actionLoading === o.id ? '...' : 'Reassign'}
                            </button>
                          )}
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Force Cancel Modal */}
      {cancelTarget && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-6 w-full max-w-md shadow-xl">
            <h2 className="text-lg font-bold mb-2">Force Cancel Order</h2>
            <p className="text-sm text-gray-600 mb-4">
              Cancel order <span className="font-mono font-bold">{cancelTarget.id.substring(0, 8)}...</span> for {cancelTarget.customer_name || cancelTarget.customer_email}?
              A refund will be initiated automatically.
            </p>
            <div className="mb-4">
              <label className="block text-sm font-medium mb-1">Reason (optional)</label>
              <input
                type="text"
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                placeholder="e.g. Restaurant closed, payment issue..."
                className="w-full border rounded-lg px-3 py-2 text-sm"
              />
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => { setCancelTarget(null); setCancelReason(''); }}
                className="flex-1 border rounded-lg py-2 text-sm hover:bg-gray-50"
              >
                Back
              </button>
              <button
                onClick={forceCancel}
                disabled={actionLoading === cancelTarget.id}
                className="flex-1 bg-red-500 text-white rounded-lg py-2 text-sm hover:bg-red-600 disabled:opacity-50"
              >
                {actionLoading === cancelTarget.id ? 'Cancelling...' : 'Confirm Cancel'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
