from pathlib import Path

from dagster import (
    AssetSelection,
    Definitions,
    ScheduleDefinition,
    define_asset_job,
)
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

from ge_pipe.dagster_defs.assets import (
    item_mapping,
    prices_1h,
    prices_5m,
    prices_latest,
)

DBT_PROJECT_DIR = Path(__file__).parent.parent.parent / "dbt"
dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR, prepare_project_cli_args=["parse"])

# Hard cap on run duration. Normal runs finish in ~25s; a run still going after
# this is wedged (almost always orphaned by a dagster restart/crash, since this
# `dagster dev` setup uses DefaultRunLauncher which does NOT support run-worker
# health checks — so run_monitoring can't detect a dead worker on a STARTED run).
# The monitoring daemon enforces this purely on elapsed time, so it reaps such
# runs regardless, freeing the slot. Applied to every scheduled job via tags.
RUN_TIMEOUT_TAGS = {"dagster/max_runtime": 300}


@dbt_assets(manifest=dbt_project.manifest_path)
def ge_pipe_dbt_assets(context, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


# Jobs
prices_5m_job = define_asset_job(
    "prices_5m_job",
    # Load raw prices then immediately rebuild all downstream dbt marts
    selection=AssetSelection.assets(prices_5m).downstream(include_self=True),
    tags=RUN_TIMEOUT_TAGS,
)

daily_job = define_asset_job(
    "daily_job",
    selection=AssetSelection.assets(item_mapping).downstream(include_self=True),
    tags=RUN_TIMEOUT_TAGS,
)

prices_latest_job = define_asset_job(
    "prices_latest_job",
    # Load real-time prices then refresh only the downstream dbt models that
    # depend on them (stg_prices_latest + agg_flip_opportunities) — not the
    # whole project. fct_prices/dim_items are reused as-is.
    selection=AssetSelection.assets(prices_latest).downstream(include_self=True),
    tags=RUN_TIMEOUT_TAGS,
)

prices_1h_job = define_asset_job(
    "prices_1h_job",
    # Load hourly volume then refresh the liquidity mart (and the flip mart that
    # joins it).
    selection=AssetSelection.assets(prices_1h).downstream(include_self=True),
    tags=RUN_TIMEOUT_TAGS,
)

# Schedules
prices_5m_schedule = ScheduleDefinition(
    name="prices_5m_schedule",
    job=prices_5m_job,
    cron_schedule="*/5 * * * *",
)

prices_latest_schedule = ScheduleDefinition(
    name="prices_latest_schedule",
    job=prices_latest_job,
    cron_schedule="* * * * *",  # every minute
)

prices_1h_schedule = ScheduleDefinition(
    name="prices_1h_schedule",
    job=prices_1h_job,
    cron_schedule="2 * * * *",  # 2 min past each hour (let the bucket settle)
)

daily_schedule = ScheduleDefinition(
    name="daily_schedule",
    job=daily_job,
    cron_schedule="0 1 * * *",  # 01:00 UTC daily
)

defs = Definitions(
    assets=[item_mapping, prices_5m, prices_latest, prices_1h, ge_pipe_dbt_assets],
    resources={
        "dbt": DbtCliResource(project_dir=dbt_project),
    },
    schedules=[
        prices_5m_schedule,
        prices_latest_schedule,
        prices_1h_schedule,
        daily_schedule,
    ],
)
