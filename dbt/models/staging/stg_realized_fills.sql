with source as (
    select * from {{ source('raw', 'realized_fills') }}
),

cleaned as (
    select
        event_id,
        flip_id,
        leg,
        item_id,
        bot_version,
        event,
        requested_qty,
        filled_qty,
        offer_price,
        avg_fill_price,
        tax_paid,
        realized_profit,
        offer_placed_at,
        filled_at,
        monitor_ms,
        tolerance_ms,
        relist_count,
        recorded_at,

        -- fraction of the offer that actually filled
        case
            when requested_qty > 0
            then round(filled_qty::numeric / requested_qty, 4)
        end                                                     as fill_ratio,

        -- per-unit slippage vs the listed price (signed). For a sell leg a
        -- negative value means you got less than listed; for a buy leg a negative
        -- value means you paid less than offered (favourable). Interpret by leg.
        case
            when avg_fill_price is not null and offer_price is not null
            then avg_fill_price - offer_price
        end                                                     as slippage_gp,

        -- actual time-to-fill (compare against est_hours_to_fill_limit)
        case
            when offer_placed_at is not null and filled_at is not null
            then extract(epoch from (filled_at - offer_placed_at))
        end                                                     as time_to_fill_seconds,

        (event = 'filled')                                      as is_filled,
        (event = 'partial')                                     as is_partial,
        (event in ('cancelled_deadline', 'cancelled_pricemove')) as is_cancelled

    from source
)

select * from cleaned
