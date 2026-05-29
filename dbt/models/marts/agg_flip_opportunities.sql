-- Current best GE flip opportunities.
--
-- "Flipping" in OSRS: buy an item at its low (instant-sell) price,
-- relist at high (instant-buy) price, pocket the spread minus 2% GE tax.
-- This model surfaces items where that math works out, right now.
--
-- Hybrid freshness: current prices come from the real-time /latest feed
-- (refreshed every minute), while trade *volume* comes from the most recent
-- 5-minute window (/5m is the only endpoint that reports volume). This keeps
-- the spread minute-fresh while still gating on real liquidity.
--
-- Materialized as a VIEW: it's rebuilt every minute and read continuously by
-- downstream consumers. A table rebuild would need an ACCESS EXCLUSIVE lock each
-- minute, which contends with readers and can stall (and back up the run queue).
-- A view always reflects the latest stg_prices_latest with no rebuild lock; the
-- computation is cheap on this data size.
{{ config(materialized='view') }}

with current_price as (
    -- Most recent real-time price per item
    select distinct on (item_id)
        item_id,
        high_price,
        low_price,
        spread_gp,
        spread_pct,
        high_time,
        low_time,
        loaded_at
    from {{ ref('stg_prices_latest') }}
    order by item_id, loaded_at desc
),

recent_volume as (
    -- Most recent 5-minute volume per item
    select distinct on (item_id)
        item_id,
        high_price_volume,
        low_price_volume,
        price_timestamp as volume_timestamp
    from {{ ref('fct_prices') }}
    order by item_id, price_timestamp desc
),

priced as (
    select
        cp.item_id,
        i.item_name,
        i.buy_limit,
        i.is_members,
        i.is_tax_exempt,

        -- Real-time instant-buy / instant-sell prices
        cp.high_price,
        cp.low_price,
        cp.spread_gp,
        cp.spread_pct,

        -- Liquidity from the most recent 5-minute window
        rv.high_price_volume,
        rv.low_price_volume,

        cp.loaded_at        as price_updated_at,
        rv.volume_timestamp,

        -- Hourly liquidity (from /1h) for time-to-fill
        liq.volume_per_hour,
        liq.avg_volume_per_hour_24h,

        -- GE tax: 2% of the sale (high) price, FLOORED to match the in-game
        -- round-down, capped at 5,000,000 gp. Untaxed when exempt or < 50 gp.
        -- high_price::numeric / 50 == 2% exactly; avoids 0.02 binary-float drift
        -- that can make floor(high_price * 0.02) land 1 gp low.
        case
            when i.is_tax_exempt then 0
            when cp.high_price < 50 then 0
            else least(floor(cp.high_price::numeric / 50), 5000000)
        end                                                     as tax_gp

    from current_price cp
    inner join {{ ref('dim_items') }} i using (item_id)
    left join recent_volume rv using (item_id)
    left join {{ ref('agg_item_liquidity') }} liq using (item_id)
)

-- Columns 1..15 preserve the original order; newer columns are appended last so
-- existing downstream queries / column guards are unaffected.
select
    item_id,
    item_name,
    buy_limit,
    is_members,
    high_price,
    low_price,
    spread_gp,
    spread_pct,
    high_price_volume,
    low_price_volume,
    price_updated_at,
    volume_timestamp,
    tax_gp,
    spread_gp - tax_gp                              as profit_per_item,
    (spread_gp - tax_gp) * coalesce(buy_limit, 0)   as max_profit_per_limit,
    is_tax_exempt,
    volume_per_hour,
    avg_volume_per_hour_24h,
    -- Estimated hours to trade through your full buy limit at the recent hourly
    -- rate. Lower = fills faster. Null when buy_limit or volume is unknown/zero.
    round(buy_limit::numeric / nullif(volume_per_hour, 0), 2)
                                                    as est_hours_to_fill_limit
from priced
where spread_gp - tax_gp > 0           -- spread covers GE tax
  and coalesce(low_price_volume,  0) > 50   -- enough sell-side volume (last 5m)
  and coalesce(high_price_volume, 0) > 50   -- enough buy-side volume (last 5m)
  and low_price > 100                        -- skip items worth less than 100 gp
order by max_profit_per_limit desc nulls last
