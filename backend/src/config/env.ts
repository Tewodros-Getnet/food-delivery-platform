import dotenv from 'dotenv';
dotenv.config();

export const env = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: parseInt(process.env.PORT || '3000', 10),
  DATABASE_URL: process.env.DATABASE_URL || '',
  JWT_SECRET: process.env.JWT_SECRET || '',
  JWT_EXPIRY: process.env.JWT_EXPIRY || '15m',
  REFRESH_TOKEN_EXPIRY: process.env.REFRESH_TOKEN_EXPIRY || '7d',
  CHAPA_SECRET_KEY: process.env.CHAPA_SECRET_KEY || '',
  CHAPA_WEBHOOK_SECRET: process.env.CHAPA_WEBHOOK_SECRET || '',
  CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME || '',
  CLOUDINARY_API_KEY: process.env.CLOUDINARY_API_KEY || '',
  CLOUDINARY_API_SECRET: process.env.CLOUDINARY_API_SECRET || '',
  FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID || '',
  FIREBASE_PRIVATE_KEY: process.env.FIREBASE_PRIVATE_KEY || '',
  FIREBASE_CLIENT_EMAIL: process.env.FIREBASE_CLIENT_EMAIL || '',
  RIDER_SEARCH_RADIUS_KM: parseFloat(process.env.RIDER_SEARCH_RADIUS_KM || '5'),
  RIDER_TIMEOUT_SECONDS: parseInt(process.env.RIDER_TIMEOUT_SECONDS || '60', 10),
  DISPATCH_MAX_DURATION_MINUTES: parseInt(process.env.DISPATCH_MAX_DURATION_MINUTES || '10', 10),
  DELIVERY_BASE_FEE: parseFloat(process.env.DELIVERY_BASE_FEE || '5.00'),
  DELIVERY_RATE_PER_KM: parseFloat(process.env.DELIVERY_RATE_PER_KM || '2.00'),
  CHAPA_PUBLIC_KEY: process.env.CHAPA_PUBLIC_KEY || '',
  USE_CLOUDINARY: process.env.USE_CLOUDINARY === 'true',
  CHAPA_BASE_URL: process.env.CHAPA_BASE_URL || 'https://api.chapa.co/v1',
  ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://localhost:3001',
  APP_DEEP_LINK_BASE: process.env.APP_DEEP_LINK_BASE || 'fooddelivery://app',
};
