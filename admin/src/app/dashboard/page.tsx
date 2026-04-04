'use client';
import { useEffect, useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import { api } from '@/lib/api';

interface Analytics {
  totalOrders: number;
  totalRevenue: number;
  activeUsers: number;
  ordersByStatus: { status: string; count: string }[];
  topRestaurants: { name: string; order_count: string }[];
  topRiders: { display_name: string; delivery_count: string }[];
}

const COLORS = ['#f97316', '#3b82f6', '#10b981', '#ef4444', '#8b5cf6', '#f59e0b'];

export default function AnalyticsPage() {
  const [data, setData] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get('/admin/analytics')
      .then((res) => setData(res.data.data as Analytics))
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-500" /></div>;
  if (!data) return <p className="text-red-500">Failed to load analytics</p>;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Analytics</h1>

      {/* KPI Cards */}
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: 'Total Orders', value: data.totalOrders, icon: '📦' },
          { label: 'Total Revenue', value: `ETB ${data.totalRevenue.toFixed(2)}`, icon: '💰' },
          { label: 'Active Users', value: data.activeUsers, icon: '👥' },
        ].map((card) => (
          <div key={card.label} className="bg-white rounded-xl p-5 shadow-sm border">
            <div className="text-2xl mb-2">{card.icon}</div>
            <div className="text-2xl font-bold">{card.value}</div>
            <div className="text-gray-500 text-sm">{card.label}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-6">
        {/* Orders by Status */}
        <div className="bg-white rounded-xl p-5 shadow-sm border">
          <h2 className="font-semibold mb-4">Orders by Status</h2>
          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie data={data.ordersByStatus} dataKey="count" nameKey="status" cx="50%" cy="50%" outerRadius={80}>
                {data.ordersByStatus.map((_, i) => (
                  <Cell key={i} fill={COLORS[i % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Top Restaurants */}
        <div className="bg-white rounded-xl p-5 shadow-sm border">
          <h2 className="font-semibold mb-4">Top Restaurants</h2>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={data.topRestaurants}>
              <XAxis dataKey="name" tick={{ fontSize: 11 }} />
              <YAxis />
              <Tooltip />
              <Bar dataKey="order_count" fill="#f97316" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Top Riders */}
      <div className="bg-white rounded-xl p-5 shadow-sm border">
        <h2 className="font-semibold mb-4">Top Riders</h2>
        <table className="w-full text-sm">
          <thead><tr className="text-left text-gray-500 border-b">
            <th className="pb-2">Rider</th>
            <th className="pb-2">Deliveries</th>
          </tr></thead>
          <tbody>
            {data.topRiders.map((r, i) => (
              <tr key={i} className="border-b last:border-0">
                <td className="py-2">{r.display_name || 'Unknown'}</td>
                <td className="py-2 font-semibold">{r.delivery_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
