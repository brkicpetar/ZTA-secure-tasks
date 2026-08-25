const path = require('path');
const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, 'public')));

app.get('/health', (_req, res) => {
  res.json({ service: 'frontend', status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`Frontend listening on http://localhost:${PORT}`);
});
