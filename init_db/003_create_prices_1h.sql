-- 1-hour average GE prices from /1h (polled hourly). Same shape as prices_5m;
-- the value here is hourly trade VOLUME, used for liquidity + time-to-fill.
CREATE TABLE IF NOT EXISTS raw.prices_1h (
    item_id             INTEGER     NOT NULL,
    avg_high_price      INTEGER,
    high_price_volume   INTEGER,
    avg_low_price       INTEGER,
    low_price_volume    INTEGER,
    timestamp           TIMESTAMPTZ NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, timestamp)
);

CREATE INDEX IF NOT EXISTS idx_prices_1h_item_ts ON raw.prices_1h (item_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_prices_1h_timestamp ON raw.prices_1h (timestamp DESC);
