-- Per-item liquidity from the /1h volume feed.
--
-- volume_per_hour          — units traded in the most recent completed hour
-- avg_volume_per_hour_24h  — rolling average hourly volume over the trailing 24h
-- hours_observed_24h       — how many hourly buckets that average is based on
--                            (warm-up indicator; ramps to 24 as history accrues)
--
-- Materialized as a table (precomputed) because it's refreshed only hourly but
-- read continuously by agg_flip_opportunities. Grain: one row per item.

with hourly as (
    select
        item_id,
        price_timestamp,
        total_volume,
        high_price_volume,
        low_price_volume
    from {{ ref('stg_prices_1h') }}
),

latest_hour as (
    select distinct on (item_id)
        item_id,
        price_timestamp        as latest_hour_ts,
        total_volume           as volume_per_hour,
        high_price_volume      as high_volume_per_hour,
        low_price_volume       as low_volume_per_hour
    from hourly
    order by item_id, price_timestamp desc
),

rolling_24h as (
    select
        item_id,
        round(avg(total_volume))   as avg_volume_per_hour_24h,
        count(*)                   as hours_observed_24h
    from hourly
    where price_timestamp >= now() - interval '24 hours'
    group by item_id
)

select
    lh.item_id,
    lh.latest_hour_ts,
    lh.volume_per_hour,
    lh.high_volume_per_hour,
    lh.low_volume_per_hour,
    rh.avg_volume_per_hour_24h,
    rh.hours_observed_24h
from latest_hour lh
left join rolling_24h rh using (item_id)
