'use client';
import { useEffect, useState } from 'react';
import { io } from 'socket.io-client';

interface Notification {
  id: string;
  message: string;
  type: 'dispute' | 'unassigned_order';
  timestamp: Date;
}

export default function RealtimeNotifications() {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [showPanel, setShowPanel] = useState(false);

  useEffect(() => {
    const token = typeof window !== 'undefined' ? localStorage.getItem('jwt') : null;
    if (!token) return;

    const wsUrl = process.env.NEXT_PUBLIC_WS_URL || 'http://localhost:3000';
    const socket = io(wsUrl, { auth: { token }, transports: ['websocket'] });

    socket.on('dispute:resolved', () => {
      addNotification('A dispute has been resolved', 'dispute');
    });

    // Admin alert for unassigned orders
    socket.on('order:status_changed', (data: { data: { status: string } }) => {
      if (data.data.status === 'ready_for_pickup') {
        setTimeout(() => {
          addNotification('Order unassigned for 10+ minutes — needs attention', 'unassigned_order');
        }, 10 * 60 * 1000);
      }
    });

    return () => { socket.disconnect(); };
  }, []);

  const addNotification = (message: string, type: Notification['type']) => {
    setNotifications((prev) => [
      { id: Date.now().toString(), message, type, timestamp: new Date() },
      ...prev.slice(0, 9),
    ]);
  };

  const unread = notifications.length;

  return (
    <div className="relative">
      <button onClick={() => setShowPanel(!showPanel)}
        className="relative p-2 text-gray-600 hover:text-gray-900">
        🔔
        {unread > 0 && (
          <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
            {unread}
          </span>
        )}
      </button>

      {showPanel && (
        <div className="absolute right-0 top-10 w-80 bg-white rounded-xl shadow-xl border z-50">
          <div className="p-3 border-b flex items-center justify-between">
            <span className="font-semibold text-sm">Notifications</span>
            <button onClick={() => setNotifications([])} className="text-xs text-gray-400 hover:text-gray-600">
              Clear all
            </button>
          </div>
          {notifications.length === 0 ? (
            <p className="p-4 text-sm text-gray-500 text-center">No notifications</p>
          ) : (
            <ul className="max-h-64 overflow-y-auto">
              {notifications.map((n) => (
                <li key={n.id} className="p-3 border-b last:border-0 text-sm">
                  <p>{n.message}</p>
                  <p className="text-xs text-gray-400 mt-1">{n.timestamp.toLocaleTimeString()}</p>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
