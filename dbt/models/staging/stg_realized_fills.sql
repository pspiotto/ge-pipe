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

        -- per-unit slippage vs the listed price. Effectively a BUY-side signal:
        -- buys record actual gp spent / qty, so a negative value means you paid
        -- below your bid (favourable). Sells fill at the listed ask, so this is
        -- ~0 on sells by construction — the sell-side outcome lives in
        -- realized_profit, not here.
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
        (event in ('cancelled_deadline', 'cancelled_pricemove', 'cancelled_manual'))
                                                                as is_cancelled

    from source
)

select * from cleaned
