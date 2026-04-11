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
  missedEventQueue.get(userId)!.push({ event, payload, ts: now });

  // Schedule TTL cleanup
  setTimeout(() => {
    const queue = missedEventQueue.get(userId);
    if (!queue) return;
    const fresh = queue.filter(e => Date.now() - e.ts < MISSED_EVENT_TTL_MS);
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
    // Await join so the room exists before we flush queued events
    await socket.join(`user:${userId}`);
    logger.info('Socket connected', { socketId: socket.id, userId });

    // Deliver any events missed while offline
    flushQueue(socket, userId);

    socket.on('disconnect', async () => {
      logger.info('Socket disconnected', { socketId: socket.id, userId });
      await socket.leave(`user:${userId}`);
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
}) {
  if (!io) return;
  const payload = {
    event: 'rider:location_update',
    data: {
      riderId: params.riderId,
      orderId: params.orderId,
      latitude: params.latitude,
      longitude: params.longitude,
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

export function getIo(): Server {
  return io;
}
