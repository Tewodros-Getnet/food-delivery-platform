'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { logout } from '@/lib/auth';

const links = [
  { href: '/dashboard', label: 'Analytics', icon: '📊' },
  { href: '/dashboard/restaurants', label: 'Restaurants', icon: '🍽️' },
  { href: '/dashboard/users', label: 'Users', icon: '👥' },
  { href: '/dashboard/orders', label: 'Orders', icon: '📦' },
  { href: '/dashboard/disputes', label: 'Disputes', icon: '⚖️' },
];

export default function Sidebar() {
  const pathname = usePathname();
  return (
    <aside className="w-56 bg-gray-900 text-white min-h-screen flex flex-col">
      <div className="p-4 border-b border-gray-700">
        <h2 className="font-bold text-lg">Admin Panel</h2>
        <p className="text-gray-400 text-xs">Food Delivery</p>
      </div>
      <nav className="flex-1 p-4 space-y-1">
        {links.map((l) => (
          <Link key={l.href} href={l.href}
            className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
              pathname === l.href ? 'bg-orange-500 text-white' : 'text-gray-300 hover:bg-gray-800'
            }`}>
            <span>{l.icon}</span>
            {l.label}
          </Link>
        ))}
      </nav>
      <div className="p-4 border-t border-gray-700">
        <button onClick={logout}
          className="w-full text-left text-gray-400 hover:text-white text-sm px-3 py-2">
          🚪 Logout
        </button>
      </div>
    </aside>
  );
}
