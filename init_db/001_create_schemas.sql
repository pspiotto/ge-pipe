-- Schemas
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS marts;

-- Item metadata (full refresh daily from /mapping)
CREATE TABLE IF NOT EXISTS raw.item_mapping (
    item_id     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    examine     TEXT,
    members     BOOLEAN,
    lowalch     INTEGER,
    highalch    INTEGER,
    buy_limit   INTEGER,
    value       INTEGER,
    icon        TEXT,
    loaded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5-minute average GE prices (~25k rows per tick)
CREATE TABLE IF NOT EXISTS raw.prices_5m (
    item_id             INTEGER     NOT NULL,
    avg_high_price      INTEGER,
    high_price_volume   INTEGER,
    avg_low_price       INTEGER,
    low_price_volume    INTEGER,
    timestamp           TIMESTAMPTZ NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_prices_5m_item_id   ON raw.prices_5m (item_id);
CREATE INDEX IF NOT EXISTS idx_prices_5m_timestamp ON raw.prices_5m (timestamp DESC);
