'use client';
import { useEffect, useState, useCallback, useRef } from 'react';
import { api } from '@/lib/api';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Rider {
  id: string;
  email: string;
  display_name: string | null;
  phone: string | null;
  status: string;                 // 'pending' | 'active' | 'suspended'
  created_at: string;
  availability: string | null;   // 'available' | 'on_delivery' | 'offline'
  last_seen: string | null;
  restaurant_name: string | null;
  restaurant_id: string | null;
  total_deliveries: string;
  average_rating: string | null;
  invitation_status: string | null; // 'pending' | 'accepted' | 'declined'
  invited_by: string | null;        // restaurant name that sent the invitation
}

interface RiderDetail extends Rider {
  recent_deliveries: DeliveryRecord[];
  this_week_deliveries: number;
  this_month_deliveries: number;
  suspension_reason: string | null;
}

interface DeliveryRecord {
  id: string;
  status: string;
  total: number;
  created_at: string;
  restaurant_name: string | null;
  customer_name: string | null;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

type RiderAction = 'approve' | 'reject' | 'suspend' | 'reactivate';

// ── Style maps ────────────────────────────────────────────────────────────────

const STATUS_STYLES: Record<string, string> = {
  pending:   'bg-amber-50 text-amber-700',
  active:    'bg-green-50 text-green-700',
  suspended: 'bg-red-50 text-red-600',
};
const STATUS_DOT: Record<string, string> = {
  pending:   'bg-amber-400',
  active:    'bg-green-400',
  suspended: 'bg-red-400',
};
const AVAIL_STYLES: Record<string, string> = {
  available:   'bg-green-50 text-green-700',
  on_delivery: 'bg-blue-50 text-blue-700',
  offline:     'bg-gray-100 text-gray-500',
};
const AVAIL_DOT: Record<string, string> = {
  available:   'bg-green-400',
  on_delivery: 'bg-blue-400',
  offline:     'bg-gray-300',
};

// ── Shared small components ───────────────────────────────────────────────────

function StatusBadge({ status }: { status: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${STATUS_STYLES[status] ?? 'bg-gray-100 text-gray-600'}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[status] ?? 'bg-gray-400'}`} />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
}

function AvailBadge({ avail }: { avail: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${AVAIL_STYLES[avail] ?? 'bg-gray-100 text-gray-500'}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${AVAIL_DOT[avail] ?? 'bg-gray-300'}`} />
      {avail.replaceAll('_', ' ')}
    </span>
  );
}

function StarRating({ value }: { value: string | null }) {
  if (!value) return <span className="text-gray-300 text-sm">—</span>;
  return (
    <div className="flex items-center gap-1">
      <svg className="w-3.5 h-3.5 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
      </svg>
      <span className="text-gray-700 text-sm font-medium">{parseFloat(value).toFixed(1)}</span>
    </div>
  );
}

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1, 2, 3, 4, 5].map((i) => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-40 bg-gray-200 rounded" />
          <div className="h-4 w-24 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

// ── Suspend / Reject confirmation modal ───────────────────────────────────────

function ConfirmModal({
  title,
  subtitle,
  placeholder,
  confirmLabel,
  confirmClass,
  requireReason,
  onConfirm,
  onCancel,
}: {
  title: string;
  subtitle: string;
  placeholder: string;
  confirmLabel: string;
  confirmClass: string;
  requireReason: boolean;
  onConfirm: (reason: string) => void;
  onCancel: () => void;
}) {
  const [reason, setReason] = useState('');
  const canConfirm = !requireReason || reason.trim().length > 0;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md mx-4 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-1">{title}</h3>
        <p className="text-sm text-gray-500 mb-4">{subtitle}</p>
        <textarea
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-gray-300"
          rows={3}
          placeholder={placeholder}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        {requireReason && !reason.trim() && (
          <p className="text-xs text-red-500 mt-1">A reason is required.</p>
        )}
        <div className="flex gap-2 mt-4 justify-end">
          <button onClick={onCancel}
            className="px-4 py-2 text-sm text-gray-600 hover:bg-gray-100 rounded-xl transition-colors">
            Cancel
          </button>
          <button
            onClick={() => onConfirm(reason.trim())}
            disabled={!canConfirm}
            className={`px-4 py-2 text-sm text-white rounded-xl transition-colors font-medium disabled:opacity-40 ${confirmClass}`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Detail drawer ─────────────────────────────────────────────────────────────

function DetailDrawer({
  riderId,
  onClose,
  onAction,
  acting,
}: {
  riderId: string;
  onClose: () => void;
  onAction: (id: string, action: RiderAction, reason?: string) => void;
  acting: boolean;
}) {
  const [rider, setRider]   = useState<RiderDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState(false);

  useEffect(() => {
    setLoading(true);
    setError(false);
    api.get(`/admin/riders/${riderId}`)
      .then((r) => setRider(r.data.data as RiderDetail))
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, [riderId]);

  const avail = rider?.availability ?? 'offline';

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-lg bg-white shadow-2xl flex flex-col h-full overflow-hidden">

        {/* Header */}
        <div className="flex items-start justify-between px-6 pt-6 pb-4 border-b border-gray-100 shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-purple-100 flex items-center justify-center text-purple-600 font-bold text-xl shrink-0">
              {((rider?.display_name || rider?.email) ?? '?')[0].toUpperCase()}
            </div>
            <div>
              <h2 className="font-semibold text-gray-900 text-lg leading-tight">
                {rider?.display_name || <span className="text-gray-400 italic">No name</span>}
              </h2>
              {rider && (
                <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                  <StatusBadge status={rider.status} />
                  <AvailBadge avail={avail} />
                </div>
              )}
            </div>
          </div>
          <button onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-lg hover:bg-gray-100">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {loading && (
            <div className="space-y-3 animate-pulse">
              {[1,2,3,4].map((i) => <div key={i} className="h-12 bg-gray-100 rounded-xl" />)}
            </div>
          )}
          {error && (
            <div className="text-center py-16 text-gray-400">
              <div className="text-4xl mb-2">⚠</div>
              <p className="text-sm">Failed to load rider details</p>
            </div>
          )}
          {rider && !loading && (
            <div className="space-y-6">

              {/* Suspension reason banner */}
              {rider.status === 'suspended' && rider.suspension_reason && (
                <div className="bg-red-50 border border-red-200 rounded-xl p-4">
                  <p className="text-xs font-semibold text-red-600 mb-1">Suspension Reason</p>
                  <p className="text-sm text-red-700">{rider.suspension_reason}</p>
                </div>
              )}

              {/* Stats row */}
              <div className="grid grid-cols-3 gap-3">
                <div className="bg-gray-50 rounded-xl p-3 text-center">
                  <p className="text-xl font-bold text-gray-900">{rider.total_deliveries}</p>
                  <p className="text-xs text-gray-500 mt-0.5">Total Deliveries</p>
                </div>
                <div className="bg-gray-50 rounded-xl p-3 text-center">
                  <p className="text-xl font-bold text-gray-900">
                    {rider.average_rating ? parseFloat(rider.average_rating).toFixed(1) : '—'}
                  </p>
                  <p className="text-xs text-gray-500 mt-0.5">Avg Rating</p>
                </div>
                <div className="bg-gray-50 rounded-xl p-3 text-center">
                  <p className="text-xl font-bold text-gray-900">{rider.this_week_deliveries ?? 0}</p>
                  <p className="text-xs text-gray-500 mt-0.5">This Week</p>
                </div>
              </div>

              {/* Contact & account info */}
              {[
                { label: 'Email',       value: rider.email },
                { label: 'Phone',       value: rider.phone ?? '—' },
                { label: 'Joined',      value: new Date(rider.created_at).toLocaleDateString() },
                { label: 'Last seen',   value: rider.last_seen ? new Date(rider.last_seen).toLocaleString() : 'Never' },
              ].map((f) => (
                <div key={f.label} className="flex gap-3">
                  <span className="w-20 text-xs text-gray-400 shrink-0 pt-0.5">{f.label}</span>
                  <span className="text-sm text-gray-800 break-all">{f.value}</span>
                </div>
              ))}

              {/* Restaurant assignment */}
              <div className="border border-gray-100 rounded-xl p-4">
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Restaurant Assignment</p>
                {rider.restaurant_name ? (
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-lg bg-orange-50 flex items-center justify-center text-orange-500 font-bold text-sm shrink-0">
                      {rider.restaurant_name[0].toUpperCase()}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-gray-800">{rider.restaurant_name}</p>
                      <p className="text-xs text-green-600 font-medium">Active assignment</p>
                    </div>
                  </div>
                ) : (
                  <div>
                    <p className="text-sm text-gray-400 italic">No restaurant assigned</p>
                    {/* Show invitation status if there is one */}
                    {rider.invitation_status && (
                      <div className="mt-2 flex items-center gap-2">
                        <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium ${
                          rider.invitation_status === 'pending'  ? 'bg-amber-50 text-amber-700' :
                          rider.invitation_status === 'accepted' ? 'bg-green-50 text-green-700' :
                          'bg-gray-100 text-gray-500'
                        }`}>
                          {rider.invitation_status === 'pending'  && '⏳ '}
                          {rider.invitation_status === 'accepted' && '✓ '}
                          {rider.invitation_status === 'declined' && '✕ '}
                          Invitation {rider.invitation_status}
                        </span>
                        {rider.invited_by && (
                          <span className="text-xs text-gray-400">from {rider.invited_by}</span>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>

              {/* Recent deliveries */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Recent Deliveries</p>
                {!rider.recent_deliveries || rider.recent_deliveries.length === 0 ? (
                  <div className="text-center py-8 text-gray-300">
                    <div className="text-3xl mb-2">🛵</div>
                    <p className="text-sm text-gray-400">No deliveries yet</p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {rider.recent_deliveries.map((d) => (
                      <div key={d.id}
                        className="flex items-center justify-between p-3 rounded-xl border border-gray-100 hover:bg-gray-50 transition-colors">
                        <div className="min-w-0">
                          <p className="text-xs text-gray-400 font-mono">{d.id.slice(0, 8)}…</p>
                          <p className="text-sm font-medium text-gray-800 mt-0.5 truncate">
                            {d.restaurant_name ?? 'Unknown restaurant'}
                          </p>
                          {d.customer_name && (
                            <p className="text-xs text-gray-400">→ {d.customer_name}</p>
                          )}
                        </div>
                        <div className="text-right shrink-0 ml-3">
                          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                            d.status === 'delivered'  ? 'bg-green-50 text-green-700' :
                            d.status === 'cancelled'  ? 'bg-red-50 text-red-600'    :
                            'bg-gray-100 text-gray-600'
                          }`}>
                            {d.status}
                          </span>
                          <p className="text-xs text-gray-900 font-semibold mt-1">ETB {Number(d.total).toLocaleString()}</p>
                          <p className="text-xs text-gray-400">{new Date(d.created_at).toLocaleDateString()}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Action footer — shown only after rider data is loaded */}
        {rider && (
          <div className="shrink-0 border-t border-gray-100 px-6 py-4 flex gap-2 flex-wrap">
            {/* Pending riders: approve or reject (similar to restaurant flow) */}
            {rider.status === 'pending' && (
              <>
                <button onClick={() => onAction(rider.id, 'approve')} disabled={acting}
                  className="flex-1 text-sm bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-4 py-2.5 rounded-xl transition-colors font-medium">
                  ✓ Approve Rider
                </button>
                <button onClick={() => onAction(rider.id, 'reject')} disabled={acting}
                  className="flex-1 text-sm bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-4 py-2.5 rounded-xl transition-colors font-medium">
                  ✕ Reject
                </button>
              </>
            )}
            {rider.status === 'active' && (
              <button onClick={() => onAction(rider.id, 'suspend')} disabled={acting}
                className="flex-1 text-sm bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-4 py-2.5 rounded-xl transition-colors font-medium">
                Suspend Rider
              </button>
            )}
            {rider.status === 'suspended' && (
              <button onClick={() => onAction(rider.id, 'reactivate')} disabled={acting}
                className="flex-1 text-sm bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-4 py-2.5 rounded-xl transition-colors font-medium">
                Reactivate Rider
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function RidersPage() {
  const [riders, setRiders]           = useState<Rider[]>([]);
  const [pagination, setPagination]   = useState<Pagination | null>(null);
  const [loading, setLoading]         = useState(true);
  const [page, setPage]               = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch]           = useState('');
  const [statusFilter, setStatusFilter]     = useState('');
  const [availFilter, setAvailFilter]       = useState('');
  const [selectedId, setSelectedId]         = useState<string | null>(null);
  const [acting, setActing]                 = useState<string | null>(null);

  // Pending modal state
  const [pendingModal, setPendingModal] = useState<{
    riderId: string;
    action: RiderAction;
  } | null>(null);

  const searchTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback((p: number, q?: string, status?: string, avail?: string) => {
    setLoading(true);
    const params: Record<string, string | number> = { page: p, limit: 20 };
    if (q)      params.search       = q;
    if (status) params.status       = status;
    if (avail)  params.availability = avail;
    api.get('/admin/riders', { params })
      .then((res) => {
        const data = res.data.data;
        setRiders(data.riders as Rider[]);
        setPagination(data.pagination as Pagination);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  // Initial load
  useEffect(() => { load(1); }, [load]);

  // Debounced search
  useEffect(() => {
    if (searchTimeout.current) clearTimeout(searchTimeout.current);
    searchTimeout.current = setTimeout(() => {
      setSearch(searchInput);
      setPage(1);
      load(1, searchInput || undefined, statusFilter || undefined, availFilter || undefined);
    }, 350);
    return () => { if (searchTimeout.current) clearTimeout(searchTimeout.current); };
  }, [searchInput, statusFilter, availFilter, load]);

  const goToPage = (p: number) => {
    setPage(p);
    load(p, search || undefined, statusFilter || undefined, availFilter || undefined);
  };

  const doAction = async (id: string, action: RiderAction, reason?: string) => {
    // Actions requiring a reason open a confirmation modal first
    if ((action === 'suspend' || action === 'reject') && reason === undefined) {
      setPendingModal({ riderId: id, action });
      return;
    }
    setActing(id);
    try {
      const endpoints: Record<RiderAction, string> = {
        approve:    `/admin/users/${id}/approve`,
        reject:     `/admin/users/${id}/reject`,
        suspend:    `/admin/users/${id}/suspend`,
        reactivate: `/admin/users/${id}/reactivate`,
      };
      const methods: Record<RiderAction, 'post' | 'put'> = {
        approve:    'put',
        reject:     'put',
        suspend:    'put',
        reactivate: 'put',
      };
      const body = (action === 'suspend' || action === 'reject') && reason
        ? { reason }
        : undefined;
      await api[methods[action]](endpoints[action], body);
      // Reload the list
      load(page, search || undefined, statusFilter || undefined, availFilter || undefined);
      // Close drawer if the acted-on rider was selected
      if (selectedId === id) setSelectedId(null);
    } catch (e) {
      console.error(e);
    } finally {
      setActing(null);
    }
  };

  const pendingCount   = riders.filter((r) => r.status === 'pending').length;
  const activeCount    = riders.filter((r) => r.status === 'active').length;
  const suspendedCount = riders.filter((r) => r.status === 'suspended').length;

  return (
    <>
      {/* Suspend / Reject confirmation modal */}
      {pendingModal && (
        <ConfirmModal
          title={pendingModal.action === 'suspend' ? 'Suspend Rider' : 'Reject Rider'}
          subtitle={
            pendingModal.action === 'suspend'
              ? 'The rider will be immediately taken offline and cannot accept new deliveries.'
              : 'The rider\'s account will be rejected. They will need to re-register.'
          }
          placeholder={
            pendingModal.action === 'suspend'
              ? 'Reason for suspension (required)...'
              : 'Reason for rejection (required)...'
          }
          confirmLabel={pendingModal.action === 'suspend' ? 'Confirm Suspension' : 'Confirm Rejection'}
          confirmClass={pendingModal.action === 'suspend' ? 'bg-red-500 hover:bg-red-600' : 'bg-red-500 hover:bg-red-600'}
          requireReason={true}
          onConfirm={(reason) => {
            const { riderId, action } = pendingModal;
            setPendingModal(null);
            void doAction(riderId, action, reason);
          }}
          onCancel={() => setPendingModal(null)}
        />
      )}

      {/* Detail drawer */}
      {selectedId && (
        <DetailDrawer
          riderId={selectedId}
          acting={acting === selectedId}
          onClose={() => setSelectedId(null)}
          onAction={(id, action, reason) => {
            // If action needs a reason, modal will open — don't close drawer yet
            if ((action === 'suspend' || action === 'reject') && reason === undefined) {
              void doAction(id, action);
            } else {
              void doAction(id, action, reason);
            }
          }}
        />
      )}

      <div className="space-y-5">

        {/* Header */}
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Riders</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              {pagination && `${pagination.total.toLocaleString()} total`}
              {activeCount    > 0 && <span className="text-green-600 font-medium"> · {activeCount} active</span>}
              {pendingCount   > 0 && <span className="text-amber-600 font-medium"> · {pendingCount} pending</span>}
              {suspendedCount > 0 && <span className="text-red-500 font-medium"> · {suspendedCount} suspended</span>}
            </p>
          </div>
          <button
            onClick={() => load(page, search || undefined, statusFilter || undefined, availFilter || undefined)}
            className="flex items-center gap-2 border border-gray-200 rounded-xl px-4 py-2 text-sm hover:bg-gray-50 transition-colors"
          >
            <svg className="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
        </div>

        {/* Pending approval alert */}
        {pendingCount > 0 && (
          <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 flex items-center gap-3">
            <svg className="w-5 h-5 text-amber-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p className="text-sm text-amber-800 flex-1">
              <span className="font-semibold">{pendingCount} rider{pendingCount !== 1 ? 's' : ''}</span> awaiting approval.
            </p>
            <button
              onClick={() => { setStatusFilter('pending'); setPage(1); load(1, search || undefined, 'pending', availFilter || undefined); }}
              className="text-sm font-semibold text-amber-700 hover:underline whitespace-nowrap"
            >
              Show pending →
            </button>
          </div>
        )}

        {/* Search + filters */}
        <div className="flex gap-2 flex-wrap">
          {/* Search */}
          <div className="relative flex-1 min-w-[180px] max-w-xs">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-4.35-4.35M17 11A6 6 0 111 11a6 6 0 0116 0z" />
            </svg>
            <input
              type="text"
              placeholder="Search name, email or phone…"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
            />
          </div>

          {/* Status filter */}
          <select
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); setPage(1); load(1, search || undefined, e.target.value || undefined, availFilter || undefined); }}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
          >
            <option value="">All Statuses</option>
            {['pending','active','suspended'].map((s) => (
              <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
            ))}
          </select>

          {/* Availability filter */}
          <select
            value={availFilter}
            onChange={(e) => { setAvailFilter(e.target.value); setPage(1); load(1, search || undefined, statusFilter || undefined, e.target.value || undefined); }}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
          >
            <option value="">All Availability</option>
            {['available','on_delivery','offline'].map((a) => (
              <option key={a} value={a}>{a.replaceAll('_', ' ').replace(/^\w/, (c) => c.toUpperCase())}</option>
            ))}
          </select>

          {/* Clear filters */}
          {(searchInput || statusFilter || availFilter) && (
            <button
              onClick={() => {
                setSearchInput(''); setSearch('');
                setStatusFilter(''); setAvailFilter('');
                setPage(1); load(1);
              }}
              className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700 border border-gray-200 rounded-xl hover:bg-gray-50 transition-colors"
            >
              ✕ Clear
            </button>
          )}
        </div>

        {/* Table */}
        {loading ? <TableSkeleton /> : (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  {['Rider', 'Status', 'Availability', 'Restaurant', 'Deliveries', 'Rating', 'Joined', 'Actions'].map((h) => (
                    <th key={h} className="text-left px-5 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {riders.length === 0 && (
                  <tr>
                    <td colSpan={8} className="text-center py-16">
                      <div className="text-gray-300 text-4xl mb-3">🛵</div>
                      <p className="text-gray-400 text-sm">No riders found</p>
                    </td>
                  </tr>
                )}
                {riders.map((r) => {
                  const avail = r.availability ?? 'offline';
                  return (
                    <tr
                      key={r.id}
                      className="hover:bg-gray-50/50 transition-colors cursor-pointer"
                      onClick={() => setSelectedId(r.id)}
                    >
                      {/* Rider */}
                      <td className="px-5 py-4">
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-purple-100 flex items-center justify-center text-purple-600 font-semibold text-sm shrink-0">
                            {(r.display_name || r.email)[0].toUpperCase()}
                          </div>
                          <div>
                            <div className="font-medium text-gray-800">{r.display_name || <span className="text-gray-400 italic">No name</span>}</div>
                            <div className="text-gray-400 text-xs">{r.email}</div>
                            {r.phone && <div className="text-gray-400 text-xs">{r.phone}</div>}
                          </div>
                        </div>
                      </td>

                      {/* Status */}
                      <td className="px-5 py-4">
                        <StatusBadge status={r.status} />
                      </td>

                      {/* Availability */}
                      <td className="px-5 py-4">
                        <AvailBadge avail={avail} />
                        {r.last_seen && (
                          <div className="text-gray-400 text-xs mt-0.5">
                            {new Date(r.last_seen).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </div>
                        )}
                      </td>

                      {/* Restaurant */}
                      <td className="px-5 py-4">
                        {r.restaurant_name
                          ? <span className="text-gray-700 text-sm">{r.restaurant_name}</span>
                          : (
                            <div>
                              <span className="text-gray-300 italic text-sm">Unassigned</span>
                              {r.invitation_status === 'pending' && (
                                <div className="text-xs text-amber-600 font-medium mt-0.5">⏳ Invite pending</div>
                              )}
                            </div>
                          )
                        }
                      </td>

                      {/* Deliveries */}
                      <td className="px-5 py-4">
                        <span className="inline-flex items-center gap-1.5 bg-green-50 text-green-700 text-xs font-semibold px-2.5 py-1 rounded-full">
                          {r.total_deliveries}
                        </span>
                      </td>

                      {/* Rating */}
                      <td className="px-5 py-4">
                        <StarRating value={r.average_rating} />
                      </td>

                      {/* Joined */}
                      <td className="px-5 py-4 text-gray-400 text-xs whitespace-nowrap">
                        {new Date(r.created_at).toLocaleDateString()}
                      </td>

                      {/* Actions */}
                      <td className="px-5 py-4" onClick={(e) => e.stopPropagation()}>
                        <div className="flex gap-1.5 flex-wrap">
                          {r.status === 'pending' && (
                            <>
                              <button
                                onClick={() => void doAction(r.id, 'approve')}
                                disabled={acting === r.id}
                                className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                              >
                                Approve
                              </button>
                              <button
                                onClick={() => void doAction(r.id, 'reject')}
                                disabled={acting === r.id}
                                className="text-xs bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                              >
                                Reject
                              </button>
                            </>
                          )}
                          {r.status === 'active' && (
                            <button
                              onClick={() => void doAction(r.id, 'suspend')}
                              disabled={acting === r.id}
                              className="text-xs bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                            >
                              Suspend
                            </button>
                          )}
                          {r.status === 'suspended' && (
                            <button
                              onClick={() => void doAction(r.id, 'reactivate')}
                              disabled={acting === r.id}
                              className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                            >
                              Reactivate
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
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
                          p === pagination.page
                            ? 'bg-orange-500 text-white border-orange-500'
                            : 'border-gray-200 hover:bg-gray-50'
                        }`}>
                        {p}
                      </button>
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
