'use client';
import { useEffect, useState, useCallback, useRef } from 'react';
import { api } from '@/lib/api';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Order {
  id: string;
  status: string;
  total: number;
  subtotal: number;
  delivery_fee: number;
  payment_status: string | null;
  payment_reference: string | null;
  payment_method: string | null;
  cancellation_reason: string | null;
  cancelled_by: 'customer' | 'restaurant' | 'admin' | 'system' | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
  estimated_delivery_time: string | null;
  estimated_prep_time_minutes: number | null;
  notes: string | null;
  customer_id: string;
  customer_email: string;
  customer_name: string | null;
  customer_phone: string | null;
  restaurant_id: string;
  restaurant_name: string;
  rider_id: string | null;
  rider_name: string | null;
  rider_email: string | null;
  rider_phone: string | null;
  delivery_address: string | null;
  delivery_city: string | null;
}

interface OrderDetail extends Order {
  restaurant_address: string | null;
  delivery_line1: string | null;
  delivery_line2: string | null;
  delivery_lat: number | null;
  delivery_lon: number | null;
  dispute_id: string | null;
  items: OrderItem[];
}

interface OrderItem {
  id: string;
  item_name: string;
  quantity: number;
  unit_price: number;
  item_image_url: string | null;
  selected_modifiers: unknown[];
}

interface Pagination { page: number; limit: number; total: number; pages: number; }

// ── Constants ─────────────────────────────────────────────────────────────────

const STATUS_STYLES: Record<string, string> = {
  pending_payment:    'bg-gray-100 text-gray-600',
  pending_acceptance: 'bg-yellow-50 text-yellow-700',
  confirmed:          'bg-blue-50 text-blue-700',
  ready_for_pickup:   'bg-amber-50 text-amber-700',
  rider_assigned:     'bg-purple-50 text-purple-700',
  picked_up:          'bg-teal-50 text-teal-700',
  delivered:          'bg-green-50 text-green-700',
  cancelled:          'bg-red-50 text-red-600',
  payment_failed:     'bg-red-50 text-red-600',
};

const CANCELLED_BY_STYLES: Record<string, string> = {
  customer:   'bg-blue-50 text-blue-700',
  restaurant: 'bg-orange-50 text-orange-700',
  admin:      'bg-red-50 text-red-700',
  system:     'bg-gray-100 text-gray-600',
};

const STUCK_STATUSES = ['pending_acceptance','confirmed','ready_for_pickup','rider_assigned','picked_up'];

// Status timeline — in chronological order
const STATUS_TIMELINE = [
  { key: 'pending_payment',    label: 'Payment',       icon: '💳' },
  { key: 'pending_acceptance', label: 'Placed',        icon: '📋' },
  { key: 'confirmed',          label: 'Confirmed',     icon: '✅' },
  { key: 'ready_for_pickup',   label: 'Ready',         icon: '🍱' },
  { key: 'rider_assigned',     label: 'Rider Assigned',icon: '🏍' },
  { key: 'picked_up',          label: 'Picked Up',     icon: '📦' },
  { key: 'delivered',          label: 'Delivered',     icon: '🎉' },
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(d: string) {
  return new Date(d).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

function fmtTime(d: string) {
  return new Date(d).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1,2,3,4,5].map((i) => (
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

// ── CSV Export ────────────────────────────────────────────────────────────────

function exportCSV(orders: Order[]) {
  const headers = [
    'Order ID','Status','Customer','Customer Email','Restaurant',
    'Rider','Total (ETB)','Payment Status','Payment Ref','Cancelled By',
    'Cancellation Reason','Delivery Address','Created At',
  ];
  const rows = orders.map((o) => [
    o.id,
    o.status,
    o.customer_name ?? '',
    o.customer_email,
    o.restaurant_name,
    o.rider_name ?? '',
    Number(o.total).toFixed(2),
    o.payment_status ?? '',
    o.payment_reference ?? '',
    o.cancelled_by ?? '',
    o.cancellation_reason ?? '',
    [o.delivery_address, o.delivery_city].filter(Boolean).join(', '),
    new Date(o.created_at).toISOString(),
  ]);
  const csv = [headers, ...rows]
    .map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(','))
    .join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = `orders_${new Date().toISOString().slice(0,10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── Order Timeline ────────────────────────────────────────────────────────────

function OrderTimeline({ order }: { order: OrderDetail }) {
  const currentIdx = STATUS_TIMELINE.findIndex((s) => s.key === order.status);
  const isCancelled = order.status === 'cancelled';

  return (
    <div className="py-2">
      {isCancelled ? (
        <div className="flex items-start gap-3 p-3 bg-red-50 rounded-xl border border-red-100">
          <span className="text-xl">❌</span>
          <div>
            <p className="text-sm font-semibold text-red-700">Order Cancelled</p>
            {order.cancelled_at && (
              <p className="text-xs text-red-500 mt-0.5">{fmt(order.cancelled_at)}</p>
            )}
            {order.cancelled_by && (
              <p className="text-xs text-red-500">by {order.cancelled_by}</p>
            )}
            {order.cancellation_reason && (
              <p className="text-xs text-red-600 mt-1 italic">"{order.cancellation_reason}"</p>
            )}
          </div>
        </div>
      ) : (
        <div className="relative">
          {/* Connecting line */}
          <div className="absolute left-4 top-4 bottom-4 w-0.5 bg-gray-100" />
          <div className="space-y-1">
            {STATUS_TIMELINE.map((step, i) => {
              const done    = i <= currentIdx;
              const current = i === currentIdx;
              return (
                <div key={step.key} className={`relative flex items-center gap-3 px-2 py-2 rounded-xl transition-colors ${current ? 'bg-orange-50' : ''}`}>
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm shrink-0 z-10 border-2 ${
                    done
                      ? current
                        ? 'bg-orange-500 border-orange-500 text-white'
                        : 'bg-green-500 border-green-500 text-white'
                      : 'bg-white border-gray-200 text-gray-300'
                  }`}>
                    {done ? (current ? step.icon : '✓') : step.icon}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`text-sm font-medium ${done ? (current ? 'text-orange-700' : 'text-gray-700') : 'text-gray-300'}`}>
                      {step.label}
                    </p>
                    {current && (
                      <p className="text-xs text-orange-500 mt-0.5">{fmt(order.updated_at)}</p>
                    )}
                    {step.key === 'pending_acceptance' && done && !current && (
                      <p className="text-xs text-gray-400">{fmt(order.created_at)}</p>
                    )}
                    {step.key === 'delivered' && done && (
                      <p className="text-xs text-green-500">{fmt(order.updated_at)}</p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ETA */}
      {order.estimated_delivery_time && order.status !== 'delivered' && order.status !== 'cancelled' && (
        <div className="mt-3 flex items-center gap-2 bg-blue-50 rounded-xl px-3 py-2">
          <span className="text-base">🕐</span>
          <p className="text-xs text-blue-700">
            Estimated delivery by <span className="font-semibold">{fmtTime(order.estimated_delivery_time)}</span>
          </p>
        </div>
      )}
    </div>
  );
}

// ── Detail Drawer ─────────────────────────────────────────────────────────────

type DrawerTab = 'details' | 'timeline';

function DetailDrawer({
  orderId,
  onClose,
  onCancel,
  onReassign,
  onRetryRefund,
  acting,
}: {
  orderId: string;
  onClose: () => void;
  onCancel: (order: Order) => void;
  onReassign: (id: string) => void;
  onRetryRefund: (id: string) => void;
  acting: string | null;
}) {
  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<DrawerTab>('details');

  useEffect(() => {
    setLoading(true);
    api.get(`/admin/orders/${orderId}`)
      .then((r) => setOrder(r.data.data as OrderDetail))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [orderId]);

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-lg bg-white shadow-2xl flex flex-col h-full overflow-hidden">
        {/* Header */}
        <div className="flex items-start justify-between px-6 pt-6 pb-4 border-b border-gray-100 shrink-0">
          <div>
            <p className="text-xs text-gray-400 font-mono">{orderId}</p>
            {order && (
              <div className="flex items-center gap-2 mt-1">
                <span className={`px-2.5 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[order.status] ?? 'bg-gray-100 text-gray-600'}`}>
                  {order.status.replace(/_/g, ' ')}
                </span>
                {order.dispute_id && (
                  <span className="px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">⚠ Dispute</span>
                )}
              </div>
            )}
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 p-1 rounded-lg hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-gray-100 shrink-0 px-6">
          {(['details','timeline'] as DrawerTab[]).map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-1 py-3 mr-6 text-sm font-medium border-b-2 transition-colors capitalize ${
                tab === t ? 'border-orange-500 text-orange-600' : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}>
              {t}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {loading ? (
            <div className="space-y-3">
              {[1,2,3,4].map((i) => <div key={i} className="h-12 bg-gray-100 rounded-xl animate-pulse" />)}
            </div>
          ) : !order ? (
            <p className="text-gray-400 text-sm text-center mt-16">Could not load order.</p>
          ) : tab === 'timeline' ? (
            <OrderTimeline order={order} />
          ) : (
            <div className="space-y-5">
              {/* Totals */}
              <div className="bg-gray-50 rounded-xl p-4 space-y-2">
                {[
                  { label: 'Subtotal', value: `ETB ${Number(order.subtotal).toFixed(2)}` },
                  { label: 'Delivery Fee', value: `ETB ${Number(order.delivery_fee).toFixed(2)}` },
                  { label: 'Total', value: `ETB ${Number(order.total).toFixed(2)}`, bold: true },
                ].map((r) => (
                  <div key={r.label} className="flex justify-between">
                    <span className={`text-sm ${r.bold ? 'font-semibold text-gray-900' : 'text-gray-500'}`}>{r.label}</span>
                    <span className={`text-sm ${r.bold ? 'font-semibold text-gray-900' : 'text-gray-700'}`}>{r.value}</span>
                  </div>
                ))}
                <div className="flex justify-between pt-1 border-t border-gray-200">
                  <span className="text-xs text-gray-400">Payment</span>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                    order.payment_status === 'paid' ? 'bg-green-50 text-green-700' :
                    order.payment_status === 'refund_failed' ? 'bg-red-100 text-red-700' :
                    order.payment_status === 'refunded' ? 'bg-blue-50 text-blue-700' :
                    'bg-gray-100 text-gray-500'
                  }`}>{order.payment_status ?? '—'}</span>
                </div>
                {order.payment_reference && (
                  <p className="text-xs text-gray-400 font-mono break-all">Ref: {order.payment_reference}</p>
                )}
              </div>

              {/* Items */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Items</p>
                <div className="space-y-2">
                  {order.items.map((item) => (
                    <div key={item.id} className="flex items-center gap-3">
                      {item.item_image_url ? (
                        <img src={item.item_image_url} alt={item.item_name} className="w-10 h-10 rounded-lg object-cover shrink-0" />
                      ) : (
                        <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center text-base shrink-0">🍴</div>
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-gray-800 font-medium truncate">{item.item_name}</p>
                        <p className="text-xs text-gray-400">x{item.quantity}</p>
                      </div>
                      <span className="text-sm font-semibold text-gray-800 shrink-0">
                        ETB {(Number(item.unit_price) * item.quantity).toFixed(2)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>

              {/* People */}
              {[
                { label: 'Customer', name: order.customer_name, email: order.customer_email, phone: order.customer_phone },
                { label: 'Rider', name: order.rider_name, email: order.rider_email, phone: order.rider_phone },
              ].map((p) => p.email && (
                <div key={p.label}>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">{p.label}</p>
                  <div className="bg-gray-50 rounded-xl px-4 py-3 space-y-0.5">
                    {p.name && <p className="text-sm font-medium text-gray-800">{p.name}</p>}
                    <p className="text-xs text-gray-500">{p.email}</p>
                    {p.phone && <p className="text-xs text-gray-500">{p.phone}</p>}
                  </div>
                </div>
              ))}

              {/* Delivery address */}
              {(order.delivery_line1 || order.delivery_city) && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">Delivery Address</p>
                  <div className="bg-gray-50 rounded-xl px-4 py-3">
                    {order.delivery_line1 && <p className="text-sm text-gray-800">{order.delivery_line1}</p>}
                    {order.delivery_line2 && <p className="text-sm text-gray-600">{order.delivery_line2}</p>}
                    {order.delivery_city && <p className="text-xs text-gray-500">{order.delivery_city}</p>}
                  </div>
                </div>
              )}

              {/* Notes */}
              {order.notes && (
                <div>
                  <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">Customer Note</p>
                  <p className="text-sm text-gray-600 bg-amber-50 rounded-xl px-4 py-3 italic">"{order.notes}"</p>
                </div>
              )}

              {/* Timestamps */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Timestamps</p>
                <div className="space-y-1">
                  {[
                    { label: 'Placed',   value: order.created_at },
                    { label: 'Updated',  value: order.updated_at },
                    { label: 'Cancelled',value: order.cancelled_at },
                    { label: 'Est. Delivery', value: order.estimated_delivery_time },
                  ].filter((t) => t.value).map((t) => (
                    <div key={t.label} className="flex justify-between">
                      <span className="text-xs text-gray-400">{t.label}</span>
                      <span className="text-xs text-gray-600">{fmt(t.value!)}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Action footer */}
        {order && (
          <div className="shrink-0 border-t border-gray-100 px-6 py-4 flex gap-2 flex-wrap">
            {STUCK_STATUSES.includes(order.status) && (
              <>
                <button onClick={() => onCancel(order)} disabled={acting === order.id}
                  className="flex-1 text-sm bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-4 py-2 rounded-xl transition-colors font-medium">
                  Force Cancel
                </button>
                {['ready_for_pickup','rider_assigned'].includes(order.status) && (
                  <button onClick={() => onReassign(order.id)} disabled={acting === order.id}
                    className="flex-1 text-sm bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white px-4 py-2 rounded-xl transition-colors font-medium">
                    {acting === order.id ? '…' : 'Reassign Rider'}
                  </button>
                )}
              </>
            )}
            {order.payment_status === 'refund_failed' && (
              <button onClick={() => onRetryRefund(order.id)} disabled={acting === order.id}
                className="flex-1 text-sm bg-purple-500 hover:bg-purple-600 disabled:opacity-50 text-white px-4 py-2 rounded-xl transition-colors font-medium">
                {acting === order.id ? '…' : 'Retry Refund'}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Cancel Modal ──────────────────────────────────────────────────────────────

function CancelModal({ order, onConfirm, onClose, loading }: {
  order: Order;
  onConfirm: (reason: string) => void;
  onClose: () => void;
  loading: boolean;
}) {
  const [reason, setReason] = useState('');
  return (
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
          Order <span className="font-mono font-bold text-gray-800">{order.id.slice(0,8)}…</span> for{' '}
          <span className="font-medium">{order.customer_name ?? order.customer_email}</span>
        </p>
        <div className="mb-5">
          <label className="block text-sm font-medium text-gray-700 mb-1.5">Reason (optional)</label>
          <input type="text" value={reason} onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Restaurant closed, payment issue..."
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
        </div>
        <div className="flex gap-3">
          <button onClick={onClose}
            className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-medium hover:bg-gray-50 transition-colors">
            Back
          </button>
          <button onClick={() => onConfirm(reason || 'Cancelled by admin')} disabled={loading}
            className="flex-1 bg-red-500 hover:bg-red-600 text-white rounded-xl py-2.5 text-sm font-medium disabled:opacity-50 transition-colors">
            {loading ? 'Cancelling…' : 'Confirm Cancel'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function OrdersPage() {
  const [orders, setOrders]           = useState<Order[]>([]);
  const [pagination, setPagination]   = useState<Pagination | null>(null);
  const [loading, setLoading]         = useState(true);
  const [statusFilter, setStatusFilter]   = useState('');
  const [paymentFilter, setPaymentFilter] = useState('');
  const [startDate, setStartDate]     = useState('');
  const [endDate, setEndDate]         = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch]           = useState('');
  const [page, setPage]               = useState(1);
  const [selectedId, setSelectedId]   = useState<string | null>(null);
  const [cancelTarget, setCancelTarget] = useState<Order | null>(null);
  const [acting, setActing]           = useState<string | null>(null);
  const searchTimer                   = useRef<ReturnType<typeof setTimeout>>();

  const load = useCallback((p: number, overrides?: {
    status?: string; payment?: string; q?: string; start?: string; end?: string;
  }) => {
    setLoading(true);
    const params: Record<string, string> = { page: String(p), limit: '30' };
    const s   = overrides?.status  ?? statusFilter;
    const pay = overrides?.payment ?? paymentFilter;
    const q   = overrides?.q       ?? search;
    const st  = overrides?.start   ?? startDate;
    const en  = overrides?.end     ?? endDate;
    if (s)   params.status         = s;
    if (pay) params.payment_status = pay;
    if (q)   params.search         = q;
    if (st)  params.startDate      = new Date(st).toISOString();
    if (en)  params.endDate        = new Date(en + 'T23:59:59').toISOString();
    api.get('/admin/orders', { params })
      .then((res) => {
        const d = res.data.data;
        setOrders(Array.isArray(d) ? (d as Order[]) : (d.orders as Order[]));
        setPagination(Array.isArray(d) ? null : (d.pagination as Pagination));
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [statusFilter, paymentFilter, search, startDate, endDate]);

  useEffect(() => { load(1); }, []);

  // Debounce search
  useEffect(() => {
    clearTimeout(searchTimer.current);
    searchTimer.current = setTimeout(() => {
      setSearch(searchInput);
      setPage(1);
      load(1, { q: searchInput });
    }, 350);
    return () => clearTimeout(searchTimer.current);
  }, [searchInput]);

  const applyFilters = () => { setPage(1); load(1); };
  const goToPage = (p: number) => { setPage(p); load(p); };

  const forceCancel = async (reason: string) => {
    if (!cancelTarget) return;
    setActing(cancelTarget.id);
    try {
      await api.put(`/admin/orders/${cancelTarget.id}/cancel`, { reason });
      setCancelTarget(null);
      load(page);
      if (selectedId === cancelTarget.id) setSelectedId(null);
    } catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  const reassignRider = async (orderId: string) => {
    setActing(orderId);
    try { await api.put(`/admin/orders/${orderId}/reassign-rider`); load(page); }
    catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  const retryRefund = async (orderId: string) => {
    setActing(orderId);
    try { await api.post('/payments/refund', { orderId }); load(page); }
    catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  return (
    <>
      {cancelTarget && (
        <CancelModal
          order={cancelTarget}
          onConfirm={forceCancel}
          onClose={() => setCancelTarget(null)}
          loading={acting === cancelTarget.id}
        />
      )}
      {selectedId && (
        <DetailDrawer
          orderId={selectedId}
          onClose={() => setSelectedId(null)}
          onCancel={(o) => { setSelectedId(null); setCancelTarget(o); }}
          onReassign={(id) => { reassignRider(id); setSelectedId(null); }}
          onRetryRefund={(id) => { retryRefund(id); setSelectedId(null); }}
          acting={acting}
        />
      )}

      <div className="space-y-5">
        {/* Header */}
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              {pagination ? `${pagination.total.toLocaleString()} total` : `${orders.length} orders`}
            </p>
          </div>
          <button
            onClick={() => exportCSV(orders)}
            disabled={orders.length === 0}
            className="flex items-center gap-2 border border-gray-200 rounded-xl px-4 py-2 text-sm font-medium hover:bg-gray-50 disabled:opacity-40 transition-colors"
          >
            <svg className="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
            Export CSV
          </button>
        </div>

        {/* Filters row */}
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 flex flex-wrap gap-3 items-end">
          {/* Search */}
          <div className="relative flex-1 min-w-48">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-4.35-4.35M17 11A6 6 0 111 11a6 6 0 0116 0z" />
            </svg>
            <input
              type="text"
              placeholder="Order ID, customer, restaurant…"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
            />
          </div>
          {/* Status */}
          <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white">
            <option value="">All Statuses</option>
            {['pending_payment','pending_acceptance','confirmed','ready_for_pickup',
              'rider_assigned','picked_up','delivered','cancelled','payment_failed'].map((s) => (
              <option key={s} value={s}>{s.replace(/_/g,' ')}</option>
            ))}
          </select>
          {/* Payment */}
          <select value={paymentFilter} onChange={(e) => setPaymentFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white">
            <option value="">All Payments</option>
            <option value="paid">Paid</option>
            <option value="refunded">Refunded</option>
            <option value="refund_failed">Refund Failed ⚠</option>
            <option value="failed">Failed</option>
          </select>
          {/* Date range */}
          <div className="flex items-center gap-2">
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)}
              className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
            <span className="text-gray-400 text-sm">—</span>
            <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)}
              className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" />
          </div>
          <button onClick={applyFilters}
            className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-xl text-sm font-medium transition-colors shrink-0">
            Apply
          </button>
          {(statusFilter || paymentFilter || startDate || endDate || search) && (
            <button onClick={() => {
              setStatusFilter(''); setPaymentFilter('');
              setStartDate(''); setEndDate('');
              setSearchInput(''); setSearch('');
              setPage(1); load(1, { status:'', payment:'', q:'', start:'', end:'' });
            }} className="text-sm text-gray-400 hover:text-gray-600 transition-colors px-2">
              Clear
            </button>
          )}
        </div>

        {/* Refund failed alert */}
        {paymentFilter === 'refund_failed' && orders.length > 0 && (
          <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 flex items-center gap-3">
            <svg className="w-5 h-5 text-red-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <p className="text-sm text-red-700">
              <span className="font-semibold">{orders.length} order{orders.length !== 1 ? 's' : ''}</span> with failed refunds — manual intervention needed.
            </p>
          </div>
        )}

        {/* Table */}
        {loading ? <TableSkeleton /> : (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  {['Order','Customer','Restaurant','Rider','Total','Status','Payment','Date','Actions'].map((h) => (
                    <th key={h} className="text-left px-4 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {orders.length === 0 && (
                  <tr><td colSpan={9} className="text-center py-16">
                    <div className="text-gray-300 text-4xl mb-3">📦</div>
                    <p className="text-gray-400 text-sm">No orders found</p>
                  </td></tr>
                )}
                {orders.map((o) => (
                  <tr key={o.id}
                    onClick={() => setSelectedId(o.id)}
                    className={`hover:bg-gray-50/50 transition-colors cursor-pointer ${o.payment_status === 'refund_failed' ? 'bg-red-50/30' : ''}`}>
                    <td className="px-4 py-3.5 font-mono text-xs text-gray-500">{o.id.slice(0,8)}…</td>
                    <td className="px-4 py-3.5">
                      <p className="font-medium text-gray-800 text-xs">{o.customer_name ?? '—'}</p>
                      <p className="text-gray-400 text-xs">{o.customer_email}</p>
                    </td>
                    <td className="px-4 py-3.5 text-gray-700 text-xs">{o.restaurant_name}</td>
                    <td className="px-4 py-3.5 text-xs">
                      {o.rider_name ? <span className="text-gray-700">{o.rider_name}</span> : <span className="text-gray-300">—</span>}
                    </td>
                    <td className="px-4 py-3.5 font-semibold text-gray-800 text-xs">ETB {Number(o.total).toFixed(2)}</td>
                    <td className="px-4 py-3.5">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[o.status] ?? 'bg-gray-100 text-gray-600'}`}>
                        {o.status.replace(/_/g,' ')}
                      </span>
                    </td>
                    <td className="px-4 py-3.5">
                      {o.payment_status ? (
                        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                          o.payment_status === 'refund_failed' ? 'bg-red-100 text-red-700 font-bold' :
                          o.payment_status === 'refunded'      ? 'bg-green-50 text-green-700' :
                          o.payment_status === 'paid'          ? 'bg-blue-50 text-blue-700' :
                          'bg-gray-100 text-gray-600'
                        }`}>
                          {o.payment_status === 'refund_failed' ? '⚠ ' : ''}{o.payment_status.replace(/_/g,' ')}
                        </span>
                      ) : <span className="text-gray-300 text-xs">—</span>}
                    </td>
                    <td className="px-4 py-3.5 text-gray-400 text-xs whitespace-nowrap">
                      {new Date(o.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-3.5" onClick={(e) => e.stopPropagation()}>
                      <div className="flex gap-1.5">
                        {STUCK_STATUSES.includes(o.status) && (
                          <>
                            <button onClick={() => setCancelTarget(o)} disabled={acting === o.id}
                              className="text-xs bg-red-500 hover:bg-red-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors">
                              Cancel
                            </button>
                            {['ready_for_pickup','rider_assigned'].includes(o.status) && (
                              <button onClick={() => reassignRider(o.id)} disabled={acting === o.id}
                                className="text-xs bg-orange-500 hover:bg-orange-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors">
                                {acting === o.id ? '…' : 'Reassign'}
                              </button>
                            )}
                          </>
                        )}
                        {o.payment_status === 'refund_failed' && (
                          <button onClick={() => retryRefund(o.id)} disabled={acting === o.id}
                            className="text-xs bg-purple-500 hover:bg-purple-600 text-white px-2.5 py-1.5 rounded-lg disabled:opacity-50 transition-colors">
                            {acting === o.id ? '…' : 'Retry Refund'}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {/* Pagination */}
            {pagination && pagination.pages > 1 && (
              <div className="px-5 py-4 border-t border-gray-100 flex items-center justify-between">
                <p className="text-xs text-gray-500">
                  Showing {((pagination.page - 1) * pagination.limit) + 1}–{Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total.toLocaleString()}
                </p>
                <div className="flex gap-1.5">
                  <button onClick={() => goToPage(pagination.page - 1)} disabled={pagination.page <= 1}
                    className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors">
                    ← Prev
                  </button>
                  {Array.from({ length: Math.min(pagination.pages, 5) }, (_, i) => {
                    const p = Math.max(1, pagination.page - 2) + i;
                    if (p > pagination.pages) return null;
                    return (
                      <button key={p} onClick={() => goToPage(p)}
                        className={`px-3 py-1.5 text-xs rounded-lg border transition-colors ${
                          p === pagination.page ? 'bg-orange-500 text-white border-orange-500' : 'border-gray-200 hover:bg-gray-50'
                        }`}>{p}</button>
                    );
                  })}
                  <button onClick={() => goToPage(pagination.page + 1)} disabled={pagination.page >= pagination.pages}
                    className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors">
                    Next →
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </>
  );
}
