const express = require('express');
const router = express.Router();

/**
 * GET /health
 * Liveness probe – confirms the app process is running.
 */
router.get('/health', (req, res) => {
  console.log('[INFO] Health check requested');
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

module.exports = router;
