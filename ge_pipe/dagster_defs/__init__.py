from pathlib import Path

from dagster import (
    AssetSelection,
    Definitions,
    ScheduleDefinition,
    define_asset_job,
)
from dagster_dbt import DbtCliResource, DbtProject, dbt_assets

from ge_pipe.dagster_defs.assets import item_mapping, prices_5m, prices_latest

DBT_PROJECT_DIR = Path(__file__).parent.parent.parent / "dbt"
dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR, prepare_project_cli_args=["parse"])


@dbt_assets(manifest=dbt_project.manifest_path)
def ge_pipe_dbt_assets(context, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


# Jobs
prices_5m_job = define_asset_job(
    "prices_5m_job",
    # Load raw prices then immediately rebuild all downstream dbt marts
    selection=AssetSelection.assets(prices_5m).downstream(include_self=True),
)

daily_job = define_asset_job(
    "daily_job",
    selection=AssetSelection.assets(item_mapping).downstream(include_self=True),
)

prices_latest_job = define_asset_job(
    "prices_latest_job",
    # Load real-time prices then refresh only the downstream dbt models that
    # depend on them (stg_prices_latest + agg_flip_opportunities) — not the
    # whole project. fct_prices/dim_items are reused as-is.
    selection=AssetSelection.assets(prices_latest).downstream(include_self=True),
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

daily_schedule = ScheduleDefinition(
    name="daily_schedule",
    job=daily_job,
    cron_schedule="0 1 * * *",  # 01:00 UTC daily
)

defs = Definitions(
    assets=[item_mapping, prices_5m, prices_latest, ge_pipe_dbt_assets],
    resources={
        "dbt": DbtCliResource(project_dir=dbt_project),
    },
    schedules=[prices_5m_schedule, prices_latest_schedule, daily_schedule],
)
