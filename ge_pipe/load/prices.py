from datetime import datetime, timezone
from typing import Any

from psycopg2.extras import execute_values

from ge_pipe.load.base import get_conn


def _epoch_to_ts(epoch: int | None) -> datetime | None:
    return datetime.fromtimestamp(epoch, tz=timezone.utc) if epoch else None


def load_prices_latest(payload: dict[str, Any]) -> int:
    """Insert real-time /latest prices, but only rows whose (high, low) price
    changed since the item's most recent stored snapshot.

    /latest is polled every minute and returns every item, but most items don't
    trade every minute. Skipping unchanged rows keeps table growth proportional
    to actual trading activity rather than poll_frequency * item_count, while
    still preserving a true history of price changes.

    Returns the number of rows actually inserted (changed since last snapshot).
    """
    data = payload.get("data", {})
    if not data:
        return 0

    now = datetime.now(timezone.utc)

    rows = []
    for item_id, v in data.items():
        high = v.get("high")
        low = v.get("low")
        # Skip never-traded / untradeable items (both sides null)
        if high is None and low is None:
            continue
        rows.append(
            (
                int(item_id),
                high,
                _epoch_to_ts(v.get("highTime")),
                low,
                _epoch_to_ts(v.get("lowTime")),
                now,
            )
        )

    if not rows:
        return 0

    # Insert a row only when (high_price, low_price) differs from the item's most
    # recent snapshot. IS NOT DISTINCT FROM makes the comparison null-safe.
    sql = """
        INSERT INTO raw.prices_latest (
            item_id, high_price, high_time, low_price, low_time, loaded_at
        )
        SELECT item_id, high_price, high_time, low_price, low_time, loaded_at
        FROM (
            SELECT
                v.item_id::integer        as item_id,
                v.high_price::integer     as high_price,
                v.high_time::timestamptz  as high_time,
                v.low_price::integer      as low_price,
                v.low_time::timestamptz   as low_time,
                v.loaded_at::timestamptz  as loaded_at
            FROM (VALUES %s) AS v
                (item_id, high_price, high_time, low_price, low_time, loaded_at)
        ) v
        WHERE NOT EXISTS (
            SELECT 1
            FROM raw.prices_latest p
            WHERE p.item_id = v.item_id
              AND p.loaded_at = (
                  SELECT max(p2.loaded_at)
                  FROM raw.prices_latest p2
                  WHERE p2.item_id = v.item_id
              )
              AND p.high_price IS NOT DISTINCT FROM v.high_price
              AND p.low_price  IS NOT DISTINCT FROM v.low_price
        )
    """

    with get_conn() as conn:
        with conn.cursor() as cur:
            # Single statement (page_size >= len) so cur.rowcount is the true total.
            execute_values(cur, sql, rows, page_size=len(rows))
            return cur.rowcount


def _load_window_prices(table: str, payload: dict[str, Any]) -> int:
    """Insert averaged-window price records (shared by /5m and /1h, which have an
    identical shape). Skips duplicates on (item_id, timestamp). Returns rows
    attempted."""
    data = payload.get("data", {})
    if not data:
        return 0

    sql = f"""
        INSERT INTO raw.{table} (
            item_id, avg_high_price, high_price_volume,
            avg_low_price, low_price_volume, timestamp, loaded_at
        )
        VALUES (
            %(item_id)s, %(avgHighPrice)s, %(highPriceVolume)s,
            %(avgLowPrice)s, %(lowPriceVolume)s, to_timestamp(%(timestamp)s), %(loaded_at)s
        )
        ON CONFLICT (item_id, timestamp) DO NOTHING
    """

    now = datetime.now(timezone.utc)
    api_timestamp = payload.get("timestamp", 0)

    rows = [
        {
            "item_id": int(item_id),
            "avgHighPrice": v.get("avgHighPrice"),
            "highPriceVolume": v.get("highPriceVolume"),
            "avgLowPrice": v.get("avgLowPrice"),
            "lowPriceVolume": v.get("lowPriceVolume"),
            "timestamp": api_timestamp,
            "loaded_at": now,
        }
        for item_id, v in data.items()
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
            return len(rows)


def load_prices_5m(payload: dict[str, Any]) -> int:
    """Insert 5-minute price records. Skips duplicates on (item_id, timestamp).
    Returns number of rows attempted."""
    return _load_window_prices("prices_5m", payload)


def load_prices_1h(payload: dict[str, Any]) -> int:
    """Insert 1-hour price records (source of hourly volume). Skips duplicates on
    (item_id, timestamp). Returns number of rows attempted."""
    return _load_window_prices("prices_1h", payload)
