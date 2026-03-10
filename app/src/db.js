const { Pool } = require('pg');
const { env } = require('./config/env');

let pool = null;

/**
 * Returns the singleton pg Pool instance.
 * The pool is only created if DB connection env vars are present.
 */
function getPool() {
  if (!env.DB_HOST && !env.DATABASE_URL) {
    return null;
  }

  if (!pool) {
    pool = new Pool({
      connectionString: env.DATABASE_URL,
      host: env.DB_HOST,
      port: parseInt(env.DB_PORT, 10) || 5432,
      database: env.DB_NAME,
      user: env.DB_USER,
      password: env.DB_PASSWORD,
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
