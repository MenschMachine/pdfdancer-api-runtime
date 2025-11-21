#!/bin/bash

# Apply ClickHouse schema migration scripts
# Usage: ./scripts/apply-clickhouse-migration.sh <migration-file.sql>

set -e

MIGRATION_FILE="$1"

if [ -z "$MIGRATION_FILE" ]; then
    echo "Error: Migration file required"
    echo "Usage: $0 <migration-file.sql>"
    exit 1
fi

if [ ! -f "$MIGRATION_FILE" ]; then
    echo "Error: Migration file not found: $MIGRATION_FILE"
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# ClickHouse connection details
CH_HOST="${CLICKHOUSE_HOST:-localhost}"
CH_PORT="${CLICKHOUSE_PORT:-8123}"
CH_USER="${CLICKHOUSE_USER:-default}"
CH_PASSWORD="${CLICKHOUSE_PASSWORD}"
CH_DB="${CLICKHOUSE_DB:-pdfdancer}"

echo "Applying migration: $MIGRATION_FILE"
echo "ClickHouse: $CH_USER@$CH_HOST:$CH_PORT/$CH_DB"

# Check if running in Docker
CONTAINER_NAME="${CLICKHOUSE_CONTAINER:-pdfdancer-clickhouse}"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Using Docker container: $CONTAINER_NAME"
    docker exec -i "$CONTAINER_NAME" clickhouse-client \
        --database "$CH_DB" \
        --multiquery < "$MIGRATION_FILE"
    EXIT_CODE=$?
elif command -v clickhouse-client &> /dev/null; then
    # Use clickhouse-client if available
    if [ -n "$CH_PASSWORD" ]; then
        clickhouse-client \
            --host "$CH_HOST" \
            --port 9000 \
            --user "$CH_USER" \
            --password "$CH_PASSWORD" \
            --database "$CH_DB" \
            --multiquery < "$MIGRATION_FILE"
    else
        clickhouse-client \
            --host "$CH_HOST" \
            --port 9000 \
            --user "$CH_USER" \
            --database "$CH_DB" \
            --multiquery < "$MIGRATION_FILE"
    fi
    EXIT_CODE=$?
else
    # Fallback to curl with HTTP interface
    if [ -n "$CH_PASSWORD" ]; then
        AUTH_PARAM="--user $CH_USER:$CH_PASSWORD"
    else
        AUTH_PARAM=""
    fi

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        $AUTH_PARAM \
        "http://$CH_HOST:$CH_PORT/" \
        --data-binary @"$MIGRATION_FILE")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 200 ]; then
        EXIT_CODE=0
        echo "$BODY"
    else
        EXIT_CODE=1
        echo "Error: HTTP $HTTP_CODE"
        echo "$BODY"
    fi
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "Migration applied successfully"
else
    echo "Migration failed"
    exit 1
fi
