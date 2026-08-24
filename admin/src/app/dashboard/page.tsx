'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
} from 'recharts';
import { api } from '@/lib/api';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Analytics {
  totalOrders: number;
  totalRevenue: number;
  activeUsers: number;
  refundFailedCount: number;
  ordersByStatus: { status: string; count: string }[];
  topRestaurants: { name: string; order_count: string }[];
  topRiders: { display_name: string; delivery_count: string }[];
  dateRange: { start: string; end: string };
}

interface PendingRestaurant {
  id: string;
  name: string;
  owner_name: string | null;
  owner_email: string;
  address: string;
  created_at: string;
  logo_url: string | null;
}

interface PendingRider {
  id: string;
  display_name: string | null;
  email: string;
  phone: string | null;
  created_at: string;
  invitation_status: string | null;
  invited_by: string | null;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const STATUS_COLORS = [
  '#f97316', '#3b82f6', '#10b981', '#ef4444',
  '#8b5cf6', '#f59e0b', '#06b6d4', '#84cc16',
];

// ── Shared helpers ────────────────────────────────────────────────────────────

function StatCard({
  label, value, icon, color,
}: {
  label: string; value: string | number; icon: React.ReactNode; color: string;
}) {
  return (
    <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
      <div className={`inline-flex items-center justify-center w-10 h-10 rounded-xl mb-4 ${color}`}>
        {icon}
      </div>
      <div className="text-2xl font-bold text-gray-900">{value}</div>
      <div className="text-gray-500 text-sm mt-0.5">{label}</div>
    </div>
  );
}

function LoadingSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      <div className="h-8 w-40 bg-gray-200 rounded-lg" />
      <div className="grid grid-cols-2 gap-4">
        {[1, 2].map((i) => <div key={i} className="h-44 bg-gray-200 rounded-2xl" />)}
      </div>
      <div className="grid grid-cols-3 gap-4">
        {[1, 2, 3].map((i) => <div key={i} className="h-32 bg-gray-200 rounded-2xl" />)}
      </div>
      <div className="grid grid-cols-2 gap-6">
        {[1, 2].map((i) => <div key={i} className="h-64 bg-gray-200 rounded-2xl" />)}
      </div>
      <div className="h-48 bg-gray-200 rounded-2xl" />
    </div>
  );
}

// ── Pending approvals section ─────────────────────────────────────────────────

function PendingRestaurantsCard({
  items,
  onApprove,
  onReject,
  acting,
}: {
  items: PendingRestaurant[];
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
  acting: string | null;
}) {
  const router = useRouter();
  return (
    <div className="bg-white rounded-2xl border border-amber-200 shadow-sm overflow-hidden">
      {/* Card header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-amber-100 bg-amber-50">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-xl bg-amber-100 flex items-center justify-center">
            <svg className="w-4 h-4 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
            </svg>
          </div>
          <div>
            <h3 className="font-semibold text-gray-900 text-sm">Pending Restaurants</h3>
            <p className="text-xs text-amber-700">{items.length} awaiting review</p>
          </div>
        </div>
        <button
          onClick={() => router.push('/dashboard/restaurants?status=pending')}
          className="text-xs font-semibold text-amber-700 hover:underline"
        >
          View all →
        </button>
      </div>

      {/* Items */}
      <div className="divide-y divide-gray-50">
        {items.map((r) => (
          <div key={r.id} className="flex items-center gap-3 px-5 py-3.5 hover:bg-gray-50/60 transition-colors">
            {/* Avatar */}
            {r.logo_url ? (
              <img src={r.logo_url} alt={r.name}
                className="w-9 h-9 rounded-xl object-cover shrink-0" />
            ) : (
              <div className="w-9 h-9 rounded-xl bg-orange-50 flex items-center justify-center text-orange-500 font-bold text-sm shrink-0">
                {r.name[0].toUpperCase()}
              </div>
            )}

            {/* Info */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-800 truncate">{r.name}</p>
              <p className="text-xs text-gray-400 truncate">
                {r.owner_name ? `${r.owner_name} · ` : ''}{r.owner_email}
              </p>
              <p className="text-xs text-gray-400 truncate">{r.address}</p>
            </div>

            {/* Age */}
            <div className="text-xs text-gray-400 whitespace-nowrap shrink-0 text-right">
              {formatAge(r.created_at)}
            </div>

            {/* Quick actions */}
            <div className="flex gap-1.5 shrink-0" onClick={(e) => e.stopPropagation()}>
              <button
                onClick={() => onApprove(r.id)}
                disabled={acting === r.id}
                className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-2.5 py-1.5 rounded-lg font-medium transition-colors"
              >
                {acting === r.id ? '…' : 'Approve'}
              </button>
              <button
                onClick={() => onReject(r.id)}
                disabled={acting === r.id}
                className="text-xs bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-2.5 py-1.5 rounded-lg font-medium transition-colors"
              >
                Reject
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PendingRidersCard({
  items,
  onApprove,
  onReject,
  acting,
}: {
  items: PendingRider[];
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
  acting: string | null;
}) {
  const router = useRouter();
  return (
    <div className="bg-white rounded-2xl border border-blue-200 shadow-sm overflow-hidden">
      {/* Card header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-blue-100 bg-blue-50">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-xl bg-blue-100 flex items-center justify-center">
            <svg className="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
          </div>
          <div>
            <h3 className="font-semibold text-gray-900 text-sm">Pending Riders</h3>
            <p className="text-xs text-blue-700">{items.length} awaiting review</p>
          </div>
        </div>
        <button
          onClick={() => router.push('/dashboard/riders?status=pending')}
          className="text-xs font-semibold text-blue-700 hover:underline"
        >
          View all →
        </button>
      </div>

      {/* Items */}
      <div className="divide-y divide-gray-50">
        {items.map((r) => (
          <div key={r.id} className="flex items-center gap-3 px-5 py-3.5 hover:bg-gray-50/60 transition-colors">
            {/* Avatar */}
            <div className="w-9 h-9 rounded-full bg-purple-100 flex items-center justify-center text-purple-600 font-semibold text-sm shrink-0">
              {(r.display_name || r.email)[0].toUpperCase()}
            </div>

            {/* Info */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-800 truncate">
                {r.display_name || <span className="text-gray-400 italic">No name</span>}
              </p>
              <p className="text-xs text-gray-400 truncate">{r.email}</p>
              {r.phone && <p className="text-xs text-gray-400">{r.phone}</p>}
              {/* Invitation context */}
              {r.invitation_status === 'pending' && r.invited_by && (
                <p className="text-xs text-amber-600 font-medium mt-0.5">
                  ⏳ Invited by {r.invited_by}
                </p>
              )}
            </div>

            {/* Age */}
            <div className="text-xs text-gray-400 whitespace-nowrap shrink-0 text-right">
              {formatAge(r.created_at)}
            </div>

            {/* Quick actions */}
            <div className="flex gap-1.5 shrink-0" onClick={(e) => e.stopPropagation()}>
              <button
                onClick={() => onApprove(r.id)}
                disabled={acting === r.id}
                className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-2.5 py-1.5 rounded-lg font-medium transition-colors"
              >
                {acting === r.id ? '…' : 'Approve'}
              </button>
              <button
                onClick={() => onReject(r.id)}
                disabled={acting === r.id}
                className="text-xs bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-2.5 py-1.5 rounded-lg font-medium transition-colors"
              >
                Reject
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Reject reason mini-modal (inline, lightweight) ────────────────────────────

function InlineRejectModal({
  title,
  onConfirm,
  onCancel,
}: {
  title: string;
  onConfirm: (reason: string) => void;
  onCancel: () => void;
}) {
  const [reason, setReason] = useState('');
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md mx-4 p-6">
        <h3 className="text-base font-semibold text-gray-900 mb-1">{title}</h3>
        <p className="text-sm text-gray-500 mb-3">Provide a reason so the applicant knows what to fix.</p>
        <textarea
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-red-300"
          rows={3}
          placeholder="Reason for rejection..."
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          autoFocus
        />
        <div className="flex gap-2 mt-3 justify-end">
          <button onClick={onCancel}
            className="px-4 py-2 text-sm text-gray-600 hover:bg-gray-100 rounded-xl transition-colors">
            Cancel
          </button>
          <button
            onClick={() => onConfirm(reason.trim())}
            disabled={!reason.trim()}
            className="px-4 py-2 text-sm bg-red-500 hover:bg-red-600 disabled:opacity-40 text-white rounded-xl font-medium transition-colors"
          >
            Confirm Rejection
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Utility ───────────────────────────────────────────────────────────────────

function formatAge(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins  = Math.floor(diff / 60_000);
  const hours = Math.floor(diff / 3_600_000);
  const days  = Math.floor(diff / 86_400_000);
  if (mins  < 60)  return `${mins}m ago`;
  if (hours < 24)  return `${hours}h ago`;
  return `${days}d ago`;
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function DashboardPage() {
  const [analytics, setAnalytics]                   = useState<Analytics | null>(null);
  const [analyticsLoading, setAnalyticsLoading]     = useState(true);
  const [startDate, setStartDate]                   = useState('');
  const [endDate, setEndDate]                       = useState('');

  // Pending approvals state
  const [pendingRestaurants, setPendingRestaurants] = useState<PendingRestaurant[]>([]);
  const [pendingRiders, setPendingRiders]           = useState<PendingRider[]>([]);
  const [pendingLoading, setPendingLoading]         = useState(true);
  const [acting, setActing]                         = useState<string | null>(null);
  const [rejectModal, setRejectModal]               = useState<{
    id: string; type: 'restaurant' | 'rider';
  } | null>(null);

  // ── Loaders ────────────────────────────────────────────────────────────────

  const loadAnalytics = (start?: string, end?: string) => {
    setAnalyticsLoading(true);
    api.get('/admin/analytics', {
      params: { startDate: start || undefined, endDate: end || undefined },
    })
      .then((res) => setAnalytics(res.data.data as Analytics))
      .catch(console.error)
      .finally(() => setAnalyticsLoading(false));
  };

  const loadPending = () => {
    setPendingLoading(true);
    Promise.all([
      api.get('/admin/restaurants', { params: { status: 'pending', limit: 10 } }),
      api.get('/admin/riders',      { params: { status: 'pending', limit: 10 } }),
    ])
      .then(([rRes, ridRes]) => {
        // Restaurants endpoint returns an array directly; riders returns { riders, pagination }
        const rData   = rRes.data.data;
        const ridData = ridRes.data.data;
        setPendingRestaurants(Array.isArray(rData) ? rData as PendingRestaurant[] : []);
        setPendingRiders(Array.isArray(ridData) ? ridData as PendingRider[] : (ridData?.riders ?? []) as PendingRider[]);
      })
      .catch(console.error)
      .finally(() => setPendingLoading(false));
  };

  useEffect(() => {
    loadAnalytics();
    loadPending();
  }, []);

  // ── Actions ────────────────────────────────────────────────────────────────

  const approveRestaurant = async (id: string) => {
    setActing(id);
    try {
      await api.post(`/admin/restaurants/${id}/approve`);
      loadPending();
    } catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  const rejectRestaurant = async (id: string, reason: string) => {
    setActing(id);
    try {
      await api.post(`/admin/restaurants/${id}/reject`, { reason });
      loadPending();
    } catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  const approveRider = async (id: string) => {
    setActing(id);
    try {
      await api.put(`/admin/users/${id}/approve`);
      loadPending();
    } catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  const rejectRider = async (id: string, reason: string) => {
    setActing(id);
    try {
      await api.put(`/admin/users/${id}/reject`, { reason });
      loadPending();
    } catch (e) { console.error(e); }
    finally { setActing(null); }
  };

  // ── Render ─────────────────────────────────────────────────────────────────

  const totalPending = pendingRestaurants.length + pendingRiders.length;

  return (
    <>
      {/* Reject reason modal */}
      {rejectModal && (
        <InlineRejectModal
          title={rejectModal.type === 'restaurant' ? 'Reject Restaurant' : 'Reject Rider'}
          onConfirm={(reason) => {
            const { id, type } = rejectModal;
            setRejectModal(null);
            if (type === 'restaurant') void rejectRestaurant(id, reason);
            else                       void rejectRider(id, reason);
          }}
          onCancel={() => setRejectModal(null)}
        />
      )}

      <div className="space-y-6">

        {/* Page title */}
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p className="text-gray-500 text-sm mt-0.5">Platform overview</p>
        </div>

        {/* ── PENDING APPROVALS ──────────────────────────────────────────────
            Shown only when there is at least one pending item.
            Rendered before the analytics so it's the first thing the admin
            sees — matches how real ops dashboards (e.g. Doordash Merchant,
            Uber Eats Operations) surface time-sensitive action items. */}
        {!pendingLoading && totalPending > 0 && (
          <section>
            <div className="flex items-center gap-2 mb-3">
              <h2 className="text-base font-semibold text-gray-900">Pending Approvals</h2>
              <span className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-red-500 text-white text-xs font-bold">
                {totalPending}
              </span>
            </div>
            <div className={`grid gap-4 ${
              pendingRestaurants.length > 0 && pendingRiders.length > 0
                ? 'grid-cols-1 xl:grid-cols-2'
                : 'grid-cols-1 max-w-2xl'
            }`}>
              {pendingRestaurants.length > 0 && (
                <PendingRestaurantsCard
                  items={pendingRestaurants}
                  acting={acting}
                  onApprove={(id) => void approveRestaurant(id)}
                  onReject={(id) => setRejectModal({ id, type: 'restaurant' })}
                />
              )}
              {pendingRiders.length > 0 && (
                <PendingRidersCard
                  items={pendingRiders}
                  acting={acting}
                  onApprove={(id) => void approveRider(id)}
                  onReject={(id) => setRejectModal({ id, type: 'rider' })}
                />
              )}
            </div>
          </section>
        )}

        {/* Pending loading skeleton */}
        {pendingLoading && (
          <div className="grid grid-cols-2 gap-4 animate-pulse">
            {[1, 2].map((i) => (
              <div key={i} className="h-44 bg-gray-100 rounded-2xl" />
            ))}
          </div>
        )}

        {/* ── ANALYTICS ─────────────────────────────────────────────────── */}

        {analyticsLoading ? (
          <LoadingSkeleton />
        ) : !analytics ? (
          <div className="flex items-center justify-center h-64">
            <div className="text-center">
              <div className="text-red-400 text-4xl mb-3">⚠</div>
              <p className="text-gray-500">Failed to load analytics</p>
            </div>
          </div>
        ) : (
          <>
            {/* Date range picker */}
            <div className="flex items-center gap-3 bg-white rounded-xl border border-gray-200 px-4 py-3">
              <svg className="w-4 h-4 text-gray-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)}
                className="text-sm border-0 outline-none text-gray-700" />
              <span className="text-gray-400 text-sm">→</span>
              <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)}
                className="text-sm border-0 outline-none text-gray-700" />
              <button
                onClick={() => loadAnalytics(startDate || undefined, endDate || undefined)}
                className="ml-auto bg-orange-500 hover:bg-orange-600 text-white px-4 py-1.5 rounded-lg text-sm font-medium transition-colors"
              >
                Apply
              </button>
              {(startDate || endDate) && (
                <button
                  onClick={() => { setStartDate(''); setEndDate(''); loadAnalytics(); }}
                  className="text-gray-400 hover:text-gray-600 text-sm transition-colors"
                >
                  Reset
                </button>
              )}
            </div>

            {/* Refund failed alert */}
            {analytics.refundFailedCount > 0 && (
              <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 flex items-center gap-3">
                <svg className="w-5 h-5 text-red-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <p className="text-sm text-red-700 flex-1">
                  <span className="font-semibold">
                    {analytics.refundFailedCount} order{analytics.refundFailedCount !== 1 ? 's' : ''}
                  </span>{' '}
                  have failed refunds and need manual intervention.
                </p>
                <a href="/dashboard/orders?payment_status=refund_failed"
                  className="text-sm font-semibold text-red-700 hover:underline whitespace-nowrap">
                  View orders →
                </a>
              </div>
            )}

            {/* KPI cards */}
            <div className="grid grid-cols-3 gap-4">
              <StatCard
                label="Total Orders"
                value={analytics.totalOrders.toLocaleString()}
                color="bg-orange-50"
                icon={
                  <svg className="w-5 h-5 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                      d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                  </svg>
                }
              />
              <StatCard
                label="Total Revenue"
                value={`ETB ${analytics.totalRevenue.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`}
                color="bg-green-50"
                icon={
                  <svg className="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                      d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                }
              />
              <StatCard
                label="Active Users"
                value={analytics.activeUsers.toLocaleString()}
                color="bg-blue-50"
                icon={
                  <svg className="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                      d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                }
              />
            </div>

            {/* Charts */}
            <div className="grid grid-cols-2 gap-6">
              {/* Orders by status */}
              <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
                <h2 className="font-semibold text-gray-900 mb-1">Orders by Status</h2>
                <p className="text-gray-400 text-xs mb-4">Distribution across all statuses</p>
                <ResponsiveContainer width="100%" height={220}>
                  <PieChart>
                    <Pie
                      data={analytics.ordersByStatus.map((d) => ({ ...d, count: parseInt(d.count, 10) }))}
                      dataKey="count" nameKey="status"
                      cx="50%" cy="50%" outerRadius={80} innerRadius={40}
                    >
                      {analytics.ordersByStatus.map((_, i) => (
                        <Cell key={i} fill={STATUS_COLORS[i % STATUS_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      formatter={(value, name) => [value, String(name).replaceAll('_', ' ')]}
                      contentStyle={{ borderRadius: '8px', border: '1px solid #e5e7eb', fontSize: '12px' }}
                    />
                    <Legend
                      formatter={(value) => String(value).replaceAll('_', ' ')}
                      wrapperStyle={{ fontSize: '11px' }}
                    />
                  </PieChart>
                </ResponsiveContainer>
              </div>

              {/* Top restaurants */}
              <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
                <h2 className="font-semibold text-gray-900 mb-1">Top Restaurants</h2>
                <p className="text-gray-400 text-xs mb-4">By order volume</p>
                <ResponsiveContainer width="100%" height={220}>
                  <BarChart
                    data={analytics.topRestaurants.map((r) => ({
                      ...r, order_count: parseInt(r.order_count, 10),
                    }))}
                    margin={{ top: 0, right: 0, left: -20, bottom: 0 }}
                  >
                    <XAxis dataKey="name" tick={{ fontSize: 10 }} tickLine={false} axisLine={false} />
                    <YAxis tick={{ fontSize: 10 }} tickLine={false} axisLine={false} />
                    <Tooltip
                      contentStyle={{ borderRadius: '8px', border: '1px solid #e5e7eb', fontSize: '12px' }}
                      cursor={{ fill: '#f9fafb' }}
                    />
                    <Bar dataKey="order_count" fill="#f97316" radius={[4, 4, 0, 0]} name="Orders" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Top riders */}
            <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
              <div className="px-6 py-4 border-b border-gray-50">
                <h2 className="font-semibold text-gray-900">Top Riders</h2>
                <p className="text-gray-400 text-xs mt-0.5">By completed deliveries</p>
              </div>
              <table className="w-full text-sm">
                <thead className="bg-gray-50">
                  <tr>
                    {['#', 'Rider', 'Deliveries'].map((h) => (
                      <th key={h} className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {analytics.topRiders.length === 0 && (
                    <tr><td colSpan={3} className="text-center py-8 text-gray-400 text-sm">No data yet</td></tr>
                  )}
                  {analytics.topRiders.map((r, i) => (
                    <tr key={i} className="hover:bg-gray-50 transition-colors">
                      <td className="px-6 py-3.5 text-gray-400 text-xs font-mono">{i + 1}</td>
                      <td className="px-6 py-3.5">
                        <div className="flex items-center gap-3">
                          <div className="w-7 h-7 rounded-full bg-orange-100 flex items-center justify-center text-orange-600 text-xs font-bold">
                            {(r.display_name || 'U')[0].toUpperCase()}
                          </div>
                          <span className="font-medium text-gray-800">{r.display_name || 'Unknown'}</span>
                        </div>
                      </td>
                      <td className="px-6 py-3.5">
                        <span className="inline-flex items-center gap-1.5 bg-green-50 text-green-700 text-xs font-semibold px-2.5 py-1 rounded-full">
                          {r.delivery_count} deliveries
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </>
  );
}
