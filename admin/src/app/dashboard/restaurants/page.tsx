'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Restaurant {
  id: string;
  name: string;
  owner_email: string;
  owner_name: string | null;
  status: string;
  menu_count: string;
  average_rating: number;
}

const STATUS_STYLES: Record<string, string> = {
  pending: 'bg-amber-50 text-amber-700',
  approved: 'bg-green-50 text-green-700',
  rejected: 'bg-red-50 text-red-600',
  suspended: 'bg-gray-100 text-gray-600',
};

const STATUS_DOT: Record<string, string> = {
  pending: 'bg-amber-400',
  approved: 'bg-green-400',
  rejected: 'bg-red-400',
  suspended: 'bg-gray-400',
};

function TableSkeleton() {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden animate-pulse">
      <div className="h-12 bg-gray-50 border-b border-gray-100" />
      {[1, 2, 3, 4].map((i) => (
        <div key={i} className="flex gap-4 px-6 py-4 border-b border-gray-50">
          <div className="h-4 w-32 bg-gray-200 rounded" />
          <div className="h-4 w-40 bg-gray-200 rounded" />
          <div className="h-4 w-16 bg-gray-200 rounded ml-auto" />
        </div>
      ))}
    </div>
  );
}

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

  const doAction = async (id: string, action: 'approve' | 'reject' | 'suspend') => {
    const endpoints: Record<string, string> = {
      approve: `/restaurants/${id}/approve`,
      reject: `/restaurants/${id}/reject`,
      suspend: `/restaurants/${id}/suspend`,
    };
    const methods: Record<string, 'post' | 'put'> = { approve: 'post', reject: 'post', suspend: 'put' };
    await api[methods[action]](endpoints[action]);
    load(filter || undefined);
  };

  const counts = {
    all: restaurants.length,
    pending: restaurants.filter((r) => r.status === 'pending').length,
    approved: restaurants.filter((r) => r.status === 'approved').length,
  };

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Restaurants</h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {counts.pending > 0 && (
              <span className="text-amber-600 font-medium">{counts.pending} pending approval · </span>
            )}
            {counts.approved} active
          </p>
        </div>
        <select
          value={filter}
          onChange={(e) => { setFilter(e.target.value); load(e.target.value || undefined); }}
          className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400 bg-white"
        >
          <option value="">All Statuses</option>
          {['pending', 'approved', 'rejected', 'suspended'].map((s) => (
            <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
          ))}
        </select>
      </div>

      {loading ? <TableSkeleton /> : (
        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-100">
              <tr>
                {['Restaurant', 'Owner', 'Status', 'Menu Items', 'Rating', 'Actions'].map((h) => (
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
                <tr key={r.id} className="hover:bg-gray-50/50 transition-colors">
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-lg bg-orange-50 flex items-center justify-center text-orange-500 font-bold text-sm shrink-0">
                        {r.name[0].toUpperCase()}
                      </div>
                      <span className="font-medium text-gray-800">{r.name}</span>
                    </div>
                  </td>
                  <td className="px-5 py-4 text-gray-500 text-xs">{r.owner_email}</td>
                  <td className="px-5 py-4">
                    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${STATUS_STYLES[r.status] ?? 'bg-gray-100 text-gray-600'}`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[r.status] ?? 'bg-gray-400'}`} />
                      {r.status.charAt(0).toUpperCase() + r.status.slice(1)}
                    </span>
                  </td>
                  <td className="px-5 py-4 text-gray-600">{r.menu_count} items</td>
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-1">
                      <svg className="w-3.5 h-3.5 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                      </svg>
                      <span className="text-gray-700 text-sm font-medium">{Number(r.average_rating).toFixed(1)}</span>
                    </div>
                  </td>
                  <td className="px-5 py-4">
                    <div className="flex gap-1.5">
                      {r.status === 'pending' && (
                        <>
                          <button
                            onClick={() => doAction(r.id, 'approve')}
                            className="text-xs bg-green-500 hover:bg-green-600 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => doAction(r.id, 'reject')}
                            className="text-xs bg-red-500 hover:bg-red-600 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                          >
                            Reject
                          </button>
                        </>
                      )}
                      {r.status === 'approved' && (
                        <button
                          onClick={() => doAction(r.id, 'suspend')}
                          className="text-xs bg-gray-500 hover:bg-gray-600 text-white px-3 py-1.5 rounded-lg transition-colors font-medium"
                        >
                          Suspend
                        </button>
                      )}
                      {r.status === 'suspended' && (
                        <span className="text-xs text-gray-400 italic">Suspended</span>
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
