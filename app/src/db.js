const { Pool } = require('pg');

let pool = null;

/**
 * Returns the singleton pg Pool instance.
 * The pool is only created if DB connection env vars are present.
 */
function getPool() {
  if (!process.env.DB_HOST && !process.env.DATABASE_URL) {
    return null;
  }

  if (!pool) {
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT, 10) || 5432,
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 3000,
    });

    pool.on('error', (err) => {
      console.error('[ERROR] Unexpected DB pool error:', err.message);
    });
  }

  return pool;
}

module.exports = { getPool };
