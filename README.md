# PDFDancer API Runtime

Docker Compose bundle for running the PDFDancer API with a Caddy edge, blue/green API containers, and optional ClickHouse analytics. This repo is meant to be a drop-in runtime: bring your env vars/secrets, pull the GHCR images, and go.

## Services
- `caddy` – TLS/HTTP entrypoint that forwards to the active API container.
- `green` / `blue` – PDFDancer API containers (blue/green switch controlled by `COMPOSE_PROFILES` / `run.sh`).
- `clickhouse` – optional analytics database used by the API for metrics.

Default ports: `80`/`443` (Caddy), `8080` (blue), `8081` (green), `5005/5006` (debug), `8123`/`9000` (ClickHouse).

## Prerequisites
- Docker & Docker Compose.
- Access to GHCR images `ghcr.io/menschmachine/pdfdancer-api` (set `GITHUB_ACTOR` and `GITHUB_TOKEN` in `.env`).
- Fonts directory if you want custom fonts mounted into the API (`./fonts` → `/home/app/fonts`).

## Quick start
```bash
# Pull + start the default (green) stack
./run.sh

# Or explicitly choose an image tag (blue/green/main/sha)
./run.sh blue
./run.sh main

# Only pull, do not start containers
./run.sh --pull main
```

What the script does:
1) Loads `.env` (GHCR credentials, domain, ClickHouse creds, etc).  
2) Pulls `ghcr.io/menschmachine/pdfdancer-api:<tag>` and retags to match the service if needed.  
3) Starts Compose; when tag ≠ `blue`, it stops the blue service to keep a single active API.

To run Compose manually: `docker compose up -d` (set `COMPOSE_PROFILES=blue-enabled` if you want both blue and green up).

## Environment
Create `.env` with the values you need. Common keys:
- `GITHUB_ACTOR` / `GITHUB_TOKEN` – GHCR pull auth.
- `DOMAIN` – Caddy domain (defaults to `http://localhost`).
- `BACKEND_API_URL` – backend target for Caddy; `run.sh` sets this automatically to the active service.
- `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE` – used by ClickHouse container and migration scripts.
- `FONTS_DIR` – optional host path for fonts (defaults to `./fonts`).
- `LOGBACK_XML_FILE` – override the bundled `conf/logback.xml` if needed.
- Any other PDFDancer application env vars required by your deployment.

## Data & volumes
- Fonts: `./fonts` → `/home/app/fonts`
- Config: `./conf` (read-only inside containers)
- Tenants DB: `db-tenants` volume
- Fonts DB cache: `db-fonts` volume
- Session data: `session-data` volume
- ClickHouse data: `clickhouse-data` volume
- Caddy state: `caddy-data` volume

## ClickHouse migrations (analytics)
- Primary schema: `scripts/clickhouse-init.sql`
- Incremental migrations: `scripts/clickhouse-*.sql`
- Runner: `scripts/apply-clickhouse-migrations.sh`

Example:
```bash
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_USER=default
export CLICKHOUSE_PASSWORD=secret
./scripts/apply-clickhouse-migrations.sh
```

## Tenant bootstrap
Use `tenant-add.sh` to create a tenant, user, and API token in the SQLite tenant DB.
```bash
./tenant-add.sh \
  --db ./db/tenants/tenants.db \
  --name "Acme Inc" \
  --slug acme \
  --plan PRO \
  --user-email admin@acme.com \
  --user-name "Acme Admin"
```
The script prints the raw token once—store it securely.

## Troubleshooting
- Check health: `curl -f http://localhost:8081/ping` (green) or `curl -f http://localhost:8080/ping` (blue).
- Logs: `docker compose logs -f caddy` or `docker compose logs -f green`.
- Switch traffic: rerun `./run.sh blue` or `./run.sh main` to swap the active image.
- Stop stack: `docker compose down`.
