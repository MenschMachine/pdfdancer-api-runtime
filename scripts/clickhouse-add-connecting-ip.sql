-- Migration: Add CF-Connecting-IP tracking field
-- Adds support for tracking client IP address via CF-Connecting-IP header
-- This allows grouping user requests by IP address instead of Ray ID

ALTER TABLE pdfdancer.metrics_events
    ADD COLUMN IF NOT EXISTS connecting_ip Nullable(String) COMMENT 'Client IP address from CF-Connecting-IP header';
