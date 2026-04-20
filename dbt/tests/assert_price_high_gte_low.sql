-- Custom test: high price should never be less than low price.
-- The API occasionally emits stale/inverted data during rollover windows.
-- This test catches it. Returns rows = failures.
select
    item_id,
    price_timestamp,
    avg_high_price,
    avg_low_price
from {{ ref('fct_prices') }}
where avg_high_price is not null
  and avg_low_price  is not null
  and avg_high_price < avg_low_price
