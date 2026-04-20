.PHONY: up down build logs dbt-run dbt-test dbt-docs test fresh-start

up:
	docker compose up -d

down:
	docker compose down

build:
	docker compose build

logs:
	docker compose logs -f dagster

dbt-run:
	cd dbt && dbt run

dbt-test:
	cd dbt && dbt test

dbt-docs:
	cd dbt && dbt docs generate && dbt docs serve

test: dbt-test

fresh-start: down
	docker compose down -v
	docker compose up -d --build
