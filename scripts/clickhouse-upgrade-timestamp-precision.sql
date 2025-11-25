-- Migration: Upgrade timestamp column from DateTime to DateTime64(6)
-- Run this on existing ClickHouse deployments to enable microsecond precision timestamps
--
-- Because timestamp is part of ORDER BY and PARTITION BY, we need to recreate the table.
-- This migration:
-- 1. Creates a new table with DateTime64(6)
-- 2. Copies all data from the old table
-- 3. Swaps the tables via rename
--
-- Existing data will have .000000 microseconds appended.
-- New inserts will preserve full microsecond precision from Java Instant.

-- Step 0: Clean up any leftover table from previous failed attempts
DROP TABLE IF EXISTS pdfdancer.metrics_events_new;

-- Step 1: Create new table with DateTime64(6)
CREATE TABLE pdfdancer.metrics_events_new (
    timestamp DateTime64(6),
    event_type String,
    operation_type Nullable(String),
    duration_ms Nullable(UInt32),
    session_id Nullable(String),
    user_id Nullable(String),
    tenant_id Nullable(String),
    plan_code Nullable(String),
    success Bool DEFAULT true,
    error_message Nullable(String),
    metadata Nullable(String),
    client_country Nullable(String),
    client_region Nullable(String),
    cloudflare_ray Nullable(String),
    connecting_ip Nullable(String)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, event_type)
TTL toDateTime(timestamp) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Step 2: Copy all data from old table to new table
INSERT INTO pdfdancer.metrics_events_new
SELECT * FROM pdfdancer.metrics_events;

-- Step 3: Swap tables
RENAME TABLE pdfdancer.metrics_events TO pdfdancer.metrics_events_old, pdfdancer.metrics_events_new TO pdfdancer.metrics_events;

-- Step 4: Drop old table
DROP TABLE pdfdancer.metrics_events_old;
