// Feature: food-delivery-app
// Property 23: Search query matches case-insensitively
// Property 24: Listing endpoints return paginated results
// Property 56: Delivery fee calculated correctly
// Property 57: Distance calculated using Haversine formula

import fc from 'fast-check';
import { haversineDistance, calculateDeliveryFee } from '../utils/haversine';

// ── Property 57 ──────────────────────────────────────────────────────────────

describe('Property 57: Distance calculated using Haversine formula', () => {
  test('same coordinates return 0 distance', () => {
    expect(haversineDistance(9.03, 38.74, 9.03, 38.74)).toBe(0);
  });

  test('distance is always non-negative', () => {
    fc.assert(
      fc.property(
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        (lat1, lon1, lat2, lon2) => {
          expect(haversineDistance(lat1, lon1, lat2, lon2)).toBeGreaterThanOrEqual(0);
        }
      ),
      { numRuns: 100 }
    );
  });

  test('distance is symmetric', () => {
    fc.assert(
      fc.property(
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        (lat1, lon1, lat2, lon2) => {
          const d1 = haversineDistance(lat1, lon1, lat2, lon2);
          const d2 = haversineDistance(lat2, lon2, lat1, lon1);
          expect(Math.abs(d1 - d2)).toBeLessThan(0.0001);
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ── Property 56 ──────────────────────────────────────────────────────────────

describe('Property 56: Delivery fee calculated correctly', () => {
  test('fee = base_fee + (distance_km * rate_per_km)', () => {
    fc.assert(
      fc.property(
        fc.float({ min: 0, max: 50, noNaN: true }),
        fc.float({ min: 0, max: 10, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        (baseFee, ratePerKm, lat1, lon1, lat2, lon2) => {
          const fee = calculateDeliveryFee(lat1, lon1, lat2, lon2, baseFee, ratePerKm);
          const distance = haversineDistance(lat1, lon1, lat2, lon2);
          const expected = Math.round((baseFee + distance * ratePerKm) * 100) / 100;
          expect(fee).toBe(expected);
        }
      ),
      { numRuns: 100 }
    );
  });

  test('fee is always >= base_fee', () => {
    fc.assert(
      fc.property(
        fc.float({ min: 0, max: 50, noNaN: true }),
        fc.float({ min: 0, max: 10, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        (baseFee, ratePerKm, lat1, lon1, lat2, lon2) => {
          const fee = calculateDeliveryFee(lat1, lon1, lat2, lon2, baseFee, ratePerKm);
          expect(fee).toBeGreaterThanOrEqual(baseFee - 0.01); // rounding tolerance
        }
      ),
      { numRuns: 100 }
    );
  });
});
