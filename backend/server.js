const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const { createClient } = require('redis');
const client = require('prom-client');

client.collectDefaultMetrics();

const httpRequestsTotal = new client.Counter({
  name: 'secure_tasks_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const app = express();
app.use(cors({
  origin: 'http://localhost:3000'
}));
app.use(express.json())
app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequestsTotal.inc({
      method: req.method,
      route: req.route?.path || req.path,
      status: res.statusCode
    });
  });

  next();
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-change-me';
const JWT_ISSUER = 'secure-tasks-auth';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

const redis = createClient({ url: REDIS_URL });
redis.on('error', (err) => console.error('Redis error:', err.message));

async function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'missing or invalid bearer token' });
  }

  try {
    req.user = jwt.verify(token, JWT_SECRET, { issuer: JWT_ISSUER });
    next();
  } catch (_err) {
    return res.status(401).json({ error: 'invalid or expired token' });
  }
}

function requireRole(role) {
  return (req, res, next) => {
    if (req.user?.role !== role) {
      return res.status(403).json({ error: 'forbidden' });
    }
    next();
  };
}

async function getTasks(userId) {
  const raw = await redis.get(`tasks:${userId}`);
  return raw ? JSON.parse(raw) : [];
}

async function saveTasks(userId, tasks) {
  await redis.set(`tasks:${userId}`, JSON.stringify(tasks));
}

app.get('/health', async (_req, res) => {
  try {
    const redisStatus = redis.isReady ? 'ok' : 'not-ready';
    res.json({ service: 'backend', status: 'ok', redis: redisStatus });
  } catch (_err) {
    res.status(500).json({ service: 'backend', status: 'error' });
  }
});

app.get('/tasks', authenticate, async (req, res) => {
  try {
    const tasks = await getTasks(req.user.sub);
    res.json({ user: req.user.username, tasks });
  } catch (_err) {
    res.status(500).json({ error: 'failed to load tasks' });
  }
});

app.post('/tasks', authenticate, async (req, res) => {
  const title = typeof req.body?.title === 'string' ? req.body.title.trim() : '';

  if (!title || title.length > 120) {
    return res.status(400).json({ error: 'title must be 1-120 characters' });
  }

  try {
    const tasks = await getTasks(req.user.sub);
    const task = {
      id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
      title,
      createdAt: new Date().toISOString()
    };

    tasks.push(task);
    await saveTasks(req.user.sub, tasks);
    res.status(201).json(task);
  } catch (_err) {
    res.status(500).json({ error: 'failed to create task' });
  }
});

app.get('/admin', authenticate, requireRole('admin'), async (_req, res) => {
  try {
    const keys = await redis.keys('tasks:*');
    res.json({ message: 'admin access granted', taskBuckets: keys.length });
  } catch (_err) {
    res.status(500).json({ error: 'failed to load admin data' });
  }
});

async function start() {
  await redis.connect();
  app.listen(PORT, () => {
    console.log(`Backend listening on http://localhost:${PORT}`);
  });
}

start().catch((err) => {
  console.error('Failed to start backend:', err);
  process.exit(1);
});
