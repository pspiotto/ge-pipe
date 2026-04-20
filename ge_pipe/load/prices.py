from datetime import datetime, timezone
from typing import Any

from ge_pipe.load.base import get_conn


def load_prices_5m(payload: dict[str, Any]) -> int:
    """Insert 5-minute price records. Skips duplicates on (item_id, timestamp).
    Returns number of rows attempted."""
    data = payload.get("data", {})
    if not data:
        return 0

    sql = """
        INSERT INTO raw.prices_5m (
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
