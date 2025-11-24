-- Migration: Create ASN lookup table
-- Loads ASN data from CSV for IP address to AS information lookups
-- Format: network,country,country_code,continent,continent_code,asn,as_name,as_domain

-- Create table to store ASN ranges
CREATE TABLE IF NOT EXISTS pdfdancer.asn_ranges (
    network String,
    country Nullable(String),
    country_code Nullable(String),
    continent Nullable(String),
    continent_code Nullable(String),
    asn Nullable(String),
    as_name Nullable(String),
    as_domain Nullable(String),
    -- Parsed for efficient IP lookups
    network_start IPv4,
    network_end IPv4
) ENGINE = MergeTree()
ORDER BY network_start
SETTINGS index_granularity = 8192;

-- Create a metadata table to track CSV loads and MD5 checksums
CREATE TABLE IF NOT EXISTS pdfdancer.asn_metadata (
    load_timestamp DateTime DEFAULT now(),
    csv_path String,
    csv_md5 String,
    rows_loaded UInt64,
    load_duration_ms UInt64
) ENGINE = MergeTree()
ORDER BY load_timestamp
SETTINGS index_granularity = 8192;
