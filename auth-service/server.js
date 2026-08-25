const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const app = express();

app.use(cors({
  origin: 'http://localhost:3000'
}));

app.use(express.json());

const PORT = process.env.PORT || 4001;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-change-me';

// Demo users. For the actual project, we'll later move identity storage out of code.
const users = [
  { id: 'u1', username: 'petar', password: 'petar123', role: 'user' },
  { id: 'a1', username: 'admin', password: 'admin123', role: 'admin' }
];

app.get('/health', (_req, res) => {
  res.json({ service: 'auth-service', status: 'ok' });
});

app.post('/login', (req, res) => {
  const { username, password } = req.body || {};

  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }

  const user = users.find(
    (candidate) => candidate.username === username && candidate.password === password
  );

  if (!user) {
    return res.status(401).json({ error: 'invalid credentials' });
  }

  const token = jwt.sign(
    { sub: user.id, username: user.username, role: user.role },
    JWT_SECRET,
    { expiresIn: '15m', issuer: 'secure-tasks-auth' }
  );

  res.json({ token, user: { id: user.id, username: user.username, role: user.role } });
});

app.listen(PORT, () => {
  console.log(`Auth service listening on http://localhost:${PORT}`);
});
