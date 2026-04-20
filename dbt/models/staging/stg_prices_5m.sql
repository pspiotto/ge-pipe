with source as (
    select * from {{ source('raw', 'prices_5m') }}
),

cleaned as (
    select
        item_id,
        avg_high_price,
        high_price_volume,
        avg_low_price,
        low_price_volume,
        timestamp                                       as price_timestamp,
        loaded_at,

        -- spread in GP
        case
            when avg_high_price is not null
             and avg_low_price  is not null
            then avg_high_price - avg_low_price
        end                                             as spread_gp,

        -- spread as percentage of low price
        case
            when avg_low_price > 0
             and avg_high_price is not null
            then round(
                ((avg_high_price - avg_low_price)::numeric / avg_low_price) * 100,
                2
            )
        end                                             as spread_pct

    from source
    -- exclude rows where both sides are null (delisted/placeholder items)
    where avg_high_price is not null or avg_low_price is not null
)

select * from cleaned
