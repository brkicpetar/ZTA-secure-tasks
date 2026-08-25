# Secure Tasks — Zero Trust Project

Initial application layer for the Zero Trust architecture project.

## Services

- frontend: http://localhost:3000
- backend: http://localhost:4000
- auth-service: http://localhost:4001
- Grafana: http://localhost:3001
- Prometheus: http://localhost:9090
- redis: localhost:6379

## Demo users

- user: `petar / petar123`
- admin: `admin / admin123`

## Local run without Docker

Start Redis locally, then in three terminals:

```bash
cd auth-service
npm install
npm start
```

```bash
cd backend
npm install
npm start
```

```bash
cd frontend
npm install
npm start
```

Open http://localhost:3000.

## Run with Docker Compose

```bash
docker compose up --build
```

Then open http://localhost:3000.

## Run with K8s

```bash
./init.sh
./start.sh
```

Then open http://localhost:3000.
