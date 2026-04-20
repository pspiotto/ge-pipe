with stg as (
    select * from {{ ref('stg_item_mapping') }}
)

select
    item_id,
    item_name,
    examine,
    is_members,
    low_alch_value,
    high_alch_value,
    buy_limit,
    shop_value,
    icon,
    loaded_at               as last_refreshed_at
from stg
