-- Migration: Upgrade timestamp column from DateTime to DateTime64(6)
-- Run this on existing ClickHouse deployments to enable microsecond precision timestamps
--
-- This change:
-- - Upgrades timestamp resolution from seconds to microseconds (6 decimal places)
-- - Existing data will have .000000 microseconds appended
-- - New inserts will preserve full microsecond precision from Java Instant
--
-- ClickHouse performs this operation safely without data loss

-- Modify timestamp column type to DateTime64(6)
ALTER TABLE pdfdancer.metrics_events
MODIFY COLUMN timestamp DateTime64(6);

-- Verify the column type was changed
SELECT name, type
FROM system.columns
WHERE database = 'pdfdancer' AND table = 'metrics_events' AND name = 'timestamp';
