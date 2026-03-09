const express = require('express');
const router = express.Router();

/**
 * POST /process
 * Accepts a JSON payload and echoes it back with metadata.
 */
router.post('/process', (req, res) => {
  const body = req.body;

  if (!body || Object.keys(body).length === 0) {
    return res.status(400).json({ error: 'Request body must not be empty' });
  }

  console.log('[INFO] Processing request:', JSON.stringify(body));

  res.status(200).json({
    status: 'processed',
    receivedAt: new Date().toISOString(),
    data: body,
  });
});

module.exports = router;
