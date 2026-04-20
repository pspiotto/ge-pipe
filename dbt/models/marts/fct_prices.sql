-- Fact table: 5-minute GE price snapshots, one row per (item, timestamp)
-- Only includes items present in dim_items (inner join drops orphaned price records)
with prices as (
    select * from {{ ref('stg_prices_5m') }}
),

items as (
    select item_id from {{ ref('dim_items') }}
)

select
    p.item_id,
    p.price_timestamp,
    p.avg_high_price,
    p.high_price_volume,
    p.avg_low_price,
    p.low_price_volume,
    p.spread_gp,
    p.spread_pct,
    p.loaded_at
from prices p
inner join items i using (item_id)
