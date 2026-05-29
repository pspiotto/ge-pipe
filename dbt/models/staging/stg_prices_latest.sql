with source as (
    select * from {{ source('raw', 'prices_latest') }}
),

cleaned as (
    select
        item_id,
        high_price,
        high_time,
        low_price,
        low_time,
        loaded_at,

        -- spread in GP (instant-buy minus instant-sell)
        case
            when high_price is not null
             and low_price  is not null
            then high_price - low_price
        end                                             as spread_gp,

        -- spread as percentage of low price
        case
            when low_price > 0
             and high_price is not null
            then round(
                ((high_price - low_price)::numeric / low_price) * 100,
                2
            )
        end                                             as spread_pct

    from source
    -- exclude rows where both sides are null (delisted/placeholder items)
    where high_price is not null or low_price is not null
)

select * from cleaned
