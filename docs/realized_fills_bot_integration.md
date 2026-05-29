# Sending `realized_fills` to the pipeline (bot integration)

Hand this to the bot. It's the complete contract for writing trade outcomes into
`raw.realized_fills`, which `dbt` models into `marts.realized_fills` (the feedback
loop: realized-vs-predicted profit, actual vs estimated fill time, slippage,
fill/cancel rates by cadence).

## Connection rules (important)

- **Use a separate, dedicated write connection** — never the opportunity-fetch
  connection, which is `setReadOnly(true)`. Writes on a read-only connection fail,
  and more importantly we want fill-writes off the read path entirely.
- **Autocommit, short-lived.** Open → `INSERT` → commit immediately (or use a tiny
  dedicated pool with autocommit on). Never hold a transaction open across the
  monitor loop — a long write transaction can take locks that stall reads.
- **DSN:** `postgresql://gepipe:gepipe@localhost:5432/ge_pipe` (bot and DB are
  colocated). Target table: `raw.realized_fills`.

## The write

One row per fill/cancel event. **Do not** set `event_id` or `recorded_at` — the DB
assigns them.

```sql
INSERT INTO raw.realized_fills
  (flip_id, leg, item_id, bot_version, event,
   requested_qty, filled_qty, offer_price, avg_fill_price,
   tax_paid, realized_profit, offer_placed_at, filled_at,
   monitor_ms, tolerance_ms, relist_count)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
```

JDBC sketch (mirrors your existing client style):

```java
// write conn: read-write, autoCommit=true, NOT the readOnly fetch connection
try (PreparedStatement ps = writeConn.prepareStatement(INSERT_SQL)) {
    ps.setString(1, flipId);
    ps.setString(2, leg);                 // "buy" | "sell"
    ps.setInt(3, itemId);
    ps.setString(4, botVersion);
    ps.setString(5, event);               // see enum below
    ps.setObject(6, requestedQty, Types.INTEGER);
    ps.setObject(7, filledQty,    Types.INTEGER);
    ps.setObject(8, offerPrice,   Types.INTEGER);
    ps.setObject(9, avgFillPrice, Types.NUMERIC);   // null if nothing filled
    ps.setObject(10, taxPaid,        Types.INTEGER); // sells only, else null
    ps.setObject(11, realizedProfit, Types.BIGINT);  // sells only, else null
    ps.setObject(12, Timestamp.from(offerPlacedAt));
    ps.setObject(13, filledAt == null ? null : Timestamp.from(filledAt)); // null on cancel
    ps.setObject(14, monitorMs,   Types.INTEGER);
    ps.setObject(15, toleranceMs, Types.INTEGER);
    ps.setObject(16, relistCount, Types.INTEGER);
    ps.executeUpdate();
}
```

## Columns

| Column | Type | Meaning |
|--------|------|---------|
| `flip_id` | text, **required** | Stable id grouping both legs of a round-trip. |
| `leg` | text, **required** | `buy` or `sell` (exact strings). |
| `item_id` | int, **required** | OSRS item id. |
| `bot_version` | text | e.g. `v1.2` — lets us segment metrics by bot build. |
| `event` | text, **required** | One of `filled`, `partial`, `cancelled_deadline`, `cancelled_pricemove`, `cancelled_manual`. |
| `requested_qty` | int | Offer quantity. |
| `filled_qty` | int | `getTransferredAmount()`. On a partial-then-cancelled leg, send the filled portion (> 0) with the `cancelled_*` event and `filled_at = null`. |
| `offer_price` | int | Listed price per item. |
| `avg_fill_price` | numeric | Buys: `getTransferredValue() / filled_qty` (captures fills below your bid). Sells: the listed ask (the GE fills sells at your price), consistent with how `tax_paid`/`realized_profit` are computed. Null if nothing filled. |
| `tax_paid` | int | Sells only (closing leg); null otherwise. |
| `realized_profit` | bigint | Sells only: proceeds − cost − tax. Null otherwise. |
| `offer_placed_at` | timestamptz | When the offer was listed (UTC). |
| `filled_at` | timestamptz | When it completed; **null on cancel**. |
| `monitor_ms` | int | Monitor poll interval used. |
| `tolerance_ms` | int | Price-move tolerance used. |
| `relist_count` | int | Times the leg was relisted. |
| `event_id` | — | **DB-assigned, do not send.** |
| `recorded_at` | — | **DB-assigned, do not send.** |

## Enum values (exact)

- `leg`: `buy`, `sell`
- `event`: `filled`, `partial`, `cancelled_deadline`, `cancelled_pricemove`, `cancelled_manual`

These are validated by dbt `accepted_values` tests, **not** a DB `CHECK` — a typo
won't reject the insert, it'll silently land and then fail a data-quality test. So
send the exact strings.

## When to emit (lifecycle hooks)

One row per event, hooked into the existing lifecycle:

- `recordBought` / `recordSold` → `event = filled` (full) or `partial`.
- partial-fill detection → `event = partial` (with `filled_qty < requested_qty`).
- `cancelBuy` / `cancelSell` on deadline → `event = cancelled_deadline`.
- `cancelBuy` / `cancelSell` on adverse price move → `event = cancelled_pricemove`.
- forced/manual cancel not tied to deadline or price move (e.g. a buy cancelled by
  a sell-only wind-down) → `event = cancelled_manual`. Keep these out of
  `cancelled_deadline` so the deadline-cancel rate stays a clean cadence signal.
- `reconcile` → emit the terminal event observed for the leg.

A leg that partially filled and was then cancelled is reported as the `cancelled_*`
event with `filled_qty > 0` and `filled_at = null`; for sells, `tax_paid` /
`realized_profit` reflect only the filled portion. Downstream, `fill_ratio`
(filled/requested) is the source of truth for how much filled — not the event
string. Note `slippage_gp` is a **buy-side** measure: sells fill at the listed ask,
so it's ~0 on sells by construction; the sell-side outcome is in `realized_profit`.

## Conventions

- **Timestamps in UTC** (`timestamptz`). Epoch millis are fine if converted on write.
- **Nulls, not zeros**, for inapplicable fields (e.g. `avg_fill_price`/`filled_at`
  on a 0-fill cancel; `tax_paid`/`realized_profit` on buys).
- **Emit each event exactly once.** The table is append-only with a surrogate key;
  if you add write-retry on connection failure, dedupe at the source so a retry
  can't double-insert. (If that ever gets hard, we can add an optional
  `event_uid` unique column for idempotent upserts — ask and we'll add it.)

## Verify it's landing

```sql
SELECT count(*) FROM raw.realized_fills;
SELECT flip_id, leg, item_name, event, fill_ratio, slippage_gp,
       time_to_fill_hours, realized_profit
FROM   marts.realized_fills
ORDER  BY recorded_at DESC
LIMIT  10;
```

`marts.realized_fills` is a view, so rows appear the moment your insert commits —
no pipeline run needed.
