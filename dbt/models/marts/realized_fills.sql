-- Bot trade outcomes — the feedback loop that closes the pipeline.
-- Grain: one row per fill/cancel event. Enriched with item_name and a
-- convenience time_to_fill_hours (directly comparable to
-- agg_flip_opportunities.est_hours_to_fill_limit).
--
-- View, not a table: it's append-only event data read for analysis (not on the
-- hot per-minute path), so a view stays always-current with no rebuild lock.
{{ config(materialized='view') }}

with fills as (
    select * from {{ ref('stg_realized_fills') }}
),

items as (
    select item_id, item_name from {{ ref('dim_items') }}
)

select
    f.event_id,
    f.flip_id,
    f.leg,
    f.item_id,
    i.item_name,
    f.bot_version,
    f.event,
    f.requested_qty,
    f.filled_qty,
    f.fill_ratio,
    f.offer_price,
    f.avg_fill_price,
    f.slippage_gp,
    f.tax_paid,
    f.realized_profit,
    f.offer_placed_at,
    f.filled_at,
    f.time_to_fill_seconds,
    round(f.time_to_fill_seconds / 3600.0, 4)   as time_to_fill_hours,
    f.monitor_ms,
    f.tolerance_ms,
    f.relist_count,
    f.is_filled,
    f.is_partial,
    f.is_cancelled,
    f.recorded_at
from fills f
left join items i using (item_id)
