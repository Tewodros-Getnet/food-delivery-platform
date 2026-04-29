import 'dotenv/config';
import http from 'http';
import { Server } from 'socket.io';
import app from './app';
import { env } from './config/env';
import { pool } from './config/database';
import { logger } from './utils/logger';
import { startPaymentExpiryJob, startAcceptanceTimeoutJob, startOperatingHoursJob, startTokenCleanupJob, startStuckOrderAlertJob } from './services/scheduler.service';
import { initSocketServer } from './services/socket.service';
import { recoverDispatchSessions } from './services/rider.service';

const server = http.createServer(app);

export const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

initSocketServer(io);

async function start() {
  try {
    await pool.query('SELECT 1');
    logger.info('Database connection established');
  } catch (err) {
    logger.error('Failed to connect to database', { error: String(err) });
    process.exit(1);
  }

  await recoverDispatchSessions();

  server.listen(env.PORT, () => {
    logger.info(`Server running on port ${env.PORT}`, { env: env.NODE_ENV });
    startPaymentExpiryJob();
    startAcceptanceTimeoutJob();
    startOperatingHoursJob();
    startTokenCleanupJob();
    startStuckOrderAlertJob();
  });
}

start();
