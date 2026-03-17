-- Add request_body column to capture JSON request bodies for debugging and auditing
-- ZSTD compression - JSON compresses very well
ALTER TABLE pdfdancer.metrics_events ADD COLUMN request_body Nullable(String) CODEC(ZSTD);
