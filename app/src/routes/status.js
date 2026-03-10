const express = require('express');
const { getPool } = require('../db');
const { env } = require('../config/env');

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
    version: env.APP_VERSION || '1.0.0',
    environment: env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    dependencies: {
      database: dbStatus,
    },
  });
});

async function checkDatabase() {
  const pool = getPool();

  if (!pool) {
    return { status: 'not_configured' };
  }

  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    return { status: 'connected' };
  } catch (err) {
    console.error('[ERROR] Database health check failed:', err.message);
    return { status: 'unreachable', error: err.message };
  }
}

module.exports = router;
