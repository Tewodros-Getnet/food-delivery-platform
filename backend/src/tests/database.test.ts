// Feature: food-delivery-app, Property 70: Multi-step operations use transactions
import fc from 'fast-check';
import { withTransaction, pool } from '../config/database';

describe('Property 70: Multi-step operations use transactions', () => {
  beforeAll(async () => {
    // Create a temp test table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS _tx_test (
        id SERIAL PRIMARY KEY,
        value TEXT NOT NULL
      )
    `);
  });

  afterAll(async () => {
    await pool.query('DROP TABLE IF EXISTS _tx_test');
    await pool.end();
  });

  afterEach(async () => {
    await pool.query('DELETE FROM _tx_test');
  });

  test('successful transaction commits all writes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 1, maxLength: 50 }),
        fc.string({ minLength: 1, maxLength: 50 }),
        async (val1, val2) => {
          await withTransaction(async (client) => {
            await client.query('INSERT INTO _tx_test (value) VALUES ($1)', [val1]);
            await client.query('INSERT INTO _tx_test (value) VALUES ($1)', [val2]);
          });

          const result = await pool.query('SELECT * FROM _tx_test');
          expect(result.rowCount).toBe(2);
          await pool.query('DELETE FROM _tx_test');
        }
      ),
      { numRuns: 20 }
    );
  });

  test('failed transaction rolls back all writes — no partial writes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 1, maxLength: 50 }),
        async (val1) => {
          await expect(
            withTransaction(async (client) => {
              await client.query('INSERT INTO _tx_test (value) VALUES ($1)', [val1]);
              // Force failure: violate NOT NULL constraint
              await client.query('INSERT INTO _tx_test (value) VALUES ($1)', [null]);
            })
          ).rejects.toThrow();

          // No rows should have been committed
          const result = await pool.query('SELECT * FROM _tx_test');
          expect(result.rowCount).toBe(0);
        }
      ),
      { numRuns: 20 }
    );
  });
});
