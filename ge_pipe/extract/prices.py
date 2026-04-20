from typing import Any

from ge_pipe.extract.client import get_client


def fetch_prices_5m() -> dict[str, Any]:
    """Fetch 5-minute average GE prices for all items."""
    with get_client() as client:
        response = client.get("/5m")
        response.raise_for_status()
        return response.json()


def fetch_prices_1h() -> dict[str, Any]:
    """Fetch 1-hour average GE prices for all items."""
    with get_client() as client:
        response = client.get("/1h")
        response.raise_for_status()
        return response.json()
