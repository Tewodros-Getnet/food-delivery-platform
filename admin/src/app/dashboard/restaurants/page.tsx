'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Restaurant {
  id: string;
  name: string;
  owner_email: string;
  status: string;
  menu_count: string;
  average_rating: number;
}

const STATUS_COLORS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  approved: 'bg-green-100 text-green-800',
  rejected: 'bg-red-100 text-red-800',
  suspended: 'bg-gray-100 text-gray-800',
};

export default function RestaurantsPage() {
  const [restaurants, setRestaurants] = useState<Restaurant[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');

  const load = (status?: string) => {
    setLoading(true);
    api.get('/admin/restaurants', { params: status ? { status } : {} })
      .then((res) => setRestaurants(res.data.data as Restaurant[]))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  const action = async (id: string, action: 'approve' | 'reject' | 'suspend') => {
    const endpoints: Record<string, string> = {
      approve: `/restaurants/${id}/approve`,
      reject: `/restaurants/${id}/reject`,
      suspend: `/restaurants/${id}/suspend`,
    };
    const methods: Record<string, 'post' | 'put'> = { approve: 'post', reject: 'post', suspend: 'put' };
    await api[methods[action]](endpoints[action]);
    load(filter || undefined);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Restaurants</h1>
        <select value={filter} onChange={(e) => { setFilter(e.target.value); load(e.target.value || undefined); }}
          className="border rounded-lg px-3 py-2 text-sm">
          <option value="">All Statuses</option>
          {['pending', 'approved', 'rejected', 'suspended'].map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
      </div>

      {loading ? <div className="text-center py-8">Loading...</div> : (
        <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>{['Name', 'Owner', 'Status', 'Menu Items', 'Rating', 'Actions'].map((h) => (
                <th key={h} className="text-left px-4 py-3 font-medium text-gray-600">{h}</th>
              ))}</tr>
            </thead>
            <tbody>
              {restaurants.map((r) => (
                <tr key={r.id} className="border-b last:border-0 hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium">{r.name}</td>
                  <td className="px-4 py-3 text-gray-500">{r.owner_email}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${STATUS_COLORS[r.status] || ''}`}>
                      {r.status}
                    </span>
                  </td>
                  <td className="px-4 py-3">{r.menu_count}</td>
                  <td className="px-4 py-3">⭐ {Number(r.average_rating).toFixed(1)}</td>
                  <td className="px-4 py-3">
                    <div className="flex gap-2">
                      {r.status === 'pending' && <>
                        <button onClick={() => action(r.id, 'approve')}
                          className="text-xs bg-green-500 text-white px-2 py-1 rounded hover:bg-green-600">Approve</button>
                        <button onClick={() => action(r.id, 'reject')}
                          className="text-xs bg-red-500 text-white px-2 py-1 rounded hover:bg-red-600">Reject</button>
                      </>}
                      {r.status === 'approved' && (
                        <button onClick={() => action(r.id, 'suspend')}
                          className="text-xs bg-gray-500 text-white px-2 py-1 rounded hover:bg-gray-600">Suspend</button>
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
  );
}
