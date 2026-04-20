from dagster import AssetExecutionContext, asset

from ge_pipe.extract.mapping import fetch_item_mapping
from ge_pipe.extract.prices import fetch_prices_5m
from ge_pipe.load.mapping import load_item_mapping
from ge_pipe.load.prices import load_prices_5m


@asset(group_name="raw", compute_kind="python")
def raw_item_mapping(context: AssetExecutionContext) -> int:
    """Full refresh of OSRS item metadata from /mapping. Run daily."""
    records = fetch_item_mapping()
    count = load_item_mapping(records)
    context.log.info(f"Upserted {count} item mappings")
    return count


@asset(group_name="raw", compute_kind="python", deps=[raw_item_mapping])
def raw_prices_5m(context: AssetExecutionContext) -> int:
    """5-minute GE price snapshot for all items. Run every 5 minutes."""
    payload = fetch_prices_5m()
    count = load_prices_5m(payload)
    context.log.info(f"Loaded {count} price records")
    return count
