'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Order {
  id: string;
  status: string;
  total: number;
  payment_status: string | null;
  cancellation_reason: string | null;
  cancelled_by: 'customer' | 'restaurant' | 'admin' | 'system' | null;
  created_at: string;
  customer_email: string;
  customer_name: string | null;
  restaurant_name: string;
  rider_name: string | null;
  rider_email: string | null;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

const STATUS_STYLES: Record<string, string> = {
  pending_payment: 'bg-gray-100 text-gray-600',
  pending_acceptance: 'bg-yellow-50 text-yellow-700',
  confirmed: 'bg-blue-50 text-blue-700',
  ready_for_pickup: 'bg-amber-50 text-amber-700',
  rider_assigned: 'bg-purple-50 text-purple-700',
  picked_up: 'bg-teal-50 text-teal-700',
  delivered: 'bg-green-50 text-green-700',
  cancelled: 'bg-red-50 text-red-600',
  payment_failed: 'bg-red-50 text-red-600',
};

const CANCELLED_BY_STYLES: Record<string, string> = {
  customer: 'bg-blue-50 text-blue-700',
  restaurant: 'bg-orange-50 text-orange-700',
  admin: 'bg-red-50 text-red-700',
  system: 'bg-gray-100 text-gray-600',
};

const STUCK_STATUSES = ['pending_acceptance', 'confirmed', 'ready_for_pickup', 'rider_assigned', 'picked_up'];

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1, 2, 3, 4, 5].map((i) => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-20 bg-gray-200 rounded" />
          <div className="h-4 w-32 bg-gray-200 rounded" />
          <div className="h-4 w-28 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

export default function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('');
  const [paymentFilter, setPaymentFilter] = useState('');
  const [page, setPage] = useState(1);
  const [cancelTarget, setCancelTarget] = useState<Order | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const load = (p = page) => {
    setLoading(true);
    api.get('/admin/orders', {
      params: {
        status: statusFilter || undefined,
        payment_status: paymentFilter || undefined,
        page: p,
        limit: 30,
      },
    })
      .then((res) => {
        const data = res.data.data;
        if (Array.isArray(data)) {
          setOrders(data as Order[]);
          setPagination(null);
        } else {
          setOrders(data.orders as Order[]);
          setPagination(data.pagination as Pagination);
        }
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(1); setPage(1); }, []);

  const forceCancel = async () => {
    if (!cancelTarget) return;
    setActionLoading(cancelTarget.id);
    try {
      await api.put(`/admin/orders/${cancelTarget.id}/cancel`, { reason: cancelReason || 'Cancelled by admin' });
      setCancelTarget(null);
      setCancelReason('');
      load(page);
    } catch (e) { console.error(e); }
    finally { setActionLoading(null); }
  };

  const reassignRider = async (orderId: string) => {
    setActionLoading(orderId);
    try {
      await api.put(`/admin/orders/${orderId}/reassign-rider`);
      load(page);
    } catch (e) { console.error(e); }
    finally { setActionLoading(null); }
  };

  const applyFilters = () => { setPage(1); load(1); };
  const goToPage = (p: number) => { setPage(p); load(p); };

  const retryRefund = async (orderId: string) => {
    setActionLoading(orderId);
    try {
      await api.post('/payments/refund', { orderId });
      load(page);
    } catch (e) { console.error(e); }
    finally { setActionLoading(null); }
  };

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {pagination ? `${pagination.total.toLocaleString()} total orders` : `${orders.length} orders found`}
          </p>
        </div>
        <div className="flex gap-2">
          {/* Status filter */}
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
          >
            <option value="">All Statuses</option>
            {['pending_payment', 'pending_acceptance', 'confirmed', 'ready_for_pickup', 'rider_assigned', 'picked_up', 'delivered', 'cancelled', 'payment_failed'].map((s) => (
              <option key={s} value={s}>{s.replaceAll('_', ' ')}</option>
            ))}
          </select>
          {/* Payment status filter — Fix 4 */}
          <select
            value={paymentFilter}
            onChange={(e) => setPaymentFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
          >
            <option value="">All Payments</option>
            <option value="paid">Paid</option>
            <option value="refunded">Refunded</option>
            <option value="refund_failed">Refund Failed ⚠</option>
            <option value="failed">Payment Failed</option>
          </select>
          <button
            onClick={applyFilters}
            className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-xl text-sm font-medium transition-colors"
          >
            Apply
          </button>
        </div>
      </div>

      {/* Refund failed alert banner */}
      {paymentFilter === 'refund_failed' && orders.length > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 flex items-center gap-3">
          <svg className="w-5 h-5 text-red-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <p className="text-sm text-red-700">
            <span className="font-semibold">{orders.length} order{orders.length !== 1 ? 's' : ''}</span> with failed refunds — these customers need manual intervention.
          </p>
        </div>
      )}

      {loading ? <TableSkeleton /> : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-100">
              <tr>
                {['Order', 'Customer', 'Restaurant', 'Rider', 'Total', 'Status', 'Payment', 'Cancelled By', 'Date', 'Actions'].map((h) => (
                  <th key={h} className="text-left px-4 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {orders.length === 0 && (
                <tr>
                  <td colSpan={10} className="text-center py-16">
                    <div className="text-gray-300 text-4xl mb-3">📦</div>
                    <p className="text-gray-400 text-sm">No orders found</p>
                  </td>
                </tr>
              )}
              {orders.map((o) => (
                <tr key={o.id} className={`hover:bg-gray-50/50 transition-colors ${o.payment_status === 'refund_failed' ? 'bg-red-50/30' : ''}`}>
                  <td className="px-4 py-3.5 font-mono text-xs text-gray-500">{o.id.substring(0, 8)}…</td>
                  <td className="px-4 py-3.5">
                    <div className="font-medium text-gray-800">{o.customer_name || '—'}</div>
                    <div className="text-gray-400 text-xs">{o.customer_email}</div>
                  </td>
                  <td className="px-4 py-3.5 text-gray-700">{o.restaurant_name}</td>
                  <td className="px-4 py-3.5">
                    {o.rider_name ? (
                      <div>
                        <div className="text-gray-700">{o.rider_name}</div>
                        <div className="text-gray-400 text-xs">{o.rider_email}</div>
                      </div>
                    ) : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-4 py-3.5 font-semibold text-gray-800">ETB {Number(o.total).toFixed(2)}</td>
                  <td className="px-4 py-3.5">
                    <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${STATUS_STYLES[o.status] ?? 'bg-gray-100 text-gray-600'}`}>
                      {o.status.replaceAll('_', ' ')}
                    </span>
                  </td>
                  <td className="px-4 py-3.5">
                    {o.payment_status ? (
                      <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${
                        o.payment_status === 'refund_failed'
                          ? 'bg-red-100 text-red-700 font-bold'
                          : o.payment_status === 'refunded'
                          ? 'bg-green-50 text-green-700'
                          : o.payment_status === 'paid'
                          ? 'bg-blue-50 text-blue-700'
                          : 'bg-gray-100 text-gray-600'
                      }`}>
                        {o.payment_status === 'refund_failed' ? '⚠ ' : ''}{o.payment_status.replaceAll('_', ' ')}
                      </span>
                    ) : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-4 py-3.5">
                    {o.status === 'cancelled' && o.cancelled_by ? (
                      <div>
                        <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${CANCELLED_BY_STYLES[o.cancelled_by] ?? 'bg-gray-100 text-gray-600'}`}>
                          {o.cancelled_by}
                        </span>
                        {o.cancellation_reason && (
                          <div className="text-gray-400 text-xs mt-1 max-w-[100px] truncate" title={o.cancellation_reason}>
                            {o.cancellation_reason}
                          </div>
                        )}
                      </div>
                    ) : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-4 py-3.5 text-gray-400 text-xs whitespace-nowrap">
                    {new Date(o.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3.5">
                    <div className="flex gap-1.5">
                      {STUCK_STATUSES.includes(o.status) && (
                        <>
                          <button
                            onClick={() => setCancelTarget(o)}
                            disabled={actionLoading === o.id}
                            className="text-xs bg-red-500 hover:bg-red-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors"
                          >
                            Cancel
                          </button>
                          {['ready_for_pickup', 'rider_assigned'].includes(o.status) && (
                            <button
                              onClick={() => reassignRider(o.id)}
                              disabled={actionLoading === o.id}
                              className="text-xs bg-orange-500 hover:bg-orange-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors"
                            >
                              {actionLoading === o.id ? '…' : 'Reassign'}
                            </button>
                          )}
                        </>
                      )}
                      {o.payment_status === 'refund_failed' && (
                        <button
                          onClick={() => retryRefund(o.id)}
                          disabled={actionLoading === o.id}
                          className="text-xs bg-purple-500 hover:bg-purple-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors"
                        >
                          {actionLoading === o.id ? '…' : 'Retry Refund'}
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* Pagination — Fix 5 */}
          {pagination && pagination.pages > 1 && (
            <div className="px-5 py-4 border-t border-gray-100 flex items-center justify-between">
              <p className="text-xs text-gray-500">
                Showing {((pagination.page - 1) * pagination.limit) + 1}–{Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total.toLocaleString()}
              </p>
              <div className="flex gap-1.5">
                <button
                  onClick={() => goToPage(pagination.page - 1)}
                  disabled={pagination.page <= 1}
                  className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors"
                >
                  ← Prev
                </button>
                {Array.from({ length: Math.min(pagination.pages, 5) }, (_, i) => {
                  const p = Math.max(1, pagination.page - 2) + i;
                  if (p > pagination.pages) return null;
                  return (
                    <button
                      key={p}
                      onClick={() => goToPage(p)}
                      className={`px-3 py-1.5 text-xs rounded-lg border transition-colors ${
                        p === pagination.page
                          ? 'bg-orange-500 text-white border-orange-500'
                          : 'border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      {p}
                    </button>
                  );
                })}
                <button
                  onClick={() => goToPage(pagination.page + 1)}
                  disabled={pagination.page >= pagination.pages}
                  className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors"
                >
                  Next →
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Force Cancel Modal */}
      {cancelTarget && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-md shadow-2xl">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 bg-red-50 rounded-xl flex items-center justify-center">
                <svg className="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <div>
                <h2 className="font-bold text-gray-900">Force Cancel Order</h2>
                <p className="text-gray-400 text-xs">A refund will be initiated automatically</p>
              </div>
            </div>
            <p className="text-sm text-gray-600 mb-4 bg-gray-50 rounded-xl px-4 py-3">
              Cancelling order <span className="font-mono font-bold text-gray-800">{cancelTarget.id.substring(0, 8)}…</span> for{' '}
              <span className="font-medium">{cancelTarget.customer_name || cancelTarget.customer_email}</span>
            </p>
            <div className="mb-5">
              <label className="block text-sm font-medium text-gray-700 mb-1.5">Reason (optional)</label>
              <input
                type="text"
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                placeholder="e.g. Restaurant closed, payment issue..."
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
              />
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => { setCancelTarget(null); setCancelReason(''); }}
                className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-medium hover:bg-gray-50 transition-colors"
              >
                Back
              </button>
              <button
                onClick={forceCancel}
                disabled={actionLoading === cancelTarget.id}
                className="flex-1 bg-red-500 hover:bg-red-600 text-white rounded-xl py-2.5 text-sm font-medium disabled:opacity-50 transition-colors"
              >
                {actionLoading === cancelTarget.id ? 'Cancelling…' : 'Confirm Cancel'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
