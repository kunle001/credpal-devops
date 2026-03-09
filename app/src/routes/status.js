const express = require('express');
const router = express.Router();

/**
 * GET /status
 * Readiness probe – reports app version, environment, and dependency states.
 */
router.get('/status', async (req, res) => {
  console.log('[INFO] Status check requested');

  const dbStatus = await checkDatabase();

  res.status(200).json({
    status: 'ok',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    dependencies: {
      database: dbStatus,
    },
  });
});

async function checkDatabase() {
  // Skip DB check if no connection string is configured (e.g., in unit tests)
  if (!process.env.DATABASE_URL && !process.env.DB_HOST) {
    return { status: 'not_configured' };
  }

  try {
    const { Pool } = require('pg');
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      host: process.env.DB_HOST,
      port: process.env.DB_PORT || 5432,
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      connectionTimeoutMillis: 3000,
    });

    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    await pool.end();
    return { status: 'connected' };
  } catch (err) {
    console.error('[ERROR] Database health check failed:', err.message);
    return { status: 'unreachable', error: err.message };
  }
}

module.exports = router;
