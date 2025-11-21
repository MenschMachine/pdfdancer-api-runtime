-- Migration: Add client region tracking fields
-- Adds support for tracking client country, region, and Cloudflare datacenter
-- via Cloudflare headers (CF-IPCountry and CF-Ray)

ALTER TABLE pdfdancer.metrics_events
    ADD COLUMN IF NOT EXISTS client_country Nullable(String) COMMENT 'Client country code from CF-IPCountry header (e.g., US, DE, JP)',
    ADD COLUMN IF NOT EXISTS client_region Nullable(String) COMMENT 'Client region mapped from country (EU, US, APAC, OTHER)',
    ADD COLUMN IF NOT EXISTS cloudflare_ray Nullable(String) COMMENT 'Cloudflare Ray ID from CF-Ray header for request tracing';
