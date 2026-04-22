'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface User {
  id: string;
  email: string;
  role: string;
  display_name: string | null;
  status: string;
  email_verified: boolean;
  created_at: string;
  order_count: string;
}

const ROLE_STYLES: Record<string, string> = {
  customer: 'bg-blue-50 text-blue-700',
  restaurant: 'bg-orange-50 text-orange-700',
  rider: 'bg-purple-50 text-purple-700',
  admin: 'bg-gray-100 text-gray-700',
};

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

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('');

  const load = () => {
    setLoading(true);
    api.get('/admin/users', { params: { search: search || undefined, role: role || undefined } })
      .then((res) => setUsers(res.data.data as User[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  const toggleSuspend = async (user: User) => {
    const endpoint = user.status === 'active'
      ? `/admin/users/${user.id}/suspend`
      : `/admin/users/${user.id}/reactivate`;
    await api.put(endpoint);
    load();
  };

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Users</h1>
        <p className="text-gray-500 text-sm mt-0.5">{users.length} users loaded</p>
      </div>

      {/* Search bar */}
      <div className="flex gap-3">
        <div className="relative flex-1">
          <svg className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && load()}
            placeholder="Search by email or name..."
            className="w-full border border-gray-200 rounded-xl pl-10 pr-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>
        <select
          value={role}
          onChange={(e) => setRole(e.target.value)}
          className="border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
        >
          <option value="">All Roles</option>
          {['customer', 'restaurant', 'rider'].map((r) => (
            <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>
          ))}
        </select>
        <button
          onClick={load}
          className="bg-orange-500 hover:bg-orange-600 text-white px-5 py-2.5 rounded-xl text-sm font-medium transition-colors"
        >
          Search
        </button>
      </div>

      {loading ? <TableSkeleton /> : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-100">
              <tr>
                {['User', 'Role', 'Orders', 'Verified', 'Status', 'Joined', 'Actions'].map((h) => (
                  <th key={h} className="text-left px-5 py-3.5 text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {users.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-center py-16">
                    <div className="text-gray-300 text-4xl mb-3">👥</div>
                    <p className="text-gray-400 text-sm">No users found</p>
                  </td>
                </tr>
              )}
              {users.map((u) => (
                <tr key={u.id} className="hover:bg-gray-50/50 transition-colors">
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 font-semibold text-sm shrink-0">
                        {(u.display_name || u.email)[0].toUpperCase()}
                      </div>
                      <div>
                        <div className="font-medium text-gray-800">{u.display_name || '—'}</div>
                        <div className="text-gray-400 text-xs">{u.email}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-4">
                    <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${ROLE_STYLES[u.role] ?? 'bg-gray-100 text-gray-600'}`}>
                      {u.role}
                    </span>
                  </td>
                  <td className="px-5 py-4 text-gray-600">{u.order_count}</td>
                  <td className="px-5 py-4">
                    {u.email_verified ? (
                      <span className="inline-flex items-center gap-1 text-green-600 text-xs font-medium">
                        <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
                          <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                        </svg>
                        Verified
                      </span>
                    ) : (
                      <span className="text-amber-500 text-xs font-medium">Pending</span>
                    )}
                  </td>
                  <td className="px-5 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${
                      u.status === 'active' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${u.status === 'active' ? 'bg-green-400' : 'bg-red-400'}`} />
                      {u.status.charAt(0).toUpperCase() + u.status.slice(1)}
                    </span>
                  </td>
                  <td className="px-5 py-4 text-gray-400 text-xs whitespace-nowrap">
                    {new Date(u.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-5 py-4">
                    <button
                      onClick={() => toggleSuspend(u)}
                      className={`text-xs px-3 py-1.5 rounded-lg text-white font-medium transition-colors ${
                        u.status === 'active'
                          ? 'bg-red-500 hover:bg-red-600'
                          : 'bg-green-500 hover:bg-green-600'
                      }`}
                    >
                      {u.status === 'active' ? 'Suspend' : 'Reactivate'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
