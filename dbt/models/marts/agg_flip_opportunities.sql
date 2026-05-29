-- Current best GE flip opportunities.
--
-- "Flipping" in OSRS: buy an item at its low (instant-sell) price,
-- relist at high (instant-buy) price, pocket the spread minus 1% GE tax.
-- This model surfaces items where that math works out, right now.
--
-- Hybrid freshness: current prices come from the real-time /latest feed
-- (refreshed every minute), while trade *volume* comes from the most recent
-- 5-minute window (/5m is the only endpoint that reports volume). This keeps
-- the spread minute-fresh while still gating on real liquidity.

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

with_tax as (
    select
        cp.item_id,
        i.item_name,
        i.buy_limit,
        i.is_members,

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

        -- GE tax: 1% of high price, capped at 5,000,000 gp
        least(
            round(cp.high_price * 0.01),
            5000000
        )                                                       as tax_gp,

        -- Profit after tax per item
        cp.spread_gp - least(
            round(cp.high_price * 0.01),
            5000000
        )                                                       as profit_per_item,

        -- Max profit if you fill your entire buy limit
        (cp.spread_gp - least(round(cp.high_price * 0.01), 5000000))
            * coalesce(i.buy_limit, 0)                          as max_profit_per_limit

    from current_price cp
    inner join {{ ref('dim_items') }} i using (item_id)
    left join recent_volume rv using (item_id)
)

select *
from with_tax
where profit_per_item > 0              -- spread covers GE tax
  and coalesce(low_price_volume,  0) > 50   -- enough sell-side volume (last 5m)
  and coalesce(high_price_volume, 0) > 50   -- enough buy-side volume (last 5m)
  and low_price > 100                        -- skip items worth less than 100 gp
order by max_profit_per_limit desc nulls last
