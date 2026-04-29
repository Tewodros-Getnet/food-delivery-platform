'use client';
import { useEffect, useState } from 'react';
import { api } from '@/lib/api';

interface Rider {
  id: string;
  email: string;
  display_name: string | null;
  phone: string | null;
  status: string;
  created_at: string;
  availability: string | null;
  last_seen: string | null;
  restaurant_name: string | null;
  total_deliveries: string;
  average_rating: string | null;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
  pages: number;
}

const AVAILABILITY_STYLES: Record<string, string> = {
  available: 'bg-green-50 text-green-700',
  on_delivery: 'bg-blue-50 text-blue-700',
  offline: 'bg-gray-100 text-gray-500',
};

const AVAILABILITY_DOT: Record<string, string> = {
  available: 'bg-green-400',
  on_delivery: 'bg-blue-400',
  offline: 'bg-gray-300',
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

export default function RidersPage() {
  const [riders, setRiders] = useState<Rider[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);

  const load = (p = page) => {
    setLoading(true);
    api.get('/admin/riders', { params: { page: p, limit: 20 } })
      .then((res) => {
        const data = res.data.data;
        setRiders(data.riders as Rider[]);
        setPagination(data.pagination as Pagination);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(1); }, []);

  const toggleSuspend = async (rider: Rider) => {
    const endpoint = rider.status === 'active'
      ? `/admin/users/${rider.id}/suspend`
      : `/admin/users/${rider.id}/reactivate`;
    await api.put(endpoint);
    load(page);
  };

  const goToPage = (p: number) => { setPage(p); load(p); };

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Riders</h1>
          <p className="text-gray-500 text-sm mt-0.5">
            {pagination ? `${pagination.total.toLocaleString()} total riders` : ''}
          </p>
        </div>
        <button
          onClick={() => load(page)}
          className="flex items-center gap-2 border border-gray-200 rounded-xl px-4 py-2 text-sm hover:bg-gray-50 transition-colors"
        >
          <svg className="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Refresh
        </button>
      </div>

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
                const rating = r.average_rating ? parseFloat(r.average_rating).toFixed(1) : '—';
                return (
                  <tr key={r.id} className="hover:bg-gray-50/50 transition-colors">
                    <td className="px-5 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-purple-100 flex items-center justify-center text-purple-600 font-semibold text-sm shrink-0">
                          {(r.display_name || r.email)[0].toUpperCase()}
                        </div>
                        <div>
                          <div className="font-medium text-gray-800">{r.display_name || '—'}</div>
                          <div className="text-gray-400 text-xs">{r.email}</div>
                          {r.phone && <div className="text-gray-400 text-xs">{r.phone}</div>}
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${
                        r.status === 'active' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'
                      }`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${r.status === 'active' ? 'bg-green-400' : 'bg-red-400'}`} />
                        {r.status.charAt(0).toUpperCase() + r.status.slice(1)}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${AVAILABILITY_STYLES[avail] ?? 'bg-gray-100 text-gray-500'}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${AVAILABILITY_DOT[avail] ?? 'bg-gray-300'}`} />
                        {avail.replaceAll('_', ' ')}
                      </span>
                      {r.last_seen && (
                        <div className="text-gray-400 text-xs mt-0.5">
                          {new Date(r.last_seen).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </div>
                      )}
                    </td>
                    <td className="px-5 py-4 text-gray-600 text-sm">
                      {r.restaurant_name ?? <span className="text-gray-300 italic">Unassigned</span>}
                    </td>
                    <td className="px-5 py-4">
                      <span className="inline-flex items-center gap-1.5 bg-green-50 text-green-700 text-xs font-semibold px-2.5 py-1 rounded-full">
                        {r.total_deliveries}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      {rating !== '—' ? (
                        <div className="flex items-center gap-1">
                          <svg className="w-3.5 h-3.5 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                            <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                          </svg>
                          <span className="text-gray-700 text-sm font-medium">{rating}</span>
                        </div>
                      ) : <span className="text-gray-300">—</span>}
                    </td>
                    <td className="px-5 py-4 text-gray-400 text-xs whitespace-nowrap">
                      {new Date(r.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-5 py-4">
                      <button
                        onClick={() => toggleSuspend(r)}
                        className={`text-xs px-3 py-1.5 rounded-lg text-white font-medium transition-colors ${
                          r.status === 'active'
                            ? 'bg-red-500 hover:bg-red-600'
                            : 'bg-green-500 hover:bg-green-600'
                        }`}
                      >
                        {r.status === 'active' ? 'Suspend' : 'Reactivate'}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          {pagination && pagination.pages > 1 && (
            <div className="px-5 py-4 border-t border-gray-100 flex items-center justify-between">
              <p className="text-xs text-gray-500">
                Showing {((pagination.page - 1) * pagination.limit) + 1}–{Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total.toLocaleString()}
              </p>
              <div className="flex gap-1.5">
                <button onClick={() => goToPage(pagination.page - 1)} disabled={pagination.page <= 1}
                  className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors">← Prev</button>
                {Array.from({ length: Math.min(pagination.pages, 5) }, (_, i) => {
                  const p = Math.max(1, pagination.page - 2) + i;
                  if (p > pagination.pages) return null;
                  return (
                    <button key={p} onClick={() => goToPage(p)}
                      className={`px-3 py-1.5 text-xs rounded-lg border transition-colors ${p === pagination.page ? 'bg-orange-500 text-white border-orange-500' : 'border-gray-200 hover:bg-gray-50'}`}>
                      {p}
                    </button>
                  );
                })}
                <button onClick={() => goToPage(pagination.page + 1)} disabled={pagination.page >= pagination.pages}
                  className="px-3 py-1.5 text-xs rounded-lg border border-gray-200 disabled:opacity-40 hover:bg-gray-50 transition-colors">Next →</button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
