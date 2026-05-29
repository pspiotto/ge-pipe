-- Per-item short-horizon price volatility from the 5-minute history.
--
-- mid = (avg_high_price + avg_low_price) / 2 per 5-minute snapshot;
-- mid_volatility_1h = sample stddev of mid over the trailing 1 hour (~12 snaps).
-- Feeds Avellaneda spread-sizing (mid_volatility_1h, in gp) and a cross-item risk
-- filter (mid_volatility_pct_1h — scale-free, comparable across price tiers).
--
-- Table (precomputed), refreshed by the 5-minute job and read by
-- agg_flip_opportunities. Grain: one row per item. mid_volatility_1h is null until
-- >= 2 snapshots exist in the window (stddev_samp); snapshots_used_1h shows ramp.
{{ config(materialized='table') }}

with snapshots as (
    select
        item_id,
        price_timestamp,
        -- cast before summing: high-value items (billions) overflow int4 on add
        (avg_high_price::numeric + avg_low_price::numeric) / 2.0 as mid
    from {{ ref('fct_prices') }}
    where avg_high_price is not null
      and avg_low_price is not null
      and price_timestamp >= now() - interval '1 hour'
),

agg as (
    select
        item_id,
        max(price_timestamp)            as latest_snapshot_ts,
        count(*)                        as snapshots_used_1h,
        round(avg(mid), 2)              as mid_mean_1h,
        round(stddev_samp(mid), 2)      as mid_volatility_1h
    from snapshots
    group by item_id
)

select
    item_id,
    latest_snapshot_ts,
    snapshots_used_1h,
    mid_mean_1h,
    mid_volatility_1h,
    -- coefficient of variation (%): scale-free, for cross-item risk filtering
    case
        when mid_mean_1h > 0 and mid_volatility_1h is not null
        then round(mid_volatility_1h / mid_mean_1h * 100, 3)
    end                                 as mid_volatility_pct_1h
from agg
