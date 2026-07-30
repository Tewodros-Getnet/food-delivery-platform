'use client';
import { useEffect, useState, useRef } from 'react';
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
  created_at: string;
  order_count: string;
}
interface Pagination { page: number; limit: number; total: number; pages: number; }

// ── Constants ─────────────────────────────────────────────────────────────────
const ROLE_STYLES: Record<string, string> = {
  customer:   'bg-blue-50 text-blue-700',
  restaurant: 'bg-orange-50 text-orange-700',
  rider:      'bg-purple-50 text-purple-700',
  admin:      'bg-gray-100 text-gray-700',
};
const ROLES = ['customer', 'restaurant', 'rider', 'admin'];

// ── Skeleton ──────────────────────────────────────────────────────────────────
function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1,2,3,4,5].map(i => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-8 bg-gray-200 rounded-full" />
          <div className="h-4 w-40 bg-gray-200 rounded" />
          <div className="h-4 w-20 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

// ── Confirm dialog ────────────────────────────────────────────────────────────
function ConfirmModal({ title, message, confirmLabel, danger, onConfirm, onCancel }: {
  title: string; message: string; confirmLabel: string;
  danger?: boolean; onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/40 backdrop-blur-sm px-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">{title}</h3>
        <p className="text-sm text-gray-500 mb-6">{message}</p>
        <div className="flex gap-3 justify-end">
          <button onClick={onCancel}
            className="px-4 py-2 text-sm rounded-xl border border-gray-200 hover:bg-gray-50 transition-colors">
            Cancel
          </button>
          <button onClick={onConfirm}
            className={`px-4 py-2 text-sm rounded-xl text-white font-medium transition-colors ${danger ? 'bg-red-500 hover:bg-red-600' : 'bg-orange-500 hover:bg-orange-600'}`}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── User detail / action modal ────────────────────────────────────────────────
function UserDetailModal({ user: initialUser, onClose, onAction }: {
  user: User; onClose: () => void;
  onAction: (id: string, type: string, payload?: string) => Promise<void>;
}) {
  const [user, setUser]       = useState(initialUser);
  const [busy, setBusy]       = useState<string | null>(null);
  const [toast, setToast]     = useState<{ msg: string; ok: boolean } | null>(null);
  const [newRole, setNewRole] = useState(user.role);
  const [confirm, setConfirm] = useState<null | { type: string; label: string; message: string; danger?: boolean }>(null);

  const act = async (type: string, payload?: string) => {
    setBusy(type);
    setToast(null);
    try {
      await onAction(user.id, type, payload);
      const labels: Record<string, string> = {
        delete: 'User deleted',
        role: `Role changed to ${payload}`,
        'force-logout': 'All sessions terminated',
        'resend-verification': 'Verification email sent',
        suspend: 'User suspended',
        reactivate: 'User reactivated',
      };
      setToast({ msg: labels[type] ?? 'Done', ok: true });
      // Optimistically update the local user copy
      if (type === 'suspend')         setUser(u => ({ ...u, status: 'suspended' }));
      else if (type === 'reactivate') setUser(u => ({ ...u, status: 'active' }));
      else if (type === 'role')       setUser(u => ({ ...u, role: payload! }));
      else if (type === 'delete')     { setTimeout(onClose, 700); return; }
    } catch (e: unknown) {
      const msg = (e as { response?: { data?: { error?: string } } })?.response?.data?.error ?? 'Action failed';
      setToast({ msg: `Error: ${msg}`, ok: false });
    } finally { setBusy(null); setConfirm(null); }
  };

  const btn = 'w-full text-left px-4 py-2.5 text-sm rounded-xl font-medium transition-colors flex items-center gap-2 disabled:opacity-40';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm px-0 sm:px-4">
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-xl w-full sm:max-w-lg max-h-[92vh] overflow-y-auto">

        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4 border-b border-gray-100 sticky top-0 bg-white z-10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center text-orange-600 font-bold text-base shrink-0">
              {(user.display_name || user.email)[0].toUpperCase()}
            </div>
            <div>
              <p className="font-semibold text-gray-900 text-sm">{user.display_name || '—'}</p>
              <p className="text-xs text-gray-400">{user.email}</p>
            </div>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 transition-colors p-1 shrink-0">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Info grid */}
        <div className="px-6 py-4 grid grid-cols-2 gap-3 text-sm">
          {([
            ['Role',     <span key="r" className={`px-2 py-0.5 rounded-full text-xs font-medium ${ROLE_STYLES[user.role] ?? 'bg-gray-100 text-gray-600'}`}>{user.role}</span>],
            ['Status',   <span key="s" className={`px-2 py-0.5 rounded-full text-xs font-medium ${user.status === 'active' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'}`}>{user.status}</span>],
            ['Verified', user.email_verified ? <span key="v" className="text-green-600 text-xs font-medium">✓ Verified</span> : <span key="v" className="text-amber-500 text-xs font-medium">Pending</span>],
            ['Activity', <span key="a" className="text-gray-700">{user.order_count} orders</span>],
            ['Phone',    <span key="p" className="text-gray-700">{user.phone || '—'}</span>],
            ['Joined',   <span key="j" className="text-gray-700">{new Date(user.created_at).toLocaleDateString()}</span>],
          ] as [string, React.ReactNode][]).map(([label, val]) => (
            <div key={label} className="bg-gray-50 rounded-xl px-3 py-2.5">
              <p className="text-xs text-gray-400 mb-0.5">{label}</p>
              <div className="text-sm">{val}</div>
            </div>
          ))}
        </div>

        {/* Actions */}
        <div className="px-6 pb-2 space-y-2 border-t border-gray-100 pt-4">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Actions</p>

          {/* Suspend / Reactivate */}
          <button disabled={!!busy} onClick={() => setConfirm(
            user.status === 'active'
              ? { type: 'suspend',    label: 'Suspend',    message: `Suspend ${user.email}? They will be immediately logged out.`, danger: true }
              : { type: 'reactivate', label: 'Reactivate', message: `Reactivate ${user.email}? They will be able to log in again.` }
          )} className={`${btn} ${user.status === 'active' ? 'bg-red-50 text-red-600 hover:bg-red-100' : 'bg-green-50 text-green-700 hover:bg-green-100'}`}>
            <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d={user.status === 'active'
                  ? 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636'
                  : 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'} />
            </svg>
            {(busy === 'suspend' || busy === 'reactivate') ? 'Working…' : user.status === 'active' ? 'Suspend user' : 'Reactivate user'}
          </button>

          {/* Force logout */}
          <button disabled={!!busy} onClick={() => setConfirm({ type: 'force-logout', label: 'Force Logout', message: `Terminate all active sessions for ${user.email}? They will need to log in again on all devices.` })}
            className={`${btn} bg-yellow-50 text-yellow-700 hover:bg-yellow-100`}>
            <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            </svg>
            {busy === 'force-logout' ? 'Working…' : 'Force logout (revoke all sessions)'}
          </button>

          {/* Resend verification — only when unverified */}
          {!user.email_verified && (
            <button disabled={!!busy} onClick={() => act('resend-verification')}
              className={`${btn} bg-blue-50 text-blue-700 hover:bg-blue-100`}>
              <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              {busy === 'resend-verification' ? 'Sending…' : 'Resend verification email'}
            </button>
          )}

          {/* Change role */}
          <div className="bg-gray-50 rounded-xl px-4 py-3">
            <p className="text-xs font-medium text-gray-500 mb-2">Change role</p>
            <div className="flex gap-2">
              <select value={newRole} onChange={e => setNewRole(e.target.value)}
                className="flex-1 border border-gray-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400">
                {ROLES.map(r => <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>)}
              </select>
              <button disabled={!!busy || newRole === user.role}
                onClick={() => setConfirm({ type: 'role', label: 'Change Role',
                  message: `Change role of ${user.email} from "${user.role}" to "${newRole}"? Their current sessions will be revoked.` })}
                className="px-4 py-1.5 text-sm bg-orange-500 hover:bg-orange-600 disabled:opacity-40 text-white rounded-lg font-medium transition-colors">
                {busy === 'role' ? '…' : 'Apply'}
              </button>
            </div>
          </div>

          {/* Delete */}
          <button disabled={!!busy}
            onClick={() => setConfirm({ type: 'delete', label: 'Delete User', danger: true,
              message: `Permanently delete ${user.email}? This cannot be undone. Their account, sessions, and tokens will be removed.` })}
            className={`${btn} bg-red-50 text-red-600 hover:bg-red-100`}>
            <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            {busy === 'delete' ? 'Deleting…' : 'Delete user permanently'}
          </button>
        </div>

        {/* Toast feedback */}
        {toast && (
          <div className={`mx-6 mb-5 mt-3 px-4 py-3 rounded-xl text-sm font-medium ${toast.ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'}`}>
            {toast.msg}
          </div>
        )}
      </div>

      {/* Confirm dialog on top */}
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
  const [loading, setLoading]       = useState(true);
  const [search, setSearch]         = useState('');
  const [role, setRole]             = useState('');
  const [page, setPage]             = useState(1);
  const [selected, setSelected]     = useState<User | null>(null);
  const searchRef                   = useRef('');
  const roleRef                     = useRef('');
  searchRef.current = search;
  roleRef.current   = role;

  const load = (p: number) => {
    setLoading(true);
    api.get('/admin/users', {
      params: {
        search: searchRef.current || undefined,
        role:   roleRef.current   || undefined,
        page: p,
        limit: 20,
      },
    })
      .then(res => {
        const d = res.data.data;
        if (Array.isArray(d)) { setUsers(d); setPagination(null); }
        else                  { setUsers(d.users); setPagination(d.pagination); }
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(1); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const handleSearch = () => { setPage(1); load(1); };

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

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Page header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Users</h1>
        {pagination && (
          <p className="text-sm text-gray-400 mt-1">{pagination.total} total users</p>
        )}
      </div>

      {/* Search + filter bar */}
      <div className="flex gap-3 mb-6 flex-wrap">
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && handleSearch()}
          placeholder="Search by email or name…"
          className="flex-1 min-w-[220px] border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
        />
        <select value={role} onChange={e => { setRole(e.target.value); }}
          className="border border-gray-200 rounded-xl px-4 py-2.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-orange-400">
          <option value="">All Roles</option>
          {ROLES.map(r => <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>)}
        </select>
        <button onClick={handleSearch}
          className="px-5 py-2.5 bg-orange-500 hover:bg-orange-600 text-white text-sm font-medium rounded-xl transition-colors">
          Search
        </button>
      </div>

      {/* Table */}
      {loading ? <TableSkeleton /> : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  {['User', 'Role', 'Activity', 'Verified', 'Status', 'Joined', 'Actions'].map(h => (
                    <th key={h} className="px-6 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {users.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-6 py-12 text-center text-gray-400 text-sm">
                      No users found
                    </td>
                  </tr>
                )}
                {users.map(u => (
                  <tr key={u.id} className="hover:bg-gray-50/60 transition-colors">
                    {/* User */}
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center text-orange-600 font-bold text-xs shrink-0">
                          {(u.display_name || u.email)[0].toUpperCase()}
                        </div>
                        <div>
                          <p className="font-medium text-gray-900 text-sm">{u.display_name || '—'}</p>
                          <p className="text-xs text-gray-400">{u.email}</p>
                        </div>
                      </div>
                    </td>
                    {/* Role */}
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${ROLE_STYLES[u.role] ?? 'bg-gray-100 text-gray-600'}`}>
                        {u.role}
                      </span>
                    </td>
                    {/* Activity */}
                    <td className="px-6 py-4 text-gray-500">{u.order_count}</td>
                    {/* Verified */}
                    <td className="px-6 py-4">
                      {u.email_verified
                        ? <span className="flex items-center gap-1 text-green-600 text-xs font-medium"><span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block" />Verified</span>
                        : <span className="flex items-center gap-1 text-amber-500 text-xs font-medium"><span className="w-1.5 h-1.5 rounded-full bg-amber-400 inline-block" />Pending</span>}
                    </td>
                    {/* Status */}
                    <td className="px-6 py-4">
                      <span className={`flex items-center gap-1 text-xs font-medium ${u.status === 'active' ? 'text-green-600' : 'text-red-500'}`}>
                        <span className={`w-1.5 h-1.5 rounded-full inline-block ${u.status === 'active' ? 'bg-green-500' : 'bg-red-400'}`} />
                        {u.status.charAt(0).toUpperCase() + u.status.slice(1)}
                      </span>
                    </td>
                    {/* Joined */}
                    <td className="px-6 py-4 text-gray-400 whitespace-nowrap">
                      {new Date(u.created_at).toLocaleDateString()}
                    </td>
                    {/* Actions */}
                    <td className="px-6 py-4">
                      <button onClick={() => setSelected(u)}
                        className="px-3 py-1.5 text-xs font-medium rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
                        Manage
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {pagination && pagination.pages > 1 && (
            <div className="flex items-center justify-between px-6 py-4 border-t border-gray-100">
              <p className="text-sm text-gray-400">
                Page {pagination.page} of {pagination.pages} · {pagination.total} users
              </p>
              <div className="flex gap-2">
                <button disabled={pagination.page <= 1}
                  onClick={() => { const p = page - 1; setPage(p); load(p); }}
                  className="px-3 py-1.5 text-sm rounded-lg border border-gray-200 hover:bg-gray-50 disabled:opacity-40 transition-colors">
                  ← Prev
                </button>
                <button disabled={pagination.page >= pagination.pages}
                  onClick={() => { const p = page + 1; setPage(p); load(p); }}
                  className="px-3 py-1.5 text-sm rounded-lg border border-gray-200 hover:bg-gray-50 disabled:opacity-40 transition-colors">
                  Next →
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* User detail modal */}
      {selected && (
        <UserDetailModal
          user={selected}
          onClose={() => setSelected(null)}
          onAction={handleAction}
        />
      )}
    </div>
  );
}
