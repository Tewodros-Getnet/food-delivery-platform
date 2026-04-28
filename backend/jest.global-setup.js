// Global setup: apply missing migrations to the test database before any tests run
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '.env.test') });

const { Pool } = require('pg');

module.exports = async function globalSetup() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });

  const migrations = [
    '../database/migrations/004_inconsistencies_fix.sql',
    '../database/migrations/005_restaurant_riders.sql',
    '../database/migrations/005_bug_fixes.sql',
    '../database/migrations/006_email_verification.sql',
    '../database/migrations/007_restaurant_cancellation.sql',
    '../database/migrations/008_chat_messages.sql',
    '../database/migrations/009_order_acceptance.sql',
    '../database/migrations/010_menu_modifiers.sql',
    '../database/migrations/011_rating_replies.sql',
    '../database/migrations/012_promotional_banners.sql',
    '../database/migrations/013_favorites.sql',
  ];

  for (const rel of migrations) {
    const filePath = path.resolve(__dirname, rel);
    if (!fs.existsSync(filePath)) continue;
    const sql = fs.readFileSync(filePath, 'utf8');
    try {
      await pool.query(sql);
      console.log(`[globalSetup] Applied: ${path.basename(filePath)}`);
    } catch (err) {
      // Idempotent migrations may warn on re-run — log but don't fail
      console.warn(`[globalSetup] ${path.basename(filePath)}: ${err.message.split('\n')[0]}`);
    }
  }

  await pool.end();
};
