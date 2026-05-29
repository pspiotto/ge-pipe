#!/usr/bin/env bash
set -euo pipefail

# The compose file bind-mounts the project root over /app (./:/app), which hides
# everything the Dockerfile built into /app — including DAGSTER_HOME, the dbt
# packages, and the compiled dbt manifest. Those paths are also gitignored, so on
# a fresh clone they don't exist on the host either. Recreate them on every start
# so `docker compose up` works first-try without manual steps.

DAGSTER_HOME="${DAGSTER_HOME:-/app/.dagster}"

# 1. Dagster instance home + config
mkdir -p "$DAGSTER_HOME"
if [ ! -f "$DAGSTER_HOME/dagster.yaml" ]; then
  cp /app/dagster.yaml "$DAGSTER_HOME/dagster.yaml"
fi

# 2. dbt packages (dbt_utils etc.) and 3. compiled manifest.json — the dbt code
# location fails to load without manifest.json present at import time.
# Also load seeds (e.g. tax_exempt_items) so models that ref them can build even
# when the first scheduled job is a selective (non-seed) build.
cd /app/dbt
dbt deps
dbt seed --profiles-dir /app/dbt
dbt parse --profiles-dir /app/dbt
cd /app

exec dagster dev -h 0.0.0.0 -p 3000 -w /app/workspace.yaml
