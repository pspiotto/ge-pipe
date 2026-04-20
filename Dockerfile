FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

# Create Dagster home
ENV DAGSTER_HOME=/app/.dagster
RUN mkdir -p $DAGSTER_HOME

COPY dagster.yaml $DAGSTER_HOME/dagster.yaml

COPY . .
