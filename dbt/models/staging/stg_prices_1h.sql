with source as (
    select * from {{ source('raw', 'prices_1h') }}
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

        -- total units traded in the hour (both sides)
        coalesce(high_price_volume, 0)
            + coalesce(low_price_volume, 0)             as total_volume

    from source
    -- exclude rows with no activity at all
    where coalesce(high_price_volume, 0) > 0
       or coalesce(low_price_volume, 0) > 0
)

select * from cleaned
