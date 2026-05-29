# ge-pipe

> ELT pipeline for the Grand Exchange. No bots required.

Real-time price data from the [OSRS Wiki prices API](https://prices.runescape.wiki/api/v1) — extracted every 5 minutes, loaded into PostgreSQL, transformed with dbt, orchestrated with Dagster.

Built because I wanted an end-to-end DE project I'd actually use, and because watching flip margins in a `psql` session is more satisfying than refreshing the GE tracker.

---

## Architecture

```
OSRS Wiki API
     │
     │  /mapping (daily)
     │  /5m      (every 5 min — volume)
     │  /1h      (hourly — liquidity)
     │  /latest  (every 1 min — real-time prices)
     ▼
Python Extractors ──► PostgreSQL (raw schema) ◄── Bot writes realized_fills
                              │                     (feedback loop)
                         dbt build
                              │
                    ┌─────────┴──────────┐
                    │                    │
               stg schema          marts schema
               (views)             (tables)
                    │                    │
                    └─────────┬──────────┘
                              │
                         Dagster UI
                    (lineage, schedules,
                      asset health)
```

Everything runs in Docker Compose. One command.

---

## Quickstart

**Requires:** [Docker Desktop](https://docs.docker.com/desktop/) — available for Mac, Windows, and Linux.

> **First run:** the Docker image build takes 3–5 minutes (Python + dbt + Dagster). Subsequent starts are instant.

### Mac / Linux

```bash
git clone https://github.com/pspiotto/ge-pipe
cd ge-pipe
cp .env.example .env
make up
```

### Windows

`make` isn't available in PowerShell/cmd by default. Use **WSL2** (Docker Desktop installs it anyway — just open a WSL terminal) or run the Docker Compose commands directly in PowerShell:

```powershell
git clone https://github.com/pspiotto/ge-pipe
cd ge-pipe
copy .env.example .env          # or: cp .env.example .env in WSL
docker compose up -d --build
```

> If you hit `"C:\ProgramData\DockerDesktop must be owned by an elevated account"` during Docker Desktop install: open an elevated PowerShell and run `rmdir /s /q C:\ProgramData\DockerDesktop`, then re-run the installer.

### Once running

| Service | URL |
|---------|-----|
| Dagster UI | http://localhost:3000 |
| PostgreSQL | `localhost:5432` · db: `ge_pipe` · user: `gepipe` |

On first run, Dagster compiles the dbt manifest automatically. Kick off the assets manually in the UI or wait for the schedules to fire.

### Troubleshooting

**Port 5432 already allocated.** Another Postgres (or container) on the host is using `5432`. Either stop it, or publish ge-pipe's Postgres on a different host port by setting `POSTGRES_PORT=5433` in `.env` (internal Docker networking is unaffected — only host-side `psql` moves to the new port).

**Postgres can't be reached / a container won't attach to the network.** If a previous failed start left a container half-created, recreate cleanly:

```bash
docker compose up -d --force-recreate
```

The `pg_data` volume persists, so your schemas and data are kept.

---

## Development

### Mac / Linux (`make` commands)

```bash
make up           # start Postgres + Dagster (detached)
make logs         # stream Dagster logs
make dbt-run      # run dbt transformations manually
make dbt-test     # run dbt tests
make dbt-docs     # generate + serve dbt docs at localhost:8080
make test         # alias for dbt-test
make fresh-start  # wipe volumes, rebuild, restart
```

### Windows (Docker Compose equivalents)

```powershell
docker compose up -d             # make up
docker compose logs -f dagster   # make logs
docker compose exec dagster dbt run --project-dir /app/dbt   # make dbt-run
docker compose exec dagster dbt test --project-dir /app/dbt  # make dbt-test
docker compose down -v && docker compose up -d --build       # make fresh-start
```

### Connect to the database

```bash
psql "postgresql://gepipe:gepipe@localhost:5432/ge_pipe"
```

```sql
-- What are the best flips right now?
SELECT item_name, low_price, high_price, profit_per_item, max_profit_per_limit
FROM marts.agg_flip_opportunities
LIMIT 20;
```

---

## Data Model

Three-layer architecture: raw → staging → marts.

### Raw (`raw` schema)

Loaded directly by Python — no transforms, no opinions.

| Table | Source | Grain | Cadence |
|-------|--------|-------|---------|
| `item_mapping` | `/mapping` | 1 row per item | Daily full refresh |
| `prices_5m` | `/5m` | 1 row per item per 5-min window | Every 5 minutes |
| `prices_1h` | `/1h` | 1 row per item per 1-hour window | Hourly |
| `prices_latest` | `/latest` | 1 row per item per price change | Every 1 minute (appended on change) |
| `realized_fills` | the bot | 1 row per fill/cancel event | Written by the bot (append-only) |

### Staging (`stg` schema)

Views over raw — type-cast, renamed, lightly cleaned. No business logic.

- `stg_item_mapping` — renamed columns, null semantics
- `stg_prices_5m` — adds `spread_gp`, `spread_pct` derived columns; drops fully-null rows
- `stg_prices_latest` — same derived columns over the real-time `/latest` feed
- `stg_prices_1h` — adds `total_volume` (high + low) over the hourly `/1h` feed
- `stg_realized_fills` — adds `fill_ratio`, `slippage_gp`, `time_to_fill_seconds`, and `is_filled`/`is_cancelled` flags over the bot's fill events

### Marts (`marts` schema)

Query these. `dim_items` and `fct_prices` are tables; `agg_flip_opportunities` is a view (rebuilt every minute and read continuously, so a view avoids per-minute table-rebuild lock contention).

| Model | Materialization | Description |
|-------|-----------------|-------------|
| `dim_items` | table | Item dimension — name, members flag, alch values, buy limit, `is_tax_exempt` |
| `fct_prices` | table | Star schema fact — 5-minute price snapshots joined to dim_items |
| `agg_item_liquidity` | table | Per-item hourly liquidity (from `/1h`): `volume_per_hour`, rolling `avg_volume_per_hour_24h`. Refreshed hourly. |
| `agg_item_volatility` | table | Per-item short-horizon volatility (from 5m history): `mid_volatility_1h` (stddev of mid, gp) + scale-free `mid_volatility_pct_1h`. Refreshed every 5 min. |
| `agg_flip_opportunities` | view | Current best flips: **real-time** (`/latest`) prices for the spread, gated on recent 5-minute volume. Also carries `volume_per_hour`, `avg_volume_per_hour_24h`, `est_hours_to_fill_limit` (time-to-fill), and `mid_volatility_1h`/`mid_volatility_pct_1h` (spread-sizing). |
| `realized_fills` | view | **Feedback loop** — bot trade outcomes (one row per fill/cancel), enriched with `item_name`, `fill_ratio`, `slippage_gp`, and `time_to_fill_hours` (directly comparable to `est_hours_to_fill_limit`). |

**GE tax:** `floor(2% of the sale (high) price)`, capped at 5,000,000 gp — floored to match the in-game round-down. Items are untaxed when intrinsically exempt (tools/bonds — see the `tax_exempt_items` seed) or when they sell for under 50 gp. The exempt list is maintained in `dbt/seeds/tax_exempt_items.csv` — **verify it against the current [OSRS Wiki GE tax page](https://oldschool.runescape.wiki/w/Grand_Exchange#Tax)**, since exemptions can change with game updates.

### Feedback loop (`realized_fills`)

The bot closes the loop by writing its trade outcomes back into `raw.realized_fills`, which `dbt` models into `marts.realized_fills`. This makes realized-vs-predicted profit, actual vs estimated fill time, slippage, and fill/cancel rates by cadence all queryable.

**Write contract:** the bot appends one row per fill/cancel event over a **separate, short-lived autocommit connection**, kept entirely off its read path (which is `setReadOnly(true)`), so fill-writes can never lock or stall opportunity fetches. `event_id` and `recorded_at` are assigned by the DB; the bot supplies the rest. `leg` ∈ {`buy`,`sell`}; `event` ∈ {`filled`,`partial`,`cancelled_deadline`,`cancelled_pricemove`} (validated by dbt `accepted_values` tests, not a DB `CHECK`, so a stray value surfaces as a failing test rather than a rejected write). See `init_db/004_create_realized_fills.sql` for the full field→source mapping.

> No new schedule — `realized_fills` is a view, so it reflects the bot's writes immediately and is kept in sync by the daily `dbt build`.

---

## Schedules

| Schedule | Cadence | What it runs |
|----------|---------|--------------|
| `prices_latest_schedule` | Every 1 min | Extract + load `/latest`, then refresh `stg_prices_latest` + `agg_flip_opportunities` |
| `prices_5m_schedule` | Every 5 min | Extract + load `/5m` (volume), refresh `fct_prices` |
| `prices_1h_schedule` | Hourly (:02) | Extract + load `/1h`, refresh `agg_item_liquidity` |
| `daily_schedule` | 01:00 UTC | Full refresh: `/mapping` + `dbt build` |

> The queue runs up to 2 concurrent slots (`max_concurrent_runs: 2`) so the per-minute flip refresh keeps flowing even while a slower job runs. Orphaned/stuck runs are reaped by Dagster `run_monitoring`, and marts table rebuilds carry a `lock_timeout` so they fail fast rather than wedge the queue.

---

## Data Quality

dbt tests run on every `dbt build`:

- **Source freshness** — errors if `raw.prices_5m` is 60+ min stale, `raw.prices_latest` is 30+ min stale, or `raw.prices_1h` is 180+ min stale
- **not_null / unique** — on all primary keys and required fields
- **Referential integrity** — `fct_prices` only contains items in `dim_items`
- **Composite uniqueness** — `(item_id, price_timestamp)` in `fct_prices`
- **Price sanity** — custom test: `avg_high_price >= avg_low_price` (inverted prices = bad data)

---

## Configuration

Copy `.env.example` to `.env` and override as needed:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_HOST` | `postgres` | Postgres host — the compose service name inside Docker. Use `localhost` only for host-side connections. |
| `POSTGRES_PORT` | `5432` | Postgres port |
| `POSTGRES_USER` | `gepipe` | Postgres username |
| `POSTGRES_PASSWORD` | `gepipe` | Postgres password |
| `POSTGRES_DB` | `ge_pipe` | Database name |

---

## Tech Stack

| Layer | Tool | Why |
|-------|------|-----|
| Extract / Load | Python + httpx | Async, typed, no Airbyte overhead for a handful of endpoints |
| Warehouse | PostgreSQL 16 | Runs anywhere. Real warehouse patterns without a cloud account. |
| Transform | dbt-core (postgres) | Industry standard. Models are SQL you can actually read. |
| Orchestration | Dagster | Asset-based lineage, modern scheduler, better portfolio signal than an Airflow DAG. |
| Containerization | Docker Compose | One command. No "works on my machine." |

---

## Roadmap

- [ ] Evidence.dev dashboard — SQL-first BI deployed as a static site
- [ ] `/timeseries` backfill — historical price data per item
- [ ] `/1h` endpoint — hourly window alongside 5-minute
- [ ] Price spike alerting — Dagster sensor → Discord webhook
- [ ] Snowflake dual-target — dbt profile for Snowflake alongside Postgres
- [ ] GitHub Actions CI — dbt compile + test on every push

---

## License

MIT
