-- Trade fill/cancel events, written directly by the bot (the feedback loop).
--
-- Write contract (bot side): append-only INSERTs over a separate, short-lived
-- AUTOCOMMIT connection, kept entirely off the read path (which is
-- setReadOnly(true)), so fill-writes can never lock or stall opportunity fetches.
-- One row per fill/cancel event, hooked into the bot lifecycle (reconcile,
-- cancelBuy/cancelSell, recordBought/recordSold). event_id and recorded_at are
-- assigned by the DB; the bot supplies the rest.
--
-- Field          Source
-- flip_id, leg   groups both legs (buy|sell) of a round-trip
-- item_id, bot_version
-- event          filled | partial | cancelled_deadline | cancelled_pricemove | cancelled_manual
-- requested_qty, filled_qty   offer vs getTransferredAmount()
-- offer_price, avg_fill_price listed vs actual getTransferredValue()/qty (slippage)
-- tax_paid, realized_profit   sells; proceeds - cost - tax on the closing leg
-- offer_placed_at, filled_at  -> actual time-to-fill
-- monitor_ms, tolerance_ms, relist_count  the cadence used
CREATE TABLE IF NOT EXISTS raw.realized_fills (
    event_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    flip_id         TEXT        NOT NULL,
    leg             TEXT        NOT NULL,   -- buy | sell
    item_id         INTEGER     NOT NULL,
    bot_version     TEXT,
    event           TEXT        NOT NULL,   -- filled | partial | cancelled_{deadline,pricemove,manual}
    requested_qty   INTEGER,
    filled_qty      INTEGER,
    offer_price     INTEGER,
    avg_fill_price  NUMERIC,
    tax_paid        INTEGER,
    realized_profit BIGINT,
    offer_placed_at TIMESTAMPTZ,
    filled_at       TIMESTAMPTZ,
    monitor_ms      INTEGER,
    tolerance_ms    INTEGER,
    relist_count    INTEGER,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- leg/event values are validated by dbt accepted_values tests, not a CHECK, so a
-- stray value can never reject a bot write (it surfaces as a failing test instead).

CREATE INDEX IF NOT EXISTS idx_realized_fills_item    ON raw.realized_fills (item_id);
CREATE INDEX IF NOT EXISTS idx_realized_fills_flip    ON raw.realized_fills (flip_id);
CREATE INDEX IF NOT EXISTS idx_realized_fills_filled  ON raw.realized_fills (filled_at DESC);
