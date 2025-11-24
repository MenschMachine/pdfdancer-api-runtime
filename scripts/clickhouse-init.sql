-- PDFDancer Analytics Database Schema

-- Main events table for raw metrics
CREATE TABLE IF NOT EXISTS pdfdancer.metrics_events (
    timestamp DateTime NOT NULL,
    event_type String NOT NULL,
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
    cloudflare_ray Nullable(String)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, event_type)
TTL timestamp + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Daily aggregates table for long-term retention
CREATE TABLE IF NOT EXISTS pdfdancer.metrics_aggregates (
    date Date NOT NULL,
    metric_key String NOT NULL,
    metric_value UInt64 NOT NULL,
    metadata Nullable(String)
) ENGINE = ReplacingMergeTree()
ORDER BY (date, metric_key)
SETTINGS index_granularity = 8192;

-- Materialized view for automatic daily aggregation (optional, for future optimization)
-- CREATE MATERIALIZED VIEW IF NOT EXISTS pdfdancer.daily_page_counts
-- ENGINE = SummingMergeTree()
-- ORDER BY (date, operation_type)
-- AS SELECT
--     toDate(timestamp) as date,
--     operation_type,
--     count() as page_count
-- FROM pdfdancer.metrics_events
-- WHERE event_type = 'PDF_PAGE_GENERATED'
-- GROUP BY date, operation_type;
