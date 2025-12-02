-- Migration: add client info columns parsed from X-PDFDancer-Client header
-- Single ALTER statement to work with apply-clickhouse-migrations.sh (execute_sql_file)
ALTER TABLE pdfdancer.metrics_events
    ADD COLUMN IF NOT EXISTS client_info Nullable(String) COMMENT 'Normalized client string lang/version from X-PDFDancer-Client',
    ADD COLUMN IF NOT EXISTS client_language Nullable(String) COMMENT 'Client language parsed from X-PDFDancer-Client',
    ADD COLUMN IF NOT EXISTS client_version Nullable(String) COMMENT 'Client version parsed from X-PDFDancer-Client';
