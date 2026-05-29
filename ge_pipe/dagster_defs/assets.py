from dagster import AssetExecutionContext, asset

from ge_pipe.extract.mapping import fetch_item_mapping
from ge_pipe.extract.prices import fetch_prices_1h, fetch_prices_5m, fetch_prices_latest
from ge_pipe.load.mapping import load_item_mapping
from ge_pipe.load.prices import load_prices_1h, load_prices_5m, load_prices_latest


@asset(group_name="raw", compute_kind="python", key_prefix="raw")
def item_mapping(context: AssetExecutionContext) -> int:
    """Full refresh of OSRS item metadata from /mapping. Run daily."""
    records = fetch_item_mapping()
    count = load_item_mapping(records)
    context.log.info(f"Upserted {count} item mappings")
    return count


@asset(group_name="raw", compute_kind="python", key_prefix="raw", deps=[item_mapping])
def prices_5m(context: AssetExecutionContext) -> int:
    """5-minute GE price snapshot for all items. Run every 5 minutes.

    Source of trade *volume* (the only endpoint that reports it)."""
    payload = fetch_prices_5m()
    count = load_prices_5m(payload)
    context.log.info(f"Loaded {count} price records")
    return count


@asset(group_name="raw", compute_kind="python", key_prefix="raw", deps=[item_mapping])
def prices_latest(context: AssetExecutionContext) -> int:
    """Real-time /latest price snapshot for all items. Run every minute.

    Only rows whose price changed since the last snapshot are stored."""
    payload = fetch_prices_latest()
    count = load_prices_latest(payload)
    context.log.info(f"Loaded {count} changed latest-price rows")
    return count


@asset(group_name="raw", compute_kind="python", key_prefix="raw", deps=[item_mapping])
def prices_1h(context: AssetExecutionContext) -> int:
    """1-hour GE price/volume snapshot for all items. Run hourly.

    Source of hourly trade volume for liquidity + time-to-fill metrics."""
    payload = fetch_prices_1h()
    count = load_prices_1h(payload)
    context.log.info(f"Loaded {count} hourly price records")
    return count
