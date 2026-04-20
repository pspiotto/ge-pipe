-- Current best GE flip opportunities.
--
-- "Flipping" in OSRS: buy an item at its low (instant-sell) price,
-- relist at high (instant-buy) price, pocket the spread minus 1% GE tax.
-- This model surfaces items where that math works out, right now.

with latest_prices as (
    -- Most recent 5-minute snapshot per item
    select distinct on (item_id)
        item_id,
        avg_high_price,
        high_price_volume,
        avg_low_price,
        low_price_volume,
        spread_gp,
        spread_pct,
        price_timestamp
    from {{ ref('fct_prices') }}
    order by item_id, price_timestamp desc
),

with_tax as (
    select
        lp.*,
        i.item_name,
        i.buy_limit,
        i.is_members,

        -- GE tax: 1% of high price, capped at 5,000,000 gp
        least(
            round(lp.avg_high_price * 0.01),
            5000000
        )                                                       as tax_gp,

        -- Profit after tax per item
        lp.spread_gp - least(
            round(lp.avg_high_price * 0.01),
            5000000
        )                                                       as profit_per_item,

        -- Max profit if you fill your entire buy limit
        (lp.spread_gp - least(round(lp.avg_high_price * 0.01), 5000000))
            * coalesce(i.buy_limit, 0)                          as max_profit_per_limit

    from latest_prices lp
    inner join {{ ref('dim_items') }} i using (item_id)
)

select *
from with_tax
where profit_per_item > 0              -- spread covers GE tax
  and coalesce(low_price_volume,  0) > 50   -- enough sell-side volume
  and coalesce(high_price_volume, 0) > 50   -- enough buy-side volume
  and avg_low_price > 100                    -- skip items worth less than 100 gp
order by max_profit_per_limit desc nulls last
