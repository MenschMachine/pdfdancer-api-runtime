#!/usr/bin/env bash
set -euo pipefail

# Inserts a new tenant and API token into the SQLite tenant database.
# - Creates schema if it doesn't exist
# - Inserts tenant if missing (by slug) or updates fields if provided
# - Generates a raw token, stores SHA-256 hash and prefix
# - Prints the raw token to stdout
#
# Usage:
#   scripts/tenant-add.sh \
#     --db ./tenant.db \
#     --name "Acme Inc" \
#     --slug acme \
#     --plan PRO \
#     [--external-ref EXT123] \
#     [--plan-metadata '{"region":"eu"}'] \
#     [--status ACTIVE] \
#     [--token-name primary] \
#     [--scopes documents:read,documents:write] \
#     [--created-by USER_ID] \
#     [--expires-at 2026-01-01T00:00:00Z]
#
# Notes:
# - plan must be one of: FREE, PRO, ENTERPRISE, SYSTEM
# - status must be one of: ACTIVE, SUSPENDED, DELETED
# - requires: sqlite3, openssl, date

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found in PATH" >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl not found in PATH" >&2
  exit 1
fi

DB=""
NAME=""
SLUG=""
PLAN="PRO"
EXTERNAL_REF=""
PLAN_METADATA=""
STATUS="ACTIVE"
TOKEN_NAME="primary"
SCOPES="documents:read"
CREATED_BY=""
EXPIRES_AT_ISO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --slug) SLUG="$2"; shift 2;;
    --plan) PLAN="$2"; shift 2;;
    --external-ref) EXTERNAL_REF="$2"; shift 2;;
    --plan-metadata) PLAN_METADATA="$2"; shift 2;;
    --status) STATUS="$2"; shift 2;;
    --token-name) TOKEN_NAME="$2"; shift 2;;
    --scopes) SCOPES="$2"; shift 2;;
    --created-by) CREATED_BY="$2"; shift 2;;
    --expires-at) EXPIRES_AT_ISO="$2"; shift 2;;
    -h|--help)
      sed -n '1,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$DB" || -z "$NAME" || -z "$SLUG" ]]; then
  echo "Missing required args. See --help" >&2
  exit 1
fi

# Validate enums
case "$PLAN" in
  FREE|PRO|ENTERPRISE|SYSTEM) :;;
  *) echo "Invalid --plan: $PLAN" >&2; exit 1;;
esac

case "$STATUS" in
  ACTIVE|SUSPENDED|DELETED) :;;
  *) echo "Invalid --status: $STATUS" >&2; exit 1;;
esac

# Epoch millis now
NOW_MS=$(($(date +%s) * 1000))

# Convert ISO expires-at to epoch millis if provided
EXPIRES_MS_SQL="NULL"
if [[ -n "$EXPIRES_AT_ISO" ]]; then
  # macOS BSD date handling for ISO8601 Z
  if ! EXPIRES_S=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES_AT_ISO" +%s 2>/dev/null); then
    echo "Invalid --expires-at format, expected YYYY-MM-DDThh:mm:ssZ" >&2
    exit 1
  fi
  EXPIRES_MS_SQL=$((EXPIRES_S * 1000))
fi

# Simple SQL single-quote escaper for string literals
sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# UUIDs via Python or uuidgen; prefer uuidgen if available
uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    python3 - <<'PY'
import uuid; print(str(uuid.uuid4()))
PY
  fi
}

TOKEN_ID=$(uuid)

# Generate raw token: 64 hex chars (like service)
RAW_TOKEN=$(openssl rand -hex 32)
PREFIX=${RAW_TOKEN:0:8}
TOKEN_HASH=$(printf "%s" "$RAW_TOKEN" | openssl dgst -sha256 -binary | xxd -p -c 256)

# Create directories
mkdir -p "$(dirname "$DB")"

# Apply schema
sqlite3 "$DB" <<SQL
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS tenants (
  id TEXT PRIMARY KEY,
  external_ref TEXT,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  plan_code TEXT NOT NULL,
  plan_metadata TEXT,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tenant_users (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  state TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  last_login_at INTEGER,
  UNIQUE(tenant_id, user_id),
  FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS tenant_api_tokens (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  prefix TEXT NOT NULL,
  scopes TEXT NOT NULL,
  created_by_user_id TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,
  last_used_at INTEGER,
  UNIQUE(token_hash),
  FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);
SQL

# Prepare SQL-safe literals
NAME_SQL="'$(sql_escape "$NAME")'"
SLUG_SQL="'$(sql_escape "$SLUG")'"
PLAN_SQL="'$PLAN'"
STATUS_SQL="'$STATUS'"
if [[ -n "$EXTERNAL_REF" ]]; then EXT_REF_SQL="'$(sql_escape "$EXTERNAL_REF")'"; else EXT_REF_SQL="NULL"; fi
if [[ -n "$PLAN_METADATA" ]]; then PLAN_METADATA_SQL="'$(sql_escape "$PLAN_METADATA")'"; else PLAN_METADATA_SQL="NULL"; fi
if [[ -n "$CREATED_BY" ]]; then CREATED_BY_SQL="'$(sql_escape "$CREATED_BY")'"; else CREATED_BY_SQL="NULL"; fi
TOKEN_NAME_SQL="'$(sql_escape "$TOKEN_NAME")'"
SCOPES_SQL="'$(sql_escape "$SCOPES")'"

# Determine tenant id by slug if it exists; otherwise generate a new one
EXISTING_TENANT_ID=$(sqlite3 "$DB" "SELECT id FROM tenants WHERE slug = $SLUG_SQL LIMIT 1;") || true
if [[ -n "$EXISTING_TENANT_ID" ]]; then
  TENANT_ID="$EXISTING_TENANT_ID"
else
  TENANT_ID=$(uuid)
fi

# Upsert tenant by id
sqlite3 "$DB" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tenants (id, external_ref, name, slug, plan_code, plan_metadata, status, created_at, updated_at)
VALUES ('$TENANT_ID', $EXT_REF_SQL, $NAME_SQL, $SLUG_SQL, $PLAN_SQL, $PLAN_METADATA_SQL, $STATUS_SQL, $NOW_MS, $NOW_MS)
ON CONFLICT(id) DO UPDATE SET
  external_ref=excluded.external_ref,
  name=excluded.name,
  slug=excluded.slug,
  plan_code=excluded.plan_code,
  plan_metadata=excluded.plan_metadata,
  status=excluded.status,
  updated_at=excluded.updated_at;
SQL

# Insert token
sqlite3 "$DB" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO tenant_api_tokens (id, tenant_id, name, token_hash, prefix, scopes, created_by_user_id, created_at, expires_at, last_used_at)
VALUES ('$TOKEN_ID', '$TENANT_ID', $TOKEN_NAME_SQL, '$TOKEN_HASH', '$PREFIX', $SCOPES_SQL, $CREATED_BY_SQL, $NOW_MS, ${EXPIRES_MS_SQL}, NULL);
SQL

cat <<OUT
Tenant created/updated:
  id:   $TENANT_ID
  name: $NAME
  slug: $SLUG
  plan: $PLAN

API token created:
  id:        $TOKEN_ID
  name:      $TOKEN_NAME
  scopes:    $SCOPES
  prefix:    $PREFIX
  RAW TOKEN: $RAW_TOKEN

IMPORTANT: The raw token is only shown once. Store it securely.
OUT
