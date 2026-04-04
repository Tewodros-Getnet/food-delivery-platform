'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface User {
  id: string;
  email: string;
  role: string;
  display_name: string | null;
  status: string;
  created_at: string;
  order_count: string;
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
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Users</h1>
      <div className="flex gap-3">
        <input value={search} onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by email or name..."
          className="border rounded-lg px-3 py-2 text-sm flex-1" />
        <select value={role} onChange={(e) => setRole(e.target.value)}
          className="border rounded-lg px-3 py-2 text-sm">
          <option value="">All Roles</option>
          {['customer', 'restaurant', 'rider'].map((r) => (
            <option key={r} value={r}>{r}</option>
          ))}
        </select>
        <button onClick={load} className="bg-orange-500 text-white px-4 py-2 rounded-lg text-sm hover:bg-orange-600">
          Search
        </button>
      </div>

      {loading ? <div className="text-center py-8">Loading...</div> : (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>{['Email', 'Name', 'Role', 'Orders', 'Status', 'Joined', 'Actions'].map((h) => (
                <th key={h} className="text-left px-4 py-3 font-medium text-gray-600">{h}</th>
              ))}</tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id} className="border-b last:border-0 hover:bg-gray-50">
                  <td className="px-4 py-3">{u.email}</td>
                  <td className="px-4 py-3">{u.display_name || '—'}</td>
                  <td className="px-4 py-3 capitalize">{u.role}</td>
                  <td className="px-4 py-3">{u.order_count}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                      u.status === 'active' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                    }`}>{u.status}</span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">{new Date(u.created_at).toLocaleDateString()}</td>
                  <td className="px-4 py-3">
                    <button onClick={() => toggleSuspend(u)}
                      className={`text-xs px-2 py-1 rounded text-white ${
                        u.status === 'active' ? 'bg-red-500 hover:bg-red-600' : 'bg-green-500 hover:bg-green-600'
                      }`}>
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
