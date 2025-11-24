#!/bin/bash
set -e

# ClickHouse Migration Script
# Applies schema migrations to a ClickHouse instance


# Resolve the directory where the script itself is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parent directory of the script
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# File you want to check
TARGET_FILE="$PARENT_DIR/.env"

# Test & source
if [[ -f "$TARGET_FILE" ]]; then
    source "$TARGET_FILE"
else
    echo "File not found: $TARGET_FILE"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default connection parameters (can be overridden via env vars)
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-default}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"
CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-pdfdancer}"
CLICKHOUSE_TCP_PORT="${CLICKHOUSE_TCP_PORT:-9000}"


echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         ClickHouse Migration Tool - PDFDancer API             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Build ClickHouse connection URL
if [ -n "$CLICKHOUSE_PASSWORD" ]; then
    CLICKHOUSE_URL="http://${CLICKHOUSE_USER}:${CLICKHOUSE_PASSWORD}@${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}"
else
    CLICKHOUSE_URL="http://${CLICKHOUSE_USER}@${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}"
fi

# Function to execute SQL via HTTP
execute_sql() {
    local sql="$1"
    local description="$2"

    echo -e "${YELLOW}➜${NC} ${description}..."

    # Execute SQL and capture response
    response=$(curl -sSf "${CLICKHOUSE_URL}/" \
        --data-binary "$sql" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}" 2>&1) || {
        echo -e "${RED}✗ Failed: ${description}${NC}"
        echo -e "${RED}Error: ${response}${NC}"
        return 1
    }

    echo -e "${GREEN}✓ Success: ${description}${NC}"
    return 0
}

# Function to execute SQL file
execute_sql_file() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ File not found: ${file}${NC}"
        return 1
    fi

    echo -e "${YELLOW}➜${NC} ${description}..."
    echo -e "   File: ${file}"

    # Read file and execute
    sql=$(<"$file")
    response=$(curl -sSf "${CLICKHOUSE_URL}/" \
        --data-binary "$sql" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}" 2>&1) || {
        echo -e "${RED}✗ Failed: ${description}${NC}"
        echo -e "${RED}Error: ${response}${NC}"
        return 1
    }

    echo -e "${GREEN}✓ Success: ${description}${NC}"
    return 0
}

# Function to execute SQL file with multiple statements
execute_sql_file_multi() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ File not found: ${file}${NC}"
        return 1
    fi

    echo -e "${YELLOW}➜${NC} ${description}..."
    echo -e "   File: ${file}"

    # Read file, remove comments and split by semicolons
    # Execute each statement separately
    local statement_num=0
    local sql_buffer=""
    while IFS= read -r line; do
        # Skip comment lines and empty lines
        [[ "$line" =~ ^[[:space:]]*-- ]] && continue
        [[ -z "${line// }" ]] && continue

        # Accumulate lines until we hit a semicolon
        sql_buffer="${sql_buffer}${line}"$'\n'

        if [[ "$line" =~ \;[[:space:]]*$ ]]; then
            # Found a statement, execute it
            ((statement_num++))

            response=$(curl -sSf "${CLICKHOUSE_URL}/" \
                --data-binary "$sql_buffer" \
                -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}" 2>&1) || {
                echo -e "${RED}✗ Failed: Statement ${statement_num}${NC}"
                echo -e "${RED}Error: ${response}${NC}"
                echo -e "${RED}SQL: ${sql_buffer}${NC}"
                return 1
            }

            echo -e "${GREEN}  ✓ Statement ${statement_num} executed${NC}"
            sql_buffer=""
        fi
    done < "$file"

    echo -e "${GREEN}✓ Success: ${description} (${statement_num} statements)${NC}"
    return 0
}

# Create ASN dictionary with credentials (range-hashed for IPv4)
create_asn_dictionary() {
    local sql
    read -r -d '' sql <<EOF
CREATE DICTIONARY IF NOT EXISTS pdfdancer.asn_dict
(
    network    String,
    asn        String,
    as_name    String,
    as_domain  String
)
PRIMARY KEY network
SOURCE(CLICKHOUSE(
  HOST '${CLICKHOUSE_HOST}'
  PORT ${CLICKHOUSE_TCP_PORT}
  USER '${CLICKHOUSE_USER}'
  PASSWORD '${CLICKHOUSE_PASSWORD}'
  DATABASE '${CLICKHOUSE_DATABASE}'
  QUERY 'SELECT network, coalesce(asn, ''''), coalesce(as_name, ''''), coalesce(as_domain, '''') FROM pdfdancer.asn_ranges WHERE network NOT LIKE ''%:%'''
))
LAYOUT(IP_TRIE())
LIFETIME(0);
EOF

    execute_sql "$sql" "Create ASN dictionary"
}

# Check dictionary status and surface errors
check_asn_dictionary_status() {
    # Force a reload, then read status/exception
    execute_sql "SYSTEM RELOAD DICTIONARY pdfdancer.asn_dict" "Reload ASN dictionary" || return 1

    local status_row
    status_row=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT status, last_exception FROM system.dictionaries WHERE database = '${CLICKHOUSE_DATABASE}' AND name = 'asn_dict'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

    local status_code last_exception
    status_code=$(echo "$status_row" | awk '{print $1}')
    last_exception=$(echo "$status_row" | cut -d' ' -f2-)

    # status may be numeric or enum string (LOADED/NOT_LOADED)
    if [ -z "$status_code" ]; then
        echo -e "${RED}✗ Could not read dictionary status${NC}"
        return 1
    fi

    if [ "$status_code" = "1" ] || [[ "$status_code" =~ LOADED ]]; then
        echo -e "${GREEN}✓ ASN dictionary loaded${NC}"
        return 0
    fi

    echo -e "${RED}✗ ASN dictionary not loaded (status=${status_code})${NC}"
    if [ -n "$last_exception" ] && [ "$last_exception" != "NULL" ]; then
        echo -e "${RED}Last exception: ${last_exception}${NC}"
    fi
    return 1
}

# Check ClickHouse connectivity
echo -e "${BLUE}Connection Details:${NC}"
echo "  Host:     ${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}"
echo "  User:     ${CLICKHOUSE_USER}"
echo "  Database: ${CLICKHOUSE_DATABASE}"
echo "  TCP Port: ${CLICKHOUSE_TCP_PORT}"
echo ""

echo -e "${YELLOW}Testing connection...${NC}"
if execute_sql "SELECT 1" "Connection test"; then
    echo ""
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Failed to connect to ClickHouse                               ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Please check:"
    echo "  1. ClickHouse is running"
    echo "  2. Connection parameters are correct"
    echo "  3. Network connectivity"
    echo ""
    echo "Environment variables:"
    echo "  CLICKHOUSE_HOST=${CLICKHOUSE_HOST}"
    echo "  CLICKHOUSE_PORT=${CLICKHOUSE_PORT}"
    echo "  CLICKHOUSE_USER=${CLICKHOUSE_USER}"
    echo "  CLICKHOUSE_DATABASE=${CLICKHOUSE_DATABASE}"
    exit 1
fi

# Check if database exists, create if not
echo -e "${BLUE}Checking database...${NC}"
execute_sql "CREATE DATABASE IF NOT EXISTS ${CLICKHOUSE_DATABASE}" "Create database '${CLICKHOUSE_DATABASE}'" || exit 1
echo ""

# Check if metrics_events table exists
echo -e "${BLUE}Checking existing schema...${NC}"
table_exists=$(curl -sS "${CLICKHOUSE_URL}/" \
    --data-binary "SELECT count() FROM system.tables WHERE database = '${CLICKHOUSE_DATABASE}' AND name = 'metrics_events'" \
    -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

if [ "$table_exists" = "0" ]; then
    echo -e "${YELLOW}⚠ Table 'metrics_events' does not exist${NC}"
    echo -e "${BLUE}Running initial schema setup...${NC}"
    echo ""
    execute_sql_file "${SCRIPT_DIR}/clickhouse-init.sql" "Apply initial schema (clickhouse-init.sql)" || exit 1
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Initial schema setup completed successfully!                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${GREEN}✓ Table 'metrics_events' exists${NC}"

    # Check if region tracking migration is needed
    column_exists=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT count() FROM system.columns WHERE database = '${CLICKHOUSE_DATABASE}' AND table = 'metrics_events' AND name = 'client_country'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

    if [ "$column_exists" = "0" ]; then
        echo -e "${YELLOW}⚠ Region tracking columns not found${NC}"
        echo -e "${BLUE}Applying migration...${NC}"
        echo ""
        execute_sql_file "${SCRIPT_DIR}/clickhouse-add-region-tracking.sql" "Apply region tracking migration" || exit 1
        echo ""
    else
        echo -e "${GREEN}✓ Region tracking columns already exist${NC}"
    fi

    # Check if connecting_ip migration is needed
    connecting_ip_exists=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT count() FROM system.columns WHERE database = '${CLICKHOUSE_DATABASE}' AND table = 'metrics_events' AND name = 'connecting_ip'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

    if [ "$connecting_ip_exists" = "0" ]; then
        echo -e "${YELLOW}⚠ connecting_ip column not found${NC}"
        echo -e "${BLUE}Applying migration...${NC}"
        echo ""
        execute_sql_file "${SCRIPT_DIR}/clickhouse-add-connecting-ip.sql" "Apply CF-Connecting-IP migration" || exit 1
        echo ""
    else
        echo -e "${GREEN}✓ connecting_ip column already exists${NC}"
    fi

    # Check if ASN lookup tables are needed
    asn_table_exists=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT count() FROM system.tables WHERE database = '${CLICKHOUSE_DATABASE}' AND name = 'asn_ranges'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

    if [ "$asn_table_exists" = "0" ]; then
        echo -e "${YELLOW}⚠ ASN lookup tables not found${NC}"
        echo -e "${BLUE}Applying ASN lookup migration...${NC}"
        echo ""
        execute_sql_file_multi "${SCRIPT_DIR}/clickhouse-create-asn-lookup.sql" "Create ASN lookup tables" || exit 1
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Migration completed successfully!                            ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${GREEN}✓ ASN lookup tables already exist${NC}"
        # Ensure ASN dictionary exists even if tables were created earlier
    asn_dict_exists=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT count() FROM system.dictionaries WHERE database = '${CLICKHOUSE_DATABASE}' AND name = 'asn_dict'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

        if [ "$asn_dict_exists" = "0" ]; then
            echo -e "${YELLOW}⚠ ASN dictionary not found; creating${NC}"
            create_asn_dictionary || exit 1
        else
            dict_info=$(curl -sS "${CLICKHOUSE_URL}/" \
                --data-binary "SELECT type, status, last_exception FROM system.dictionaries WHERE database = '${CLICKHOUSE_DATABASE}' AND name = 'asn_dict'" \
                -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")
            dict_type=$(echo "$dict_info" | awk '{print $1}')
            dict_status=$(echo "$dict_info" | awk '{print $2}')
            dict_exception=$(echo "$dict_info" | cut -d' ' -f3-)

            if [ "$dict_type" != "Trie" ]; then
                echo -e "${YELLOW}⚠ ASN dictionary exists with type '${dict_type}', recreating as Trie${NC}"
                execute_sql "DROP DICTIONARY IF EXISTS pdfdancer.asn_dict" "Drop existing ASN dictionary" || exit 1
                create_asn_dictionary || exit 1
            else
                echo -e "${GREEN}✓ ASN dictionary exists (type=${dict_type}), reloading${NC}"
            fi
        fi

        if ! check_asn_dictionary_status; then
            echo -e "${RED}Dictionary reload failed. Verify CLICKHOUSE_TCP_PORT/USER/PASSWORD for native access.${NC}"
            exit 1
        fi
        # Smoke-test a lookup to surface connection/credential issues immediately
        if ! execute_sql "SELECT dictGet('pdfdancer.asn_dict','asn', toUInt32(IPv4StringToNum('52.173.108.16')))" "Test ASN dictionary lookup (52.173.108.16)"; then
            echo -e "${RED}Dictionary lookup failed. Verify native connectivity (HOST/TCP_PORT/USER/PASSWORD).${NC}"
            exit 1
        fi

        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Schema is up to date - no migrations needed                  ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Verifying schema...${NC}"

# Verify all expected columns exist
expected_columns="timestamp event_type operation_type duration_ms session_id user_id tenant_id plan_code success error_message metadata client_country client_region cloudflare_ray connecting_ip"
missing_columns=""

for col in $expected_columns; do
    exists=$(curl -sS "${CLICKHOUSE_URL}/" \
        --data-binary "SELECT count() FROM system.columns WHERE database = '${CLICKHOUSE_DATABASE}' AND table = 'metrics_events' AND name = '${col}'" \
        -H "X-ClickHouse-Database: ${CLICKHOUSE_DATABASE}")

    if [ "$exists" = "0" ]; then
        missing_columns="${missing_columns} ${col}"
        echo -e "${RED}✗ Column missing: ${col}${NC}"
    else
        echo -e "${GREEN}✓ Column present: ${col}${NC}"
    fi
done

echo ""

if [ -n "$missing_columns" ]; then
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Schema verification FAILED                                    ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}Missing columns:${missing_columns}${NC}"
    exit 1
else
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Schema verification PASSED - All columns present             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${BLUE}Migration Summary:${NC}"
echo "  Database: ${CLICKHOUSE_DATABASE}"
echo "  Table:    metrics_events"
echo "  Status:   ${GREEN}Ready${NC}"
echo ""
echo -e "${GREEN}All done! 🎉${NC}"
