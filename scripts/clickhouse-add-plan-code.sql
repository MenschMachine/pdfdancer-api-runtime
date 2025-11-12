-- Migration: Add plan_code column to metrics_events table
-- Run this on existing ClickHouse deployments to add the plan_code field

-- Add plan_code column to existing table
-- ClickHouse allows adding columns without locking the table
ALTER TABLE pdfdancer.metrics_events
ADD COLUMN IF NOT EXISTS plan_code Nullable(String) AFTER tenant_id;

-- Verify the column was added
SELECT name, type, position
FROM system.columns
WHERE database = 'pdfdancer' AND table = 'metrics_events'
ORDER BY position;
