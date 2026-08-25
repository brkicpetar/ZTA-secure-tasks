# Secure Tasks — Zero Trust Project

Initial application layer for the Zero Trust architecture project.

## Services

- frontend: http://localhost:3000
- backend: http://localhost:4000
- auth-service: http://localhost:4001
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

## Security demos

1. Access `/tasks` without a bearer token → 401.
2. Login as `petar` and call `/admin` → 403.
3. Login as `admin` and call `/admin` → 200.

The Kubernetes layer will later add default-deny network segmentation, Kubernetes RBAC, Kyverno policy enforcement, and monitoring.
