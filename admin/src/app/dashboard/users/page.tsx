'use client';
import { useEffect, useState, useRef, useCallback } from 'react';
import { api } from '@/lib/api';

// ── Types ─────────────────────────────────────────────────────────────────────

interface User {
  id: string;
  email: string;
  role: string;
  display_name: string | null;
  phone: string | null;
  status: string;
  email_verified: boolean;
  profile_photo_url: string | null;
  created_at: string;
  updated_at: string;
  order_count: string;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const ROLE_STYLES: Record<string, string> = {
  customer:   'bg-blue-50 text-blue-700',
  restaurant: 'bg-orange-50 text-orange-700',
  rider:      'bg-purple-50 text-purple-700',
  admin:      'bg-gray-100 text-gray-700',
};

const ROLE_ACTIVITY_LABEL: Record<string, string> = {
  customer:   'orders placed',
  rider:      'deliveries done',
  restaurant: 'restaurants',
  admin:      '',
};

const ROLES = ['customer', 'restaurant', 'rider', 'admin'];

// ── Helpers ───────────────────────────────────────────────────────────────────

function initials(u: User) {
  return (u.display_name || u.email)[0].toUpperCase();
}

function avatarColor(role: string): string {
  return role === 'customer'   ? 'bg-blue-100 text-blue-600'
       : role === 'restaurant' ? 'bg-orange-100 text-orange-600'
       : role === 'rider'      ? 'bg-purple-100 text-purple-600'
       : 'bg-gray-100 text-gray-600';
}

function exportCSV(users: User[]) {
  const headers = ['ID', 'Email', 'Name', 'Phone', 'Role', 'Status', 'Verified', 'Activity', 'Joined'];
  const rows = users.map(u => [
    u.id,
    u.email,
    u.display_name ?? '',
    u.phone ?? '',
    u.role,
    u.status,
    u.email_verified ? 'Yes' : 'No',
    u.order_count !== '—' ? `${u.order_count} ${ROLE_ACTIVITY_LABEL[u.role] ?? ''}`.trim() : '—',
    new Date(u.created_at).toLocaleDateString(),
  ]);
  const csv = [headers, ...rows]
    .map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(','))
    .join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url;
  a.download = `users-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1, 2, 3, 4, 5].map(i => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-8 bg-gray-200 rounded-full" />
          <div className="h-4 w-44 bg-gray-200 rounded" />
          <div className="h-4 w-20 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

// ── Confirm modal ─────────────────────────────────────────────────────────────

function ConfirmModal({
  title, message, confirmLabel, danger, onConfirm, onCancel,
}: {
  title: string; message: string; confirmLabel: string;
  danger?: boolean; onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/40 backdrop-blur-sm px-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md p-6">
        <h3 className="text-base font-semibold text-gray-900 mb-2">{title}</h3>
        <p className="text-sm text-gray-500 mb-6">{message}</p>
        <div className="flex gap-3 justify-end">
          <button onClick={onCancel}
            className="px-4 py-2 text-sm rounded-xl border border-gray-200 hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button onClick={onConfirm}
            className={`px-4 py-2 text-sm rounded-xl text-white font-medium transition-colors ${
              danger ? 'bg-red-500 hover:bg-red-600' : 'bg-orange-500 hover:bg-orange-600'
            }`}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

function BulkBar({
  count,
  busy,
  onSuspend,
  onResendVerification,
  onDelete,
  onClear,
}: {
  count: number;
  busy: boolean;
  onSuspend: () => void;
  onResendVerification: () => void;
  onDelete: () => void;
  onClear: () => void;
}) {
  return (
    <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-30 flex items-center gap-3 bg-gray-900 text-white px-5 py-3.5 rounded-2xl shadow-2xl">
      <span className="text-sm font-semibold">
        {count} selected
      </span>
      <div className="w-px h-5 bg-white/20" />
      <button
        onClick={onSuspend}
        disabled={busy}
        className="text-sm text-red-300 hover:text-red-200 font-medium disabled:opacity-40 transition-colors"
      >
        Suspend
      </button>
      <button
        onClick={onResendVerification}
        disabled={busy}
        className="text-sm text-blue-300 hover:text-blue-200 font-medium disabled:opacity-40 transition-colors"
      >
        Resend verification
      </button>
      <button
        onClick={onDelete}
        disabled={busy}
        className="text-sm text-red-400 hover:text-red-300 font-medium disabled:opacity-40 transition-colors"
      >
        Delete
      </button>
      <div className="w-px h-5 bg-white/20" />
      <button onClick={onClear} className="text-sm text-gray-400 hover:text-white transition-colors">
        ✕ Clear
      </button>
      {busy && (
        <svg className="w-4 h-4 animate-spin text-white/60" fill="none" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
        </svg>
      )}
    </div>
  );
}

// ── User detail drawer ────────────────────────────────────────────────────────

function UserDrawer({
  user: initialUser,
  onClose,
  onAction,
}: {
  user: User;
  onClose: () => void;
  onAction: (id: string, type: string, payload?: string) => Promise<void>;
}) {
  const [user, setUser]       = useState(initialUser);
  const [busy, setBusy]       = useState<string | null>(null);
  const [toast, setToast]     = useState<{ msg: string; ok: boolean } | null>(null);
  const [newRole, setNewRole] = useState(user.role);
  const [confirm, setConfirm] = useState<null | {
    type: string; label: string; message: string; danger?: boolean;
  }>(null);

  // Keep local user in sync when parent re-selects the same row after a reload
  useEffect(() => { setUser(initialUser); setNewRole(initialUser.role); }, [initialUser.id]);

  const act = async (type: string, payload?: string) => {
    setBusy(type);
    setToast(null);
    try {
      await onAction(user.id, type, payload);
      const labels: Record<string, string> = {
        delete:                `${user.email} deleted`,
        role:                  `Role changed to ${payload}`,
        'force-logout':        'All sessions revoked',
        'resend-verification': 'Verification email sent',
        suspend:               'User suspended',
        reactivate:            'User reactivated',
      };
      setToast({ msg: labels[type] ?? 'Done', ok: true });
      if      (type === 'suspend')    setUser(u => ({ ...u, status: 'suspended' }));
      else if (type === 'reactivate') setUser(u => ({ ...u, status: 'active' }));
      else if (type === 'role')       setUser(u => ({ ...u, role: payload! }));
      else if (type === 'delete')     { setTimeout(onClose, 600); return; }
    } catch (e: unknown) {
      const msg = (e as { response?: { data?: { error?: string } } })?.response?.data?.error
        ?? 'Action failed';
      setToast({ msg: `Error: ${msg}`, ok: false });
    } finally {
      setBusy(null);
      setConfirm(null);
    }
  };

  const isSuspended = user.status === 'suspended';
  const btnBase = 'w-full text-left px-4 py-2.5 text-sm rounded-xl font-medium transition-colors flex items-center gap-2.5 disabled:opacity-40';

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={onClose} />

      {/* Drawer panel */}
      <div className="relative w-full max-w-md bg-white shadow-2xl flex flex-col h-full overflow-hidden">

        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4 border-b border-gray-100 shrink-0">
          <div className="flex items-center gap-3">
            {user.profile_photo_url ? (
              <img
                src={user.profile_photo_url}
                alt={user.display_name ?? user.email}
                className="w-12 h-12 rounded-full object-cover shrink-0"
              />
            ) : (
              <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-lg shrink-0 ${avatarColor(user.role)}`}>
                {initials(user)}
              </div>
            )}
            <div>
              <p className="font-semibold text-gray-900 text-sm leading-tight">
                {user.display_name || <span className="italic text-gray-400">No name</span>}
              </p>
              <p className="text-xs text-gray-400">{user.email}</p>
            </div>
          </div>
          <button onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors p-1 rounded-lg hover:bg-gray-100">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto">

          {/* Info grid */}
          <div className="px-6 py-4 grid grid-cols-2 gap-2.5">
            {([
              ['Role', (
                <span key="r" className={`px-2 py-0.5 rounded-full text-xs font-medium ${ROLE_STYLES[user.role] ?? 'bg-gray-100 text-gray-600'}`}>
                  {user.role}
                </span>
              )],
              ['Status', (
                <span key="s" className={`px-2 py-0.5 rounded-full text-xs font-medium ${isSuspended ? 'bg-red-50 text-red-600' : 'bg-green-50 text-green-700'}`}>
                  {isSuspended ? 'Suspended' : 'Active'}
                </span>
              )],
              ['Email', (
                <span key="v">
                  {user.email_verified
                    ? <span className="text-green-600 text-xs font-medium">✓ Verified</span>
                    : <span className="text-amber-500 text-xs font-medium">⚠ Unverified</span>}
                </span>
              )],
              ['Activity', (
                <span key="a" className="text-gray-700 text-xs">
                  {user.order_count === '—'
                    ? '—'
                    : `${user.order_count} ${ROLE_ACTIVITY_LABEL[user.role] ?? ''}`.trim()}
                </span>
              )],
              ['Phone', <span key="p" className="text-gray-700 text-xs">{user.phone || '—'}</span>],
              ['Joined', <span key="j" className="text-gray-700 text-xs">{new Date(user.created_at).toLocaleDateString()}</span>],
              ['Last updated', <span key="u" className="text-gray-700 text-xs">{new Date(user.updated_at).toLocaleDateString()}</span>],
              ['User ID', <span key="id" className="text-gray-400 text-xs font-mono truncate">{user.id.slice(0, 16)}…</span>],
            ] as [string, React.ReactNode][]).map(([label, val]) => (
              <div key={label} className="bg-gray-50 rounded-xl px-3 py-2.5">
                <p className="text-xs text-gray-400 mb-0.5">{label}</p>
                <div>{val}</div>
              </div>
            ))}
          </div>

          {/* Actions */}
          <div className="px-6 pb-6 space-y-2 border-t border-gray-100 pt-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Actions</p>

            {/* Suspend / Reactivate */}
            <button
              disabled={!!busy}
              onClick={() => setConfirm(
                isSuspended
                  ? { type: 'reactivate', label: 'Reactivate', message: `Reactivate ${user.email}? They will be able to sign in again.` }
                  : { type: 'suspend', label: 'Suspend', danger: true, message: `Suspend ${user.email}? All their active sessions will be revoked immediately.` }
              )}
              className={`${btnBase} ${isSuspended ? 'bg-green-50 text-green-700 hover:bg-green-100' : 'bg-red-50 text-red-600 hover:bg-red-100'}`}
            >
              <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d={isSuspended
                    ? 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
                    : 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636'} />
              </svg>
              {(busy === 'suspend' || busy === 'reactivate') ? 'Working…'
                : isSuspended ? 'Reactivate account' : 'Suspend account'}
            </button>

            {/* Force logout */}
            <button
              disabled={!!busy}
              onClick={() => setConfirm({
                type: 'force-logout', label: 'Force Logout',
                message: `Revoke all active sessions for ${user.email}? They will be signed out on every device.`,
              })}
              className={`${btnBase} bg-amber-50 text-amber-700 hover:bg-amber-100`}
            >
              <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
              {busy === 'force-logout' ? 'Working…' : 'Force logout (revoke all sessions)'}
            </button>

            {/* Resend verification — only when unverified */}
            {!user.email_verified && (
              <button
                disabled={!!busy}
                onClick={() => act('resend-verification')}
                className={`${btnBase} bg-blue-50 text-blue-700 hover:bg-blue-100`}
              >
                <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                {busy === 'resend-verification' ? 'Sending…' : 'Resend verification email'}
              </button>
            )}

            {/* Change role */}
            <div className="bg-gray-50 rounded-xl px-4 py-3">
              <p className="text-xs font-semibold text-gray-500 mb-2">Change role</p>
              <div className="flex gap-2">
                <select
                  value={newRole}
                  onChange={e => setNewRole(e.target.value)}
                  className="flex-1 border border-gray-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400"
                >
                  {ROLES.map(r => (
                    <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>
                  ))}
                </select>
                <button
                  disabled={!!busy || newRole === user.role}
                  onClick={() => setConfirm({
                    type: 'role', label: 'Change Role',
                    message: `Change ${user.email} from "${user.role}" to "${newRole}"? Existing sessions will be revoked because the role is embedded in the JWT.`,
                  })}
                  className="px-4 py-1.5 text-sm bg-orange-500 hover:bg-orange-600 disabled:opacity-40 text-white rounded-lg font-medium transition-colors"
                >
                  {busy === 'role' ? '…' : 'Apply'}
                </button>
              </div>
            </div>

            {/* Delete */}
            <button
              disabled={!!busy}
              onClick={() => setConfirm({
                type: 'delete', label: 'Delete User', danger: true,
                message: `Permanently delete ${user.email}? This removes their account, all orders, addresses, and sessions. This cannot be undone.`,
              })}
              className={`${btnBase} bg-red-50 text-red-600 hover:bg-red-100`}
            >
              <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              {busy === 'delete' ? 'Deleting…' : 'Delete account permanently'}
            </button>
          </div>

          {/* Toast */}
          {toast && (
            <div className={`mx-6 mb-6 px-4 py-3 rounded-xl text-sm font-medium ${toast.ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'}`}>
              {toast.msg}
            </div>
          )}
        </div>
      </div>

      {/* Confirm dialog sits on top */}
      {confirm && (
        <ConfirmModal
          title={confirm.label}
          message={confirm.message}
          confirmLabel={confirm.label}
          danger={confirm.danger}
          onConfirm={() => act(confirm.type, confirm.type === 'role' ? newRole : undefined)}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function UsersPage() {
  const [users, setUsers]           = useState<User[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [unverifiedCount, setUnverifiedCount] = useState(0);
  const [loading, setLoading]       = useState(true);
  const [page, setPage]             = useState(1);
  const [selected, setSelected]     = useState<User | null>(null);
  const [selected2, setSelected2]   = useState<Set<string>>(new Set()); // bulk selection
  const [bulkBusy, setBulkBusy]     = useState(false);
  const [bulkConfirm, setBulkConfirm] = useState<{
    type: 'suspend' | 'delete' | 'resend'; label: string; message: string; danger?: boolean;
  } | null>(null);

  // Filter state
  const [searchInput, setSearchInput] = useState('');
  const [roleFilter, setRoleFilter]   = useState('');
  const [statusFilter, setStatusFilter]   = useState('');
  const [verifiedFilter, setVerifiedFilter] = useState('');

  // Stable refs so the debounce callback always reads the latest values
  const filtersRef = useRef({ search: '', role: '', status: '', verified: '' });
  filtersRef.current = { search: searchInput, role: roleFilter, status: statusFilter, verified: verifiedFilter };

  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback((p: number, overrides?: Partial<typeof filtersRef.current>) => {
    const f = { ...filtersRef.current, ...overrides };
    setLoading(true);
    api.get('/admin/users', {
      params: {
        search:   f.search   || undefined,
        role:     f.role     || undefined,
        status:   f.status   || undefined,
        verified: f.verified || undefined,
        page: p,
        limit: 20,
      },
    })
      .then(res => {
        const d = res.data.data;
        setUsers(d.users ?? d);
        setPagination(d.pagination ?? null);
        if (typeof d.unverifiedCount === 'number') setUnverifiedCount(d.unverifiedCount);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  // Initial load
  useEffect(() => { load(1); }, [load]);

  // Debounced re-load when any filter changes
  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => { setPage(1); load(1); }, 320);
    return () => { if (debounceRef.current) clearTimeout(debounceRef.current); };
  }, [searchInput, roleFilter, statusFilter, verifiedFilter, load]);

  // ── Single-user action ────────────────────────────────────────────────────

  const handleAction = async (id: string, type: string, payload?: string) => {
    if (type === 'suspend')                  await api.put(`/admin/users/${id}/suspend`);
    else if (type === 'reactivate')          await api.put(`/admin/users/${id}/reactivate`);
    else if (type === 'force-logout')        await api.post(`/admin/users/${id}/force-logout`);
    else if (type === 'resend-verification') await api.post(`/admin/users/${id}/resend-verification`);
    else if (type === 'role')                await api.put(`/admin/users/${id}/role`, { role: payload });
    else if (type === 'delete')              await api.delete(`/admin/users/${id}`);

    if (type === 'delete') {
      setUsers(prev => prev.filter(u => u.id !== id));
      setSelected(null);
    } else {
      load(page);
    }
  };

  // ── Inline quick-action (row-level, no modal needed) ──────────────────────

  const quickToggle = async (u: User, e: React.MouseEvent) => {
    e.stopPropagation();
    const type = u.status === 'active' ? 'suspend' : 'reactivate';
    try {
      if (type === 'suspend') await api.put(`/admin/users/${u.id}/suspend`);
      else                    await api.put(`/admin/users/${u.id}/reactivate`);
      setUsers(prev =>
        prev.map(x => x.id === u.id ? { ...x, status: type === 'suspend' ? 'suspended' : 'active' } : x)
      );
      // Keep drawer in sync if open
      if (selected?.id === u.id) {
        setSelected(x => x ? { ...x, status: type === 'suspend' ? 'suspended' : 'active' } : x);
      }
    } catch { /* ignore — user can open drawer for full error */ }
  };

  // ── Bulk actions ──────────────────────────────────────────────────────────

  const toggleSelectAll = () => {
    if (selected2.size === users.length) {
      setSelected2(new Set());
    } else {
      setSelected2(new Set(users.map(u => u.id)));
    }
  };

  const toggleSelectOne = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setSelected2(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const executeBulk = async (type: 'suspend' | 'delete' | 'resend') => {
    setBulkBusy(true);
    const ids = Array.from(selected2);
    try {
      await Promise.all(ids.map(id => {
        if (type === 'suspend') return api.put(`/admin/users/${id}/suspend`);
        if (type === 'delete')  return api.delete(`/admin/users/${id}`);
        return api.post(`/admin/users/${id}/resend-verification`);
      }));
      setSelected2(new Set());
      if (type === 'delete') setUsers(prev => prev.filter(u => !ids.includes(u.id)));
      else                   load(page);
    } catch { /* partial failures handled silently */ }
    finally {
      setBulkBusy(false);
      setBulkConfirm(null);
    }
  };

  // ── Derived counts ────────────────────────────────────────────────────────

  const suspendedCount = users.filter(u => u.status === 'suspended').length;
  const allSelected    = users.length > 0 && selected2.size === users.length;
  const someSelected   = selected2.size > 0 && !allSelected;

  return (
    <>
      {/* ── Bulk confirm modal ─────────────────────────────────────────────── */}
      {bulkConfirm && (
        <ConfirmModal
          title={bulkConfirm.label}
          message={bulkConfirm.message}
          confirmLabel={bulkConfirm.label}
          danger={bulkConfirm.danger}
          onConfirm={() => void executeBulk(bulkConfirm.type)}
          onCancel={() => setBulkConfirm(null)}
        />
      )}

      {/* ── User drawer ────────────────────────────────────────────────────── */}
      {selected && (
        <UserDrawer
          user={selected}
          onClose={() => setSelected(null)}
          onAction={handleAction}
        />
      )}

      {/* ── Bulk action bar ────────────────────────────────────────────────── */}
      {selected2.size > 0 && (
        <BulkBar
          count={selected2.size}
          busy={bulkBusy}
          onSuspend={() => setBulkConfirm({
            type: 'suspend', label: 'Suspend Selected', danger: true,
            message: `Suspend ${selected2.size} user${selected2.size !== 1 ? 's' : ''}? Their sessions will be revoked immediately.`,
          })}
          onResendVerification={() => void executeBulk('resend')}
          onDelete={() => setBulkConfirm({
            type: 'delete', label: 'Delete Selected', danger: true,
            message: `Permanently delete ${selected2.size} user${selected2.size !== 1 ? 's' : ''}? This cannot be undone.`,
          })}
          onClear={() => setSelected2(new Set())}
        />
      )}

      <div className="space-y-5">

        {/* ── Header ──────────────────────────────────────────────────────── */}
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Users</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              {pagination ? `${pagination.total.toLocaleString()} total` : ''}
              {suspendedCount > 0 && (
                <span className="text-red-500 font-medium"> · {suspendedCount} suspended</span>
              )}
            </p>
          </div>

          {/* Export CSV */}
          <button
            onClick={() => exportCSV(users)}
            disabled={users.length === 0}
            className="flex items-center gap-2 border border-gray-200 rounded-xl px-4 py-2 text-sm hover:bg-gray-50 transition-colors disabled:opacity-40"
          >
            <svg className="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
            Export CSV
          </button>
        </div>

        {/* ── Unverified alert banner ──────────────────────────────────────── */}
        {unverifiedCount > 0 && (
          <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 flex items-center gap-3">
            <svg className="w-5 h-5 text-amber-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <p className="text-sm text-amber-800 flex-1">
              <span className="font-semibold">{unverifiedCount} account{unverifiedCount !== 1 ? 's' : ''}</span>{' '}
              have not verified their email address.
            </p>
            <button
              onClick={() => { setVerifiedFilter('false'); }}
              className="text-sm font-semibold text-amber-700 hover:underline whitespace-nowrap"
            >
              Show unverified →
            </button>
          </div>
        )}

        {/* ── Filters ─────────────────────────────────────────────────────── */}
        <div className="flex gap-2 flex-wrap">
          {/* Search — live debounced */}
          <div className="relative flex-1 min-w-[200px] max-w-xs">
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400"
              fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M21 21l-4.35-4.35M17 11A6 6 0 111 11a6 6 0 0116 0z" />
            </svg>
            <input
              value={searchInput}
              onChange={e => setSearchInput(e.target.value)}
              placeholder="Search email, name, phone…"
              className="w-full pl-9 pr-4 py-2 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
            />
          </div>

          {/* Role */}
          <select
            value={roleFilter}
            onChange={e => setRoleFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400"
          >
            <option value="">All Roles</option>
            {ROLES.map(r => (
              <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>
            ))}
          </select>

          {/* Status */}
          <select
            value={statusFilter}
            onChange={e => setStatusFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400"
          >
            <option value="">All Statuses</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
          </select>

          {/* Verified */}
          <select
            value={verifiedFilter}
            onChange={e => setVerifiedFilter(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400"
          >
            <option value="">All Verification</option>
            <option value="true">Verified</option>
            <option value="false">Unverified</option>
          </select>

          {/* Clear filters */}
          {(searchInput || roleFilter || statusFilter || verifiedFilter) && (
            <button
              onClick={() => {
                setSearchInput('');
                setRoleFilter('');
                setStatusFilter('');
                setVerifiedFilter('');
              }}
              className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700 border border-gray-200 rounded-xl hover:bg-gray-50 transition-colors"
            >
              ✕ Clear
            </button>
          )}
        </div>

        {/* ── Table ───────────────────────────────────────────────────────── */}
        {loading ? <TableSkeleton /> : (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {/* Select-all checkbox */}
                    <th className="pl-5 pr-3 py-3.5 w-10">
                      <input
                        type="checkbox"
                        checked={allSelected}
                        ref={el => { if (el) el.indeterminate = someSelected; }}
                        onChange={toggleSelectAll}
                        className="rounded border-gray-300 text-orange-500 focus:ring-orange-400 cursor-pointer"
                      />
                    </th>
                    {['User', 'Role', 'Activity', 'Status', 'Verified', 'Joined', 'Actions'].map(h => (
                      <th key={h} className="px-4 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {users.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-6 py-16 text-center">
                        <div className="text-gray-300 text-4xl mb-3">👤</div>
                        <p className="text-gray-400 text-sm">No users found</p>
                      </td>
                    </tr>
                  )}
                  {users.map(u => {
                    const isChecked = selected2.has(u.id);
                    return (
                      <tr
                        key={u.id}
                        onClick={() => setSelected(u)}
                        className={`transition-colors cursor-pointer ${
                          isChecked ? 'bg-orange-50/60' : 'hover:bg-gray-50/60'
                        }`}
                      >
                        {/* Checkbox */}
                        <td className="pl-5 pr-3 py-4" onClick={e => toggleSelectOne(u.id, e)}>
                          <input
                            type="checkbox"
                            checked={isChecked}
                            onChange={() => {}}
                            className="rounded border-gray-300 text-orange-500 focus:ring-orange-400 cursor-pointer"
                          />
                        </td>

                        {/* User */}
                        <td className="px-4 py-4">
                          <div className="flex items-center gap-3">
                            {u.profile_photo_url ? (
                              <img src={u.profile_photo_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" />
                            ) : (
                              <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-xs shrink-0 ${avatarColor(u.role)}`}>
                                {initials(u)}
                              </div>
                            )}
                            <div className="min-w-0">
                              <p className="font-medium text-gray-900 truncate">{u.display_name || <span className="text-gray-400 italic">No name</span>}</p>
                              <p className="text-xs text-gray-400 truncate">{u.email}</p>
                              {u.phone && <p className="text-xs text-gray-300">{u.phone}</p>}
                            </div>
                          </div>
                        </td>

                        {/* Role */}
                        <td className="px-4 py-4">
                          <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${ROLE_STYLES[u.role] ?? 'bg-gray-100 text-gray-600'}`}>
                            {u.role}
                          </span>
                        </td>

                        {/* Activity — label is role-contextual */}
                        <td className="px-4 py-4">
                          {u.order_count === '—' ? (
                            <span className="text-gray-300">—</span>
                          ) : (
                            <span className="inline-flex items-center gap-1 bg-gray-50 text-gray-700 text-xs font-medium px-2.5 py-1 rounded-full">
                              {u.order_count}
                              {ROLE_ACTIVITY_LABEL[u.role] && (
                                <span className="text-gray-400 font-normal">{ROLE_ACTIVITY_LABEL[u.role]}</span>
                              )}
                            </span>
                          )}
                        </td>

                        {/* Status */}
                        <td className="px-4 py-4">
                          <span className={`inline-flex items-center gap-1.5 text-xs font-medium ${
                            u.status === 'active' ? 'text-green-600' : 'text-red-500'
                          }`}>
                            <span className={`w-1.5 h-1.5 rounded-full ${
                              u.status === 'active' ? 'bg-green-500' : 'bg-red-400'
                            }`} />
                            {u.status === 'active' ? 'Active' : 'Suspended'}
                          </span>
                        </td>

                        {/* Verified */}
                        <td className="px-4 py-4">
                          {u.email_verified
                            ? <span className="text-green-600 text-xs font-medium">✓ Verified</span>
                            : <span className="text-amber-500 text-xs font-medium">⚠ Pending</span>}
                        </td>

                        {/* Joined */}
                        <td className="px-4 py-4 text-gray-400 text-xs whitespace-nowrap">
                          {new Date(u.created_at).toLocaleDateString()}
                        </td>

                        {/* Inline quick actions — stop propagation so drawer doesn't open */}
                        <td className="px-4 py-4" onClick={e => e.stopPropagation()}>
                          <div className="flex items-center gap-2">
                            {/* Quick suspend/reactivate toggle */}
                            <button
                              onClick={e => void quickToggle(u, e)}
                              title={u.status === 'active' ? 'Suspend' : 'Reactivate'}
                              className={`text-xs px-2.5 py-1.5 rounded-lg font-medium transition-colors ${
                                u.status === 'active'
                                  ? 'bg-red-50 text-red-600 hover:bg-red-100'
                                  : 'bg-green-50 text-green-700 hover:bg-green-100'
                              }`}
                            >
                              {u.status === 'active' ? 'Suspend' : 'Reactivate'}
                            </button>
                            {/* Manage drawer button */}
                            <button
                              onClick={e => { e.stopPropagation(); setSelected(u); }}
                              className="text-xs px-2.5 py-1.5 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors font-medium"
                            >
                              Manage
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {pagination && pagination.pages > 1 && (
              <div className="flex items-center justify-between px-5 py-4 border-t border-gray-100">
                <p className="text-xs text-gray-500">
                  Showing {((pagination.page - 1) * pagination.limit) + 1}–{Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total.toLocaleString()}
                </p>
                <div className="flex gap-1.5">
                  <button
                    disabled={page <= 1}
                    onClick={() => { const p = page - 1; setPage(p); load(p); }}
                    className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 hover:bg-gray-50 disabled:opacity-40 transition-colors"
                  >
                    ← Prev
                  </button>
                  {Array.from({ length: Math.min(pagination.pages, 5) }, (_, i) => {
                    const p = Math.max(1, page - 2) + i;
                    if (p > pagination.pages) return null;
                    return (
                      <button
                        key={p}
                        onClick={() => { setPage(p); load(p); }}
                        className={`px-3 py-1.5 text-xs rounded-lg border transition-colors ${
                          p === page ? 'bg-orange-500 text-white border-orange-500' : 'border-gray-200 hover:bg-gray-50'
                        }`}
                      >
                        {p}
                      </button>
                    );
                  })}
                  <button
                    disabled={page >= pagination.pages}
                    onClick={() => { const p = page + 1; setPage(p); load(p); }}
                    className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 hover:bg-gray-50 disabled:opacity-40 transition-colors"
                  >
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
