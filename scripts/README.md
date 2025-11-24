# ClickHouse Migration Scripts

This directory contains SQL migration scripts and tools for managing the ClickHouse analytics database schema.

## Files

- **clickhouse-init.sql** - Initial database schema (includes all columns)
- **clickhouse-add-region-tracking.sql** - Migration to add region tracking columns (for existing installations)
- **apply-clickhouse-migrations.sh** - Automated migration tool

## Quick Start

### Default Connection (localhost)

```bash
./scripts/apply-clickhouse-migrations.sh
```

### Custom Connection

```bash
export CLICKHOUSE_HOST=clickhouse.example.com
export CLICKHOUSE_PORT=8123
export CLICKHOUSE_USER=admin
export CLICKHOUSE_PASSWORD=secret
export CLICKHOUSE_DATABASE=pdfdancer

./scripts/apply-clickhouse-migrations.sh
```

## Usage Examples

### Local Development

```bash
# Default settings (localhost:8123, user: default, no password)
./scripts/apply-clickhouse-migrations.sh
```

### Docker Compose

```bash
# Connect to ClickHouse in Docker
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=8123
./scripts/apply-clickhouse-migrations.sh
```

### Production Deployment

```bash
# Using environment variables from your deployment
export CLICKHOUSE_HOST=prod-clickhouse.internal
export CLICKHOUSE_PORT=8123
export CLICKHOUSE_USER=pdfdancer_admin
export CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD}"  # From secrets
export CLICKHOUSE_DATABASE=pdfdancer

./scripts/apply-clickhouse-migrations.sh
```

### CI/CD Pipeline

```yaml
# Example GitHub Actions / GitLab CI
steps:
  - name: Apply ClickHouse migrations
    env:
      CLICKHOUSE_HOST: ${{ secrets.CLICKHOUSE_HOST }}
      CLICKHOUSE_USER: ${{ secrets.CLICKHOUSE_USER }}
      CLICKHOUSE_PASSWORD: ${{ secrets.CLICKHOUSE_PASSWORD }}
    run: |
      chmod +x scripts/apply-clickhouse-migrations.sh
      ./scripts/apply-clickhouse-migrations.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_HOST` | `localhost` | ClickHouse server hostname |
| `CLICKHOUSE_PORT` | `8123` | ClickHouse HTTP port |
| `CLICKHOUSE_USER` | `default` | Database user |
| `CLICKHOUSE_PASSWORD` | (empty) | Database password |
| `CLICKHOUSE_DATABASE` | `pdfdancer` | Target database name |

## Migration Behavior

The script is **idempotent** and safe to run multiple times:

1. **New Installation**: Applies `clickhouse-init.sql` to create all tables and columns
2. **Existing Installation**: Checks for missing columns and applies migrations as needed
3. **Up-to-Date**: Does nothing if schema is already current

### What It Does

1. ✅ Tests connection to ClickHouse
2. ✅ Creates database if it doesn't exist
3. ✅ Checks if `metrics_events` table exists
   - **If NO**: Runs full schema setup
   - **If YES**: Checks for region tracking columns
4. ✅ Applies migrations only if needed
5. ✅ Verifies all expected columns are present

## Manual Migration

If you prefer to apply migrations manually:

### Initial Setup

```bash
clickhouse-client --host localhost --query "$(cat scripts/clickhouse-init.sql)"
```

### Add Region Tracking (Existing Installations)

```bash
clickhouse-client --host localhost --query "$(cat scripts/clickhouse-add-region-tracking.sql)"
```

### Using HTTP API

```bash
# Initial setup
curl -X POST 'http://localhost:8123/' \
  -H 'X-ClickHouse-Database: pdfdancer' \
  --data-binary @scripts/clickhouse-init.sql

# Or migration
curl -X POST 'http://localhost:8123/' \
  -H 'X-ClickHouse-Database: pdfdancer' \
  --data-binary @scripts/clickhouse-add-region-tracking.sql
```

## Verifying Schema

After migration, verify the schema:

```bash
# Check columns
clickhouse-client --query "DESCRIBE pdfdancer.metrics_events"

# Check region tracking columns specifically
clickhouse-client --query "
  SELECT name, type, comment
  FROM system.columns
  WHERE database = 'pdfdancer'
    AND table = 'metrics_events'
    AND name IN ('client_country', 'client_region', 'cloudflare_ray')
"
```

## Troubleshooting

### Connection Failed

```bash
# Test ClickHouse is running
curl http://localhost:8123/ping

# Check if database exists
echo "SHOW DATABASES" | curl 'http://localhost:8123/' --data-binary @-
```

### Permission Denied

Ensure the user has proper permissions:

```sql
-- Grant necessary permissions
GRANT CREATE, INSERT, SELECT ON pdfdancer.* TO pdfdancer_user;
```

### Schema Verification Failed

If columns are missing after migration:

1. Check ClickHouse logs for errors
2. Verify user has ALTER TABLE permissions
3. Try running migrations manually
4. Check ClickHouse version compatibility

## Schema Details

### Region Tracking Columns

The migration adds three columns to `metrics_events`:

| Column | Type | Description |
|--------|------|-------------|
| `client_country` | `Nullable(String)` | ISO 3166-1 alpha-2 country code from CF-IPCountry header |
| `client_region` | `Nullable(String)` | Mapped region: EU, US, APAC, or OTHER (XX) |
| `cloudflare_ray` | `Nullable(String)` | Cloudflare Ray ID for request tracing |

### Example Queries

```sql
-- Requests by region (last 24 hours)
SELECT
    client_region,
    COUNT(*) as requests
FROM pdfdancer.metrics_events
WHERE timestamp >= now() - INTERVAL 24 HOUR
GROUP BY client_region
ORDER BY requests DESC;

-- Top countries
SELECT
    client_country,
    client_region,
    COUNT(*) as requests
FROM pdfdancer.metrics_events
WHERE event_type = 'API_REQUEST'
GROUP BY client_country, client_region
ORDER BY requests DESC
LIMIT 20;

-- Traffic by region over time
SELECT
    toStartOfHour(timestamp) as hour,
    client_region,
    COUNT(*) as requests
FROM pdfdancer.metrics_events
WHERE timestamp >= now() - INTERVAL 7 DAY
GROUP BY hour, client_region
ORDER BY hour DESC, requests DESC;
```

## Support

For issues or questions:
- Check ClickHouse logs: `docker logs <clickhouse-container>`
- Verify connectivity: `curl http://localhost:8123/ping`
- Consult ClickHouse documentation: https://clickhouse.com/docs
