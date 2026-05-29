with stg as (
    select * from {{ ref('stg_item_mapping') }}
),

tax_exempt as (
    select item_id from {{ ref('tax_exempt_items') }}
)

select
    stg.item_id,
    stg.item_name,
    stg.examine,
    stg.is_members,
    stg.low_alch_value,
    stg.high_alch_value,
    stg.buy_limit,
    stg.shop_value,
    stg.icon,

    -- Intrinsic GE tax exemption (tools, bonds) from the maintained seed list.
    -- The separate "< 50 gp sales are untaxed" rule is price-dependent and is
    -- applied in agg_flip_opportunities, not here.
    (te.item_id is not null) as is_tax_exempt,

    stg.loaded_at           as last_refreshed_at
from stg
left join tax_exempt te using (item_id)
