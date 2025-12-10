const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const API_BASE = process.env.API_BASE || 'http://localhost:3000';

app.get('/config.js', (_req, res) => {
  res.type('application/javascript');
  res.send(`window.__CONFIG__ = ${JSON.stringify({ apiBase: API_BASE })};`);
});

app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, () => {
  console.log(`Frontend listening on port ${PORT}`);
});
