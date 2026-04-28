# Local Docker Compose

This project includes a local development stack in `docker-compose.yml`.

## Included services

- `postgres`
- `temporal`
- `temporal-ui`
- `api`
- `worker`

## Startup

```bash
docker compose up -d
```

## Useful endpoints

- API container app port: `http://localhost:3000`
- Temporal gRPC: `localhost:7233`
- Temporal UI: `http://localhost:8088`
- Postgres: `localhost:5432`

## Notes

This is a development scaffold.

At the moment it assumes:
- local Go execution inside the API and worker containers
- Postgres credentials suitable for local use
- Temporal auto-setup for quick startup

Later improvements may include:
- a migration runner
- a prebuilt application image
- Makefile helpers
- seed data or local test fixtures
