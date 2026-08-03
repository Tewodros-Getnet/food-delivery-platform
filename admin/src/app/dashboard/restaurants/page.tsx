'use client';
import { useEffect, useState, useCallback } from 'react';
import { api } from '@/lib/api';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Restaurant {
  id: string;
  name: string;
  description: string | null;
  address: string;
  category: string | null;
  status: string;
  average_rating: number;
  is_open: boolean;
  logo_url: string | null;
  cover_image_url: string | null;
  latitude: number;
  longitude: number;
  operating_hours: Record<string, { open: string; close: string }> | null;
  rejection_reason: string | null;
  owner_email: string;
  owner_name: string | null;
  owner_phone: string | null;
  menu_count: string;
  active_orders_count: string;
  total_orders: string;
  created_at: string;
  updated_at: string;
}

interface MenuItem {
  id: string;
  name: string;
  description: string | null;
  price: number;
  category: string | null;
  is_available: boolean;
  image_url: string | null;
}

interface ActiveOrder {
  id: string;
  status: string;
  total: number;
  created_at: string;
  customer_email: string;
  customer_name: string | null;
  rider_name: string | null;
  items_summary: string | null;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const STATUS_STYLES: Record<string, string> = {
  pending:   'bg-amber-50 text-amber-700',
  approved:  'bg-green-50 text-green-700',
  rejected:  'bg-red-50 text-red-600',
  suspended: 'bg-gray-100 text-gray-600',
};
const STATUS_DOT: Record<string, string> = {
  pending:   'bg-amber-400',
  approved:  'bg-green-400',
  rejected:  'bg-red-400',
  suspended: 'bg-gray-400',
};
const ORDER_STATUS_STYLES: Record<string, string> = {
  pending:           'bg-gray-100 text-gray-600',
  confirmed:         'bg-blue-50 text-blue-700',
  preparing:         'bg-amber-50 text-amber-700',
  ready_for_pickup:  'bg-purple-50 text-purple-700',
  rider_assigned:    'bg-indigo-50 text-indigo-700',
  out_for_delivery:  'bg-orange-50 text-orange-700',
  delivered:         'bg-green-50 text-green-700',
  cancelled:         'bg-red-50 text-red-600',
};

// ── Small helpers ─────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${STATUS_STYLES[status] ?? 'bg-gray-100 text-gray-600'}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[status] ?? 'bg-gray-400'}`} />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
}

function StarRating({ value }: { value: number }) {
  return (
    <div className="flex items-center gap-1">
      <svg className="w-3.5 h-3.5 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
      </svg>
      <span className="text-gray-700 text-sm font-medium">{Number(value).toFixed(1)}</span>
    </div>
  );
}

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1,2,3,4].map((i) => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-32 bg-gray-200 rounded" />
          <div className="h-4 w-40 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

// ── Rejection reason modal ────────────────────────────────────────────────────

function RejectModal({ onConfirm, onCancel }: { onConfirm: (reason: string) => void; onCancel: () => void }) {
  const [reason, setReason] = useState('');
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md mx-4 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-1">Reject Restaurant</h3>
        <p className="text-sm text-gray-500 mb-4">Provide a reason so the owner knows what to fix.</p>
        <textarea
          className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-red-400"
          rows={4}
          placeholder="e.g. Missing business licence, incomplete menu, invalid address..."
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        <div className="flex gap-2 mt-4 justify-end">
          <button onClick={onCancel} className="px-4 py-2 text-sm text-gray-600 hover:bg-gray-100 rounded-xl transition-colors">Cancel</button>
          <button
            onClick={() => onConfirm(reason.trim())}
            disabled={!reason.trim()}
            className="px-4 py-2 text-sm bg-red-500 hover:bg-red-600 disabled:opacity-40 text-white rounded-xl transition-colors font-medium"
          >
            Confirm Rejection
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Detail drawer ─────────────────────────────────────────────────────────────

type DrawerTab = 'info' | 'menu' | 'orders';

function DetailDrawer({
  restaurant,
  onClose,
  onAction,
}: {
  restaurant: Restaurant;
  onClose: () => void;
  onAction: (id: string, action: 'approve' | 'reject' | 'suspend' | 'unsuspend') => void;
}) {
  const [tab, setTab] = useState<DrawerTab>('info');
  const [menu, setMenu] = useState<MenuItem[]>([]);
  const [orders, setOrders] = useState<ActiveOrder[]>([]);
  const [loadingMenu, setLoadingMenu] = useState(false);
  const [loadingOrders, setLoadingOrders] = useState(false);

  useEffect(() => {
    if (tab === 'menu' && menu.length === 0) {
      setLoadingMenu(true);
      api.get(`/admin/restaurants/${restaurant.id}/menu`)
        .then((r) => setMenu(r.data.data as MenuItem[]))
        .catch(console.error)
        .finally(() => setLoadingMenu(false));
    }
    if (tab === 'orders' && orders.length === 0) {
      setLoadingOrders(true);
      api.get(`/admin/restaurants/${restaurant.id}/active-orders`)
        .then((r) => setOrders(r.data.data as ActiveOrder[]))
        .catch(console.error)
        .finally(() => setLoadingOrders(false));
    }
  }, [tab, restaurant.id, menu.length, orders.length]);

  const tabs: { key: DrawerTab; label: string; count?: number }[] = [
    { key: 'info',   label: 'Details' },
    { key: 'menu',   label: 'Menu',   count: parseInt(restaurant.menu_count) },
    { key: 'orders', label: 'Active Orders', count: parseInt(restaurant.active_orders_count) },
  ];

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-xl bg-white shadow-2xl flex flex-col h-full overflow-hidden">
        {/* Drawer header */}
        <div className="flex items-start justify-between px-6 pt-6 pb-4 border-b border-gray-100 shrink-0">
          <div className="flex items-center gap-3">
            {restaurant.logo_url ? (
              <img src={restaurant.logo_url} alt={restaurant.name} className="w-12 h-12 rounded-xl object-cover" />
            ) : (
              <div className="w-12 h-12 rounded-xl bg-orange-50 flex items-center justify-center text-orange-500 font-bold text-lg">
                {restaurant.name[0].toUpperCase()}
              </div>
            )}
            <div>
              <h2 className="font-semibold text-gray-900 text-lg leading-tight">{restaurant.name}</h2>
              <div className="flex items-center gap-2 mt-0.5">
                <StatusBadge status={restaurant.status} />
                {restaurant.is_open && (
                  <span className="text-xs text-green-600 font-medium">● Open now</span>
                )}
              </div>
            </div>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-lg hover:bg-gray-100">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-gray-100 shrink-0 px-6">
          {tabs.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`flex items-center gap-1.5 px-1 py-3 mr-6 text-sm font-medium border-b-2 transition-colors ${
                tab === t.key
                  ? 'border-orange-500 text-orange-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {t.label}
              {t.count !== undefined && t.count > 0 && (
                <span className={`text-xs rounded-full px-1.5 py-0.5 font-semibold ${tab === t.key ? 'bg-orange-100 text-orange-600' : 'bg-gray-100 text-gray-500'}`}>
                  {t.count}
                </span>
              )}
            </button>
          ))}
        </div>

        {/* Tab content */}
        <div className="flex-1 overflow-y-auto p-6">

          {/* ── INFO TAB ── */}
          {tab === 'info' && (
            <div className="space-y-5">
              {/* Cover image */}
              {restaurant.cover_image_url && (
                <img src={restaurant.cover_image_url} alt="cover" className="w-full h-36 object-cover rounded-xl" />
              )}

              {/* Stats row */}
              <div className="grid grid-cols-3 gap-3">
                {[
                  { label: 'Rating', value: `${Number(restaurant.average_rating).toFixed(1)} ★` },
                  { label: 'Menu Items', value: restaurant.menu_count },
                  { label: 'Active Orders', value: restaurant.active_orders_count },
                ].map((s) => (
                  <div key={s.label} className="bg-gray-50 rounded-xl p-3 text-center">
                    <p className="text-lg font-bold text-gray-900">{s.value}</p>
                    <p className="text-xs text-gray-500 mt-0.5">{s.label}</p>
                  </div>
                ))}
              </div>

              {/* Info fields */}
              {[
                { label: 'Owner', value: `${restaurant.owner_name ?? '—'} · ${restaurant.owner_email}` },
                { label: 'Phone', value: restaurant.owner_phone ?? '—' },
                { label: 'Address', value: restaurant.address },
                { label: 'Category', value: restaurant.category ?? '—' },
                { label: 'Joined', value: new Date(restaurant.created_at).toLocaleDateString() },
              ].map((f) => (
                <div key={f.label} className="flex gap-3">
                  <span className="w-24 text-xs text-gray-400 shrink-0 pt-0.5">{f.label}</span>
                  <span className="text-sm text-gray-800 break-all">{f.value}</span>
                </div>
              ))}

              {restaurant.description && (
                <div className="flex gap-3">
                  <span className="w-24 text-xs text-gray-400 shrink-0 pt-0.5">Description</span>
                  <span className="text-sm text-gray-600">{restaurant.description}</span>
                </div>
              )}

              {/* Rejection reason */}
              {restaurant.status === 'rejected' && restaurant.rejection_reason && (
                <div className="bg-red-50 border border-red-100 rounded-xl p-4">
                  <p className="text-xs font-semibold text-red-600 mb-1">Rejection Reason</p>
                  <p className="text-sm text-red-700">{restaurant.rejection_reason}</p>
                </div>
              )}
            </div>
          )}

          {/* ── MENU TAB ── */}
          {tab === 'menu' && (
            <div>
              {loadingMenu ? (
                <div className="space-y-3">
                  {[1,2,3].map((i) => (
                    <div key={i} className="h-16 bg-gray-100 rounded-xl animate-pulse" />
                  ))}
                </div>
              ) : menu.length === 0 ? (
                <div className="text-center py-16 text-gray-400">
                  <div className="text-4xl mb-2">🍽️</div>
                  <p className="text-sm">No menu items yet</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {menu.map((item) => (
                    <div key={item.id} className="flex items-center gap-3 p-3 rounded-xl border border-gray-100 hover:bg-gray-50 transition-colors">
                      {item.image_url ? (
                        <img src={item.image_url} alt={item.name} className="w-12 h-12 rounded-lg object-cover shrink-0" />
                      ) : (
                        <div className="w-12 h-12 rounded-lg bg-orange-50 flex items-center justify-center text-orange-400 text-xl shrink-0">🍴</div>
                      )}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-medium text-gray-800 truncate">{item.name}</p>
                          {!item.is_available && (
                            <span className="text-xs bg-gray-100 text-gray-500 px-1.5 py-0.5 rounded-full shrink-0">Unavailable</span>
                          )}
                        </div>
                        {item.category && <p className="text-xs text-gray-400">{item.category}</p>}
                        {item.description && <p className="text-xs text-gray-500 truncate">{item.description}</p>}
                      </div>
                      <span className="text-sm font-semibold text-gray-900 shrink-0">
                        ETB {Number(item.price).toLocaleString()}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ── ACTIVE ORDERS TAB ── */}
          {tab === 'orders' && (
            <div>
              {loadingOrders ? (
                <div className="space-y-3">
                  {[1,2,3].map((i) => (
                    <div key={i} className="h-20 bg-gray-100 rounded-xl animate-pulse" />
                  ))}
                </div>
              ) : orders.length === 0 ? (
                <div className="text-center py-16 text-gray-400">
                  <div className="text-4xl mb-2">📦</div>
                  <p className="text-sm">No active orders right now</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {orders.map((o) => (
                    <div key={o.id} className="p-4 rounded-xl border border-gray-100 hover:bg-gray-50 transition-colors">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-xs text-gray-400 font-mono">{o.id.slice(0, 8)}…</p>
                          <p className="text-sm font-medium text-gray-800 mt-0.5">{o.customer_name ?? o.customer_email}</p>
                          {o.items_summary && <p className="text-xs text-gray-500 mt-0.5 truncate">{o.items_summary}</p>}
                          {o.rider_name && <p className="text-xs text-gray-400 mt-0.5">Rider: {o.rider_name}</p>}
                        </div>
                        <div className="text-right shrink-0">
                          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${ORDER_STATUS_STYLES[o.status] ?? 'bg-gray-100 text-gray-600'}`}>
                            {o.status.replace(/_/g, ' ')}
                          </span>
                          <p className="text-sm font-semibold text-gray-900 mt-1">ETB {Number(o.total).toLocaleString()}</p>
                          <p className="text-xs text-gray-400">{new Date(o.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Action footer */}
        <div className="shrink-0 border-t border-gray-100 px-6 py-4 flex gap-2 flex-wrap">
          {restaurant.status === 'pending' && (
            <>
              <button onClick={() => onAction(restaurant.id, 'approve')}
                className="flex-1 text-sm bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
                Approve
              </button>
              <button onClick={() => onAction(restaurant.id, 'reject')}
                className="flex-1 text-sm bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
                Reject
              </button>
            </>
          )}
          {restaurant.status === 'approved' && (
            <button onClick={() => onAction(restaurant.id, 'suspend')}
              className="flex-1 text-sm bg-gray-500 hover:bg-gray-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
              Suspend
            </button>
          )}
          {restaurant.status === 'suspended' && (
            <button onClick={() => onAction(restaurant.id, 'unsuspend')}
              className="flex-1 text-sm bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
              Reactivate
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function RestaurantsPage() {
  const [restaurants, setRestaurants] = useState<Restaurant[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [selected, setSelected] = useState<Restaurant | null>(null);
  const [rejectTarget, setRejectTarget] = useState<string | null>(null);
  const [acting, setActing] = useState<string | null>(null);

  const load = useCallback((status?: string, q?: string) => {
    setLoading(true);
    const params: Record<string, string> = {};
    if (status) params.status = status;
    if (q)      params.search = q;
    api.get('/admin/restaurants', { params })
      .then((res) => setRestaurants(res.data.data as Restaurant[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { load(); }, [load]);

  // Debounce search
  useEffect(() => {
    const t = setTimeout(() => {
      setSearch(searchInput);
      load(filter || undefined, searchInput || undefined);
    }, 350);
    return () => clearTimeout(t);
  }, [searchInput, filter, load]);

  const doAction = async (id: string, action: 'approve' | 'reject' | 'suspend' | 'unsuspend', reason?: string) => {
    if (action === 'reject' && reason === undefined) {
      setRejectTarget(id);
      return;
    }
    setActing(id);
    try {
      const endpoints: Record<string, string> = {
        approve:   `/restaurants/${id}/approve`,
        reject:    `/restaurants/${id}/reject`,
        suspend:   `/restaurants/${id}/suspend`,
        unsuspend: `/admin/restaurants/${id}/unsuspend`,
      };
      const methods: Record<string, 'post' | 'put'> = {
        approve: 'post', reject: 'post', suspend: 'put', unsuspend: 'put',
      };
      const body = action === 'reject' && reason ? { reason } : undefined;
      await api[methods[action]](endpoints[action], body);
      load(filter || undefined, search || undefined);
      // Refresh drawer if open
      if (selected?.id === id) {
        const res = await api.get(`/admin/restaurants/${id}`);
        setSelected(res.data.data as Restaurant);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setActing(null);
    }
  };

  const counts = {
    pending:  restaurants.filter((r) => r.status === 'pending').length,
    approved: restaurants.filter((r) => r.status === 'approved').length,
  };

  return (
    <>
      {rejectTarget && (
        <RejectModal
          onConfirm={(reason) => { setRejectTarget(null); void doAction(rejectTarget, 'reject', reason); }}
          onCancel={() => setRejectTarget(null)}
        />
      )}

      {selected && (
        <DetailDrawer
          restaurant={selected}
          onClose={() => setSelected(null)}
          onAction={(id, action) => { void doAction(id, action); }}
        />
      )}

      <div className="space-y-5">
        {/* Header */}
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Restaurants</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              {counts.pending > 0 && (
                <span className="text-amber-600 font-medium">{counts.pending} pending approval · </span>
              )}
              {counts.approved} active
            </p>
          </div>

          {/* Search + filter */}
          <div className="flex gap-2 flex-wrap">
            <div className="relative">
              <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-4.35-4.35M17 11A6 6 0 111 11a6 6 0 0116 0z" />
              </svg>
              <input
                type="text"
                placeholder="Search name or owner…"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                className="pl-9 pr-4 py-2 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white w-56"
              />
            </div>
            <select
              value={filter}
              onChange={(e) => { setFilter(e.target.value); load(e.target.value || undefined, search || undefined); }}
              className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
            >
              <option value="">All Statuses</option>
              {['pending','approved','rejected','suspended'].map((s) => (
                <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Table */}
        {loading ? <TableSkeleton /> : (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  {['Restaurant','Owner','Status','Menu · Orders','Rating','Actions'].map((h) => (
                    <th key={h} className="text-left px-5 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {restaurants.length === 0 && (
                  <tr>
                    <td colSpan={6} className="text-center py-16">
                      <div className="text-gray-300 text-4xl mb-3">🍽️</div>
                      <p className="text-gray-400 text-sm">No restaurants found</p>
                    </td>
                  </tr>
                )}
                {restaurants.map((r) => (
                  <tr
                    key={r.id}
                    className="hover:bg-gray-50/50 transition-colors cursor-pointer"
                    onClick={() => setSelected(r)}
                  >
                    <td className="px-5 py-4">
                      <div className="flex items-center gap-3">
                        {r.logo_url ? (
                          <img src={r.logo_url} alt={r.name} className="w-8 h-8 rounded-lg object-cover shrink-0" />
                        ) : (
                          <div className="w-8 h-8 rounded-lg bg-orange-50 flex items-center justify-center text-orange-500 font-bold text-sm shrink-0">
                            {r.name[0].toUpperCase()}
                          </div>
                        )}
                        <span className="font-medium text-gray-800">{r.name}</span>
                      </div>
                    </td>
                    <td className="px-5 py-4">
                      <p className="text-gray-600 text-xs">{r.owner_name ?? '—'}</p>
                      <p className="text-gray-400 text-xs">{r.owner_email}</p>
                    </td>
                    <td className="px-5 py-4"><StatusBadge status={r.status} /></td>
                    <td className="px-5 py-4 text-gray-600 text-xs">
                      <span>{r.menu_count} items</span>
                      {parseInt(r.active_orders_count) > 0 && (
                        <span className="ml-2 bg-orange-100 text-orange-600 px-1.5 py-0.5 rounded-full font-medium">
                          {r.active_orders_count} active
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-4"><StarRating value={r.average_rating} /></td>
                    <td className="px-5 py-4" onClick={(e) => e.stopPropagation()}>
                      <div className="flex gap-1.5">
                        {r.status === 'pending' && (
                          <>
                            <button onClick={() => void doAction(r.id, 'approve')} disabled={acting === r.id}
                              className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium">
                              Approve
                            </button>
                            <button onClick={() => void doAction(r.id, 'reject')} disabled={acting === r.id}
                              className="text-xs bg-red-500 hover:bg-red-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium">
                              Reject
                            </button>
                          </>
                        )}
                        {r.status === 'approved' && (
                          <button onClick={() => void doAction(r.id, 'suspend')} disabled={acting === r.id}
                            className="text-xs bg-gray-500 hover:bg-gray-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium">
                            Suspend
                          </button>
                        )}
                        {r.status === 'suspended' && (
                          <button onClick={() => void doAction(r.id, 'unsuspend')} disabled={acting === r.id}
                            className="text-xs bg-green-500 hover:bg-green-600 disabled:opacity-50 text-white px-3 py-1.5 rounded-lg transition-colors font-medium">
                            Reactivate
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
