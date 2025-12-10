const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.PORT || 8080;
const CUSTOMER_FACING_URL = process.env.CUSTOMER_FACING_URL || 'http://customer-facing:80';

// Proxy API requests to customer-facing service
app.use('/api', createProxyMiddleware({
  target: CUSTOMER_FACING_URL,
  changeOrigin: true,
  pathRewrite: {
    '^/api': '', // Remove /api prefix when forwarding
  },
  onProxyReq: (proxyReq, req, res) => {
    console.log(`Proxying ${req.method} ${req.url} to ${CUSTOMER_FACING_URL}`);
  },
  onError: (err, req, res) => {
    console.error('Proxy error:', err);
    res.status(500).json({ error: 'Failed to connect to backend service' });
  }
}));

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, () => {
  console.log(`Frontend listening on port ${PORT}`);
  console.log(`Proxying /api/* requests to ${CUSTOMER_FACING_URL}`);
});
