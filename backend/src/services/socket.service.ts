import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { logger } from '../utils/logger';
import { Order } from '../models/order.model';

let io: Server;

// ── Missed event queue ────────────────────────────────────────────────────────
const MISSED_EVENT_TTL_MS = 5 * 60 * 1000; // 5 minutes

interface QueuedEvent {
  event: string;
  payload: unknown;
  ts: number;
}

const missedEventQueue = new Map<string, QueuedEvent[]>();

function queueEvent(userId: string, event: string, payload: unknown) {
  const now = Date.now();
  if (!missedEventQueue.has(userId)) {
    missedEventQueue.set(userId, []);
  }
  const queue = missedEventQueue.get(userId)!;

  // Bug 9 fix: cap queue at 50 events per user to prevent memory spike
  const MAX_QUEUE_SIZE = 50;
  if (queue.length >= MAX_QUEUE_SIZE) {
    queue.shift(); // drop oldest event
  }

  queue.push({ event, payload, ts: now });

  // Schedule TTL cleanup
  setTimeout(() => {
    const q = missedEventQueue.get(userId);
    if (!q) return;
    const fresh = q.filter(e => Date.now() - e.ts < MISSED_EVENT_TTL_MS);
    if (fresh.length === 0) {
      missedEventQueue.delete(userId);
    } else {
      missedEventQueue.set(userId, fresh);
    }
  }, MISSED_EVENT_TTL_MS);
}

function flushQueue(socket: Socket, userId: string) {
  const queue = missedEventQueue.get(userId);
  if (!queue || queue.length === 0) return;
  const now = Date.now();
  for (const item of queue) {
    if (now - item.ts < MISSED_EVENT_TTL_MS) {
      socket.emit(item.event, item.payload);
    }
  }
  missedEventQueue.delete(userId);
}

function isUserOnline(userId: string): boolean {
  if (!io) return false;
  const room = io.sockets.adapter.rooms.get(`user:${userId}`);
  return !!room && room.size > 0;
}

// ── Socket server init ────────────────────────────────────────────────────────

export function initSocketServer(socketServer: Server) {
  io = socketServer;

  io.use((socket: Socket, next) => {
    const token = socket.handshake.auth.token as string | undefined
      || socket.handshake.headers.authorization?.split(' ')[1];

    if (!token) {
      next(new Error('Authentication required'));
      return;
    }
    try {
      const payload = jwt.verify(token, env.JWT_SECRET) as { userId: string; role: string };
      socket.data.userId = payload.userId;
      socket.data.role = payload.role;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', async (socket: Socket) => {
    const userId = socket.data.userId as string;
    const role = socket.data.role as string;
    // Await join so the room exists before we flush queued events
    await socket.join(`user:${userId}`);
    // Join role room so admin broadcasts work
    if (role === 'admin') {
      await socket.join('role:admin');
    }
    logger.info('Socket connected', { socketId: socket.id, userId });

    // Deliver any events missed while offline
    flushQueue(socket, userId);

    socket.on('disconnect', async () => {
      logger.info('Socket disconnected', { socketId: socket.id, userId });
      await socket.leave(`user:${userId}`);
    });

    // ── In-app chat ───────────────────────────────────────────────────────────
    socket.on('chat:send', async (data: {
      orderId: string;
      message: string;
    }) => {
      try {
        if (!data?.orderId || !data?.message?.trim()) return;

        const { query } = await import('../config/database');

        // Verify sender is customer or rider of this order and order is active
        const orderResult = await query<{
          customer_id: string;
          rider_id: string | null;
          status: string;
        }>(
          'SELECT customer_id, rider_id, status FROM orders WHERE id = $1',
          [data.orderId]
        );
        const order = orderResult.rows[0];
        if (!order) return;

        const isCustomer = order.customer_id === userId;
        const isRider = order.rider_id === userId;
        if (!isCustomer && !isRider) return;

        const activeStatuses = ['rider_assigned', 'picked_up'];
        if (!activeStatuses.includes(order.status)) return;

        // Persist message
        const saved = await query<{
          id: string; sender_id: string; message: string; created_at: Date;
        }>(
          `INSERT INTO chat_messages (order_id, sender_id, message)
           VALUES ($1, $2, $3) RETURNING *`,
          [data.orderId, userId, data.message.trim()]
        );
        const msg = saved.rows[0];
        if (!msg) return;

        const payload = {
          orderId: data.orderId,
          messageId: msg.id,
          senderId: userId,
          message: msg.message,
          createdAt: msg.created_at.toISOString(),
        };

        // Echo back to sender so they get the confirmed message with server timestamp
        socket.emit('chat:message', { event: 'chat:message', data: payload });

        // Deliver to the other participant
        const recipientId = isCustomer ? order.rider_id : order.customer_id;
        if (recipientId) {
          emitChatMessage(recipientId, payload);
        }
      } catch (err) {
        logger.error('chat:send error', { error: String(err), userId });
      }
    });
  });
}

// ── Emit helpers ──────────────────────────────────────────────────────────────

export function emitOrderStatusChanged(order: Order, targetUserId: string) {
  if (!io) return;
  const payload = {
    event: 'order:status_changed',
    data: {
      orderId: order.id,
      status: order.status,
      timestamp: new Date().toISOString(),
      order,
    },
  };
  if (isUserOnline(targetUserId)) {
    io.to(`user:${targetUserId}`).emit('order:status_changed', payload);
  } else {
    queueEvent(targetUserId, 'order:status_changed', payload);
  }
}

export function emitToRestaurant(restaurantOwnerId: string, order: Order) {
  if (!io) return;
  const payload = {
    event: 'order:status_changed',
    data: {
      orderId: order.id,
      status: order.status,
      timestamp: new Date().toISOString(),
      order,
    },
  };
  if (isUserOnline(restaurantOwnerId)) {
    io.to(`user:${restaurantOwnerId}`).emit('order:status_changed', payload);
  } else {
    queueEvent(restaurantOwnerId, 'order:status_changed', payload);
  }
}

export function emitRiderLocationUpdate(params: {
  riderId: string;
  orderId: string;
  customerId: string;
  latitude: number;
  longitude: number;
  destinationLat?: number | null;
  destinationLon?: number | null;
}) {
  if (!io) return;
  const payload = {
    event: 'rider:location_update',
    data: {
      riderId: params.riderId,
      orderId: params.orderId,
      latitude: params.latitude,
      longitude: params.longitude,
      destinationLat: params.destinationLat ?? null,
      destinationLon: params.destinationLon ?? null,
      timestamp: new Date().toISOString(),
    },
  };
  if (isUserOnline(params.customerId)) {
    io.to(`user:${params.customerId}`).emit('rider:location_update', payload);
  } else {
    queueEvent(params.customerId, 'rider:location_update', payload);
  }
}

export function emitDeliveryRequest(riderId: string, payload: {
  orderId: string;
  restaurantName: string;
  restaurantAddress: string;
  customerAddress: string;
  deliveryFee: number;
  estimatedDistance: number;
  expiresAt: string;
}) {
  if (!io) return;
  const wrapped = { event: 'delivery:request', data: payload };
  if (isUserOnline(riderId)) {
    io.to(`user:${riderId}`).emit('delivery:request', wrapped);
  } else {
    queueEvent(riderId, 'delivery:request', wrapped);
  }
}

export function emitSearchingRider(params: {
  customerId: string;
  restaurantOwnerId: string;
  orderId: string;
  retryCount: number;
  maxRetries: number;
}) {
  if (!io) return;
  const payload = {
    event: 'order:searching_rider',
    data: {
      orderId: params.orderId,
      message: 'Looking for a rider, please wait...',
      retryCount: params.retryCount,
      maxRetries: params.maxRetries,
      timestamp: new Date().toISOString(),
    },
  };
  // Notify customer
  if (isUserOnline(params.customerId)) {
    io.to(`user:${params.customerId}`).emit('order:searching_rider', payload);
  } else {
    queueEvent(params.customerId, 'order:searching_rider', payload);
  }
  // Notify restaurant
  if (isUserOnline(params.restaurantOwnerId)) {
    io.to(`user:${params.restaurantOwnerId}`).emit('order:searching_rider', payload);
  } else {
    queueEvent(params.restaurantOwnerId, 'order:searching_rider', payload);
  }
}

export function emitDisputeResolved(customerId: string, payload: {
  disputeId: string;
  orderId: string;
  resolution: string;
  refundAmount?: number;
  adminNotes?: string;
}) {
  if (!io) return;
  const wrapped = {
    event: 'dispute:resolved',
    data: { ...payload, timestamp: new Date().toISOString() },
  };
  if (isUserOnline(customerId)) {
    io.to(`user:${customerId}`).emit('dispute:resolved', wrapped);
  } else {
    queueEvent(customerId, 'dispute:resolved', wrapped);
  }
}

export function emitChatMessage(recipientId: string, payload: {
  orderId: string;
  messageId: string;
  senderId: string;
  message: string;
  createdAt: string;
}) {
  if (!io) return;
  const wrapped = { event: 'chat:message', data: payload };
  if (isUserOnline(recipientId)) {
    io.to(`user:${recipientId}`).emit('chat:message', wrapped);
  } else {
    queueEvent(recipientId, 'chat:message', wrapped);
  }
}

export function emitOrderAcceptanceRequest(restaurantOwnerId: string, order: Order) {
  if (!io) return;
  const wrapped = {
    event: 'order:acceptance_request',
    data: {
      orderId: order.id,
      order,
      acceptanceDeadline: (order as unknown as Record<string, unknown>).acceptance_deadline ?? null,
      timestamp: new Date().toISOString(),
    },
  };
  if (isUserOnline(restaurantOwnerId)) {
    io.to(`user:${restaurantOwnerId}`).emit('order:acceptance_request', wrapped);
  } else {
    queueEvent(restaurantOwnerId, 'order:acceptance_request', wrapped);
  }
}

// ── Admin broadcast ───────────────────────────────────────────────────────────
// Emits to all connected sockets whose role is 'admin'

export function emitAdminAlert(payload: {
  type: 'stuck_order' | 'dispute_opened';
  orderId?: string;
  message: string;
}) {
  if (!io) return;
  const wrapped = {
    event: 'admin:alert',
    data: { ...payload, timestamp: new Date().toISOString() },
  };
  // Broadcast to all sockets in the admin role room
  io.to('role:admin').emit('admin:alert', wrapped);
}

export function getIo(): Server {
  return io;
}
