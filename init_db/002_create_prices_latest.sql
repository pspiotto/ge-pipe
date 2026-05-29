-- Real-time GE prices from /latest (polled every minute).
--
-- The loader appends a row only when an item's (high_price, low_price) changes
-- vs its previous snapshot, so growth tracks actual trading activity rather than
-- poll_frequency * item_count. Grain: one row per (item_id, loaded_at).
--
-- Note: /latest reports last-traded prices only — there is NO volume here.
-- Volume comes from raw.prices_5m.
CREATE TABLE IF NOT EXISTS raw.prices_latest (
    item_id     INTEGER     NOT NULL,
    high_price  INTEGER,
    high_time   TIMESTAMPTZ,
    low_price   INTEGER,
    low_time    TIMESTAMPTZ,
    loaded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, loaded_at)
);

-- Supports both the per-item "most recent snapshot" lookup in the loader's
-- change-detection and the distinct-on (item_id) ... order by loaded_at desc
-- in stg/marts.
CREATE INDEX IF NOT EXISTS idx_prices_latest_item_loaded
    ON raw.prices_latest (item_id, loaded_at DESC);
