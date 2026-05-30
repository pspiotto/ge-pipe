# `marts.agg_flip_opportunities` — all price tiers + `is_high_value` (bot-facing)

What changed when the flip mart was widened to cover every price tier. Hand this
to the bot.

## TL;DR

The flip mart no longer pre-filters for liquidity. It now returns **all price
tiers** (~2,000 rows, up from ~54), including low-volume high-value gear.
**Liquidity gating is now the consumer's job.** One new column, `is_high_value`,
appended at the end.

## ⚠️ Behaviour change you must handle

Previously every row was guaranteed to have **> 50 units of 5-minute volume on
both sides**, so a row's presence implied "liquid enough to flip." **That
guarantee is gone.** Rows can now have low or zero recent 5-minute volume
(`high_price_volume` / `low_price_volume` may be `0` or `NULL`). If any logic
assumed "it's in the mart ⇒ I can fill my limit," gate it explicitly now.

## Gates the mart still applies

A row appears only if **all** of:

- `profit_per_item > 0` — spread covers the (floored, 5M-capped) 2% tax
- `low_price > 100` — sub-100gp junk excluded
- `volume_per_hour > 0` — traded at least once in the last completed hour
  (a loose, price-agnostic floor that keeps dead items out)

Everything else — how much volume is "enough," acceptable time-to-fill, volatility
tolerance — is yours to decide, per lane.

## New column

| Column | Type | Position | Meaning |
|--------|------|----------|---------|
| `is_high_value` | boolean | **last** | `high_price >= 1,000,000` (threshold tunable server-side via the `high_value_threshold_gp` dbt var). Flags expensive, typically low-volume gear — your separate lane. |

No other columns changed; order is preserved (only appended). `tax_gp` is still
`floor(2% × high_price)` capped at `5,000,000` (verified on billion-gp items like
Twisted bow → `tax_gp = 5,000,000`).

## Gating the two lanes

- **Standard lane** (`NOT is_high_value`): existing logic; these still tend to be
  high-volume. The 5m volumes (`high_price_volume`, `low_price_volume`) are most
  relevant here.
- **High-value lane** (`is_high_value`): gate liquidity on `volume_per_hour` /
  `avg_volume_per_hour_24h` and `est_hours_to_fill_limit` — 5m volume is usually 0
  for these, so don't gate on it. These items have small `buy_limit`s but often
  decent hourly volume, so they frequently fill fast (e.g. Bandos tassets showed
  `est_hours_to_fill_limit ~ 0.1`). `mid_volatility_1h` / `mid_volatility_pct_1h`
  help with sizing/risk here.

## Columns available for gating (all pre-existing)

`volume_per_hour`, `avg_volume_per_hour_24h`, `est_hours_to_fill_limit`,
`high_price_volume`, `low_price_volume`, `mid_volatility_1h`,
`mid_volatility_pct_1h`, `price_updated_at` (price freshness), `buy_limit`.

## Gotcha (not a bug)

An item with good volume can still be **absent** if its current spread is below
the 2% tax (net-negative). Example: Osmumten's fang — ~114 trades/hr, but spread
~102k < tax ~410k at the time of writing, so it's filtered by `profit_per_item >
0`. It reappears the moment its spread beats tax.
