from datetime import datetime, timezone
from typing import Any

from ge_pipe.load.base import get_conn


def load_item_mapping(records: list[dict[str, Any]]) -> int:
    """Upsert item mapping records. Returns number of rows processed."""
    if not records:
        return 0

    sql = """
        INSERT INTO raw.item_mapping (
            item_id, name, examine, members, lowalch, highalch,
            buy_limit, value, icon, loaded_at
        )
        VALUES (
            %(id)s, %(name)s, %(examine)s, %(members)s, %(lowalch)s, %(highalch)s,
            %(limit)s, %(value)s, %(icon)s, %(loaded_at)s
        )
        ON CONFLICT (item_id) DO UPDATE SET
            name       = EXCLUDED.name,
            examine    = EXCLUDED.examine,
            members    = EXCLUDED.members,
            lowalch    = EXCLUDED.lowalch,
            highalch   = EXCLUDED.highalch,
            buy_limit  = EXCLUDED.buy_limit,
            value      = EXCLUDED.value,
            icon       = EXCLUDED.icon,
            loaded_at  = EXCLUDED.loaded_at
    """

    now = datetime.now(timezone.utc)
    rows = [{**r, "loaded_at": now} for r in records]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
            return len(rows)
