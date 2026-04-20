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
     │  /5m      (every 5 min)
     ▼
Python Extractors ──► PostgreSQL (raw schema)
                              │
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
SELECT item_name, avg_low_price, avg_high_price, profit_per_item, max_profit_per_limit
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

### Staging (`stg` schema)

Views over raw — type-cast, renamed, lightly cleaned. No business logic.

- `stg_item_mapping` — renamed columns, null semantics
- `stg_prices_5m` — adds `spread_gp`, `spread_pct` derived columns; drops fully-null rows

### Marts (`marts` schema)

Materialized tables. Query these.

| Model | Description |
|-------|-------------|
| `dim_items` | Item dimension — name, members flag, alch values, buy limit |
| `fct_prices` | Star schema fact — price snapshots joined to dim_items |
| `agg_flip_opportunities` | Current best flips: spread > GE tax, sufficient volume on both sides |

---

## Schedules

| Schedule | Cadence | What it runs |
|----------|---------|--------------|
| `prices_5m_schedule` | Every 5 min | Extract + load `/5m` |
| `daily_schedule` | 01:00 UTC | Full refresh: `/mapping` + `dbt build` |

---

## Data Quality

dbt tests run on every `dbt build`:

- **Source freshness** — errors if `raw.prices_5m` hasn't been updated in 60+ minutes
- **not_null / unique** — on all primary keys and required fields
- **Referential integrity** — `fct_prices` only contains items in `dim_items`
- **Composite uniqueness** — `(item_id, price_timestamp)` in `fct_prices`
- **Price sanity** — custom test: `avg_high_price >= avg_low_price` (inverted prices = bad data)

---

## Configuration

Copy `.env.example` to `.env` and override as needed:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_HOST` | `localhost` | Postgres host (use `postgres` inside Docker) |
| `POSTGRES_PORT` | `5432` | Postgres port |
| `POSTGRES_USER` | `gepipe` | Postgres username |
| `POSTGRES_PASSWORD` | `gepipe` | Postgres password |
| `POSTGRES_DB` | `ge_pipe` | Database name |

---

## Tech Stack

| Layer | Tool | Why |
|-------|------|-----|
| Extract / Load | Python + httpx | Async, typed, no Airbyte overhead for 2 endpoints |
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
