'use client';
import { useEffect, useRef, useState } from 'react';
import { io, Socket } from 'socket.io-client';

interface Notification {
  id: string;
  message: string;
  type: 'dispute' | 'stuck_order';
  orderId?: string;
  timestamp: Date;
}

const TYPE_ICON: Record<string, string> = {
  dispute: '⚖️',
  stuck_order: '🛵',
};

export default function RealtimeNotifications() {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [showPanel, setShowPanel] = useState(false);
  const socketRef = useRef<Socket | null>(null);

  useEffect(() => {
    const token = typeof window !== 'undefined' ? localStorage.getItem('jwt') : null;
    if (!token) return;

    const wsUrl = process.env.NEXT_PUBLIC_WS_URL || 'http://localhost:3000';
    const socket = io(wsUrl, {
      auth: { token },
      transports: ['websocket'],
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 2000,
    });
    socketRef.current = socket;

    // Dispute resolved — notify admin
    socket.on('dispute:resolved', (data: { data?: { orderId?: string } }) => {
      addNotification({
        message: 'A dispute has been resolved',
        type: 'dispute',
        orderId: data?.data?.orderId,
      });
    });

    // Server-side stuck order alert — no client-side timer needed
    socket.on('admin:alert', (data: {
      data: { type: string; orderId?: string; message: string };
    }) => {
      const { type, orderId, message } = data.data;
      addNotification({
        message,
        type: type as Notification['type'],
        orderId,
      });
    });

    return () => {
      socket.disconnect();
      socketRef.current = null;
    };
  }, []);

  const addNotification = (n: Omit<Notification, 'id' | 'timestamp'>) => {
    setNotifications((prev) => {
      // Deduplicate stuck_order alerts for the same order
      if (n.type === 'stuck_order' && n.orderId) {
        const alreadyExists = prev.some(
          (p) => p.type === 'stuck_order' && p.orderId === n.orderId
        );
        if (alreadyExists) return prev;
      }
      return [
        { ...n, id: Date.now().toString(), timestamp: new Date() },
        ...prev.slice(0, 19), // keep last 20
      ];
    });
  };

  const unread = notifications.length;

  return (
    <div className="relative">
      <button
        onClick={() => setShowPanel(!showPanel)}
        className="relative p-2 text-gray-400 hover:text-gray-700 transition-colors"
        aria-label="Notifications"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
        </svg>
        {unread > 0 && (
          <span className="absolute -top-0.5 -right-0.5 bg-red-500 text-white text-xs rounded-full w-4 h-4 flex items-center justify-center font-bold leading-none">
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      {showPanel && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowPanel(false)}
          />
          {/* Panel */}
          <div className="absolute right-0 top-10 w-80 bg-white rounded-xl shadow-2xl border border-gray-100 z-50 overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
              <span className="font-semibold text-sm text-gray-900">Notifications</span>
              {notifications.length > 0 && (
                <button
                  onClick={() => setNotifications([])}
                  className="text-xs text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Clear all
                </button>
              )}
            </div>

            {notifications.length === 0 ? (
              <div className="py-10 text-center">
                <div className="text-3xl mb-2">🔔</div>
                <p className="text-sm text-gray-400">No notifications</p>
              </div>
            ) : (
              <ul className="max-h-72 overflow-y-auto divide-y divide-gray-50">
                {notifications.map((n) => (
                  <li key={n.id} className="px-4 py-3 hover:bg-gray-50 transition-colors">
                    <div className="flex items-start gap-3">
                      <span className="text-lg shrink-0 mt-0.5">
                        {TYPE_ICON[n.type] ?? '🔔'}
                      </span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-gray-800 leading-snug">{n.message}</p>
                        {n.orderId && (
                          <p className="text-xs text-gray-400 font-mono mt-0.5">
                            #{n.orderId.substring(0, 8)}
                          </p>
                        )}
                        <p className="text-xs text-gray-400 mt-1">
                          {n.timestamp.toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </p>
                      </div>
                      <button
                        onClick={() =>
                          setNotifications((prev) =>
                            prev.filter((x) => x.id !== n.id)
                          )
                        }
                        className="text-gray-300 hover:text-gray-500 shrink-0 transition-colors"
                      >
                        ×
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </>
      )}
    </div>
  );
}
