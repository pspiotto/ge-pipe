with source as (
    select * from {{ source('raw', 'item_mapping') }}
),

renamed as (
    select
        item_id,
        name                as item_name,
        examine,
        members             as is_members,
        lowalch             as low_alch_value,
        highalch            as high_alch_value,
        buy_limit,
        value               as shop_value,
        icon,
        loaded_at
    from source
)

select * from renamed
