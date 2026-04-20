from typing import Any

from ge_pipe.extract.client import get_client


def fetch_item_mapping() -> list[dict[str, Any]]:
    """Fetch item ID → metadata mapping from /mapping. ~4k items, full refresh."""
    with get_client() as client:
        response = client.get("/mapping")
        response.raise_for_status()
        return response.json()
