import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { logger } from '../utils/logger';
import { Order } from '../models/order.model';

let io: Server;

export function initSocketServer(socketServer: Server) {
  io = socketServer;

  // JWT auth middleware for socket connections
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

  io.on('connection', (socket: Socket) => {
    const userId = socket.data.userId as string;
    void socket.join(`user:${userId}`);
    logger.info('Socket connected', { socketId: socket.id, userId });

    socket.on('disconnect', () => {
      logger.info('Socket disconnected', { socketId: socket.id, userId });
    });
  });
}

export function emitOrderStatusChanged(order: Order, targetUserId: string) {
  if (!io) return;
  io.to(`user:${targetUserId}`).emit('order:status_changed', {
    event: 'order:status_changed',
    data: {
      orderId: order.id,
      status: order.status,
      timestamp: new Date().toISOString(),
      order,
    },
  });
}

export function emitToRestaurant(restaurantOwnerId: string, order: Order) {
  if (!io) return;
  io.to(`user:${restaurantOwnerId}`).emit('order:status_changed', {
    event: 'order:status_changed',
    data: {
      orderId: order.id,
      status: order.status,
      timestamp: new Date().toISOString(),
      order,
    },
  });
}

export function emitRiderLocationUpdate(params: {
  riderId: string;
  orderId: string;
  customerId: string;
  latitude: number;
  longitude: number;
}) {
  if (!io) return;
  io.to(`user:${params.customerId}`).emit('rider:location_update', {
    event: 'rider:location_update',
    data: {
      riderId: params.riderId,
      orderId: params.orderId,
      latitude: params.latitude,
      longitude: params.longitude,
      timestamp: new Date().toISOString(),
    },
  });
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
  io.to(`user:${riderId}`).emit('delivery:request', {
    event: 'delivery:request',
    data: payload,
  });
}

export function emitDisputeResolved(customerId: string, payload: {
  disputeId: string;
  orderId: string;
  resolution: string;
  refundAmount?: number;
  adminNotes?: string;
}) {
  if (!io) return;
  io.to(`user:${customerId}`).emit('dispute:resolved', {
    event: 'dispute:resolved',
    data: { ...payload, timestamp: new Date().toISOString() },
  });
}

export function getIo(): Server {
  return io;
}
