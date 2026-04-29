'use client';
import { useEffect, useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts';
import { api } from '@/lib/api';

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

const STATUS_COLORS = ['#f97316', '#3b82f6', '#10b981', '#ef4444', '#8b5cf6', '#f59e0b', '#06b6d4', '#84cc16'];

function StatCard({ label, value, icon, color }: { label: string; value: string | number; icon: React.ReactNode; color: string }) {
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

export default function AnalyticsPage() {
  const [data, setData] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  const load = (start?: string, end?: string) => {
    setLoading(true);
    api.get('/admin/analytics', { params: { startDate: start || undefined, endDate: end || undefined } })
      .then((res) => setData(res.data.data as Analytics))
      .catch(console.error)
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, []);

  if (loading) return <LoadingSkeleton />;
  if (!data) return (
    <div className="flex items-center justify-center h-64">
      <div className="text-center">
        <div className="text-red-400 text-4xl mb-3">⚠</div>
        <p className="text-gray-500">Failed to load analytics</p>
      </div>
    </div>
  );

  const pieData = data.ordersByStatus.map((d) => ({
    ...d,
    count: parseInt(d.count, 10),
  }));

  const barData = data.topRestaurants.map((r) => ({
    ...r,
    order_count: parseInt(r.order_count, 10),
  }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Analytics</h1>
        <p className="text-gray-500 text-sm mt-0.5">Platform overview — last 30 days</p>
      </div>

      {/* Date range picker — Fix 3 */}
      <div className="flex items-center gap-3 bg-white rounded-xl border border-gray-200 px-4 py-3">
        <svg className="w-4 h-4 text-gray-400 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
        <input
          type="date"
          value={startDate}
          onChange={(e) => setStartDate(e.target.value)}
          className="text-sm border-0 outline-none text-gray-700"
        />
        <span className="text-gray-400 text-sm">→</span>
        <input
          type="date"
          value={endDate}
          onChange={(e) => setEndDate(e.target.value)}
          className="text-sm border-0 outline-none text-gray-700"
        />
        <button
          onClick={() => load(startDate || undefined, endDate || undefined)}
          className="ml-auto bg-orange-500 hover:bg-orange-600 text-white px-4 py-1.5 rounded-lg text-sm font-medium transition-colors"
        >
          Apply
        </button>
        {(startDate || endDate) && (
          <button
            onClick={() => { setStartDate(''); setEndDate(''); load(); }}
            className="text-gray-400 hover:text-gray-600 text-sm transition-colors"
          >
            Reset
          </button>
        )}
      </div>

      {/* Refund failed alert — Fix 4 */}
      {data.refundFailedCount > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 flex items-center gap-3">
          <svg className="w-5 h-5 text-red-500 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <p className="text-sm text-red-700 flex-1">
            <span className="font-semibold">{data.refundFailedCount} order{data.refundFailedCount !== 1 ? 's' : ''}</span> have failed refunds and need manual intervention.
          </p>
          <a href="/dashboard/orders?payment_status=refund_failed" className="text-sm font-semibold text-red-700 hover:underline whitespace-nowrap">
            View orders →
          </a>
        </div>
      )}

      {/* KPI Cards */}
      <div className="grid grid-cols-3 gap-4">
        <StatCard
          label="Total Orders"
          value={data.totalOrders.toLocaleString()}
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
          value={`ETB ${data.totalRevenue.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`}
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
          value={data.activeUsers.toLocaleString()}
          color="bg-blue-50"
          icon={
            <svg className="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          }
        />
      </div>

      <div className="grid grid-cols-2 gap-6">
        {/* Orders by Status */}
        <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
          <h2 className="font-semibold text-gray-900 mb-1">Orders by Status</h2>
          <p className="text-gray-400 text-xs mb-4">Distribution across all statuses</p>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie
                data={pieData}
                dataKey="count"
                nameKey="status"
                cx="50%"
                cy="50%"
                outerRadius={80}
                innerRadius={40}
              >
                {pieData.map((_, i) => (
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

        {/* Top Restaurants */}
        <div className="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
          <h2 className="font-semibold text-gray-900 mb-1">Top Restaurants</h2>
          <p className="text-gray-400 text-xs mb-4">By order volume</p>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={barData} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
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

      {/* Top Riders */}
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-50">
          <h2 className="font-semibold text-gray-900">Top Riders</h2>
          <p className="text-gray-400 text-xs mt-0.5">By completed deliveries</p>
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">#</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Rider</th>
              <th className="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Deliveries</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {data.topRiders.length === 0 && (
              <tr><td colSpan={3} className="text-center py-8 text-gray-400 text-sm">No data yet</td></tr>
            )}
            {data.topRiders.map((r, i) => (
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
    </div>
  );
}
