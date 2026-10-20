"""`fibrik lake ...` -- the MVP Iceberg lake writer (execution-plan.md §2.3)."""

from __future__ import annotations

import logging

import typer

from fibrik.lake.writer import LakeWriterConfig, count_rows, run_forever, run_once

app = typer.Typer(help="Iceberg lake writer and table management.")


@app.command("write")
def write(
    clickhouse_host: str = typer.Option("localhost", envvar="CLICKHOUSE_HOST"),
    clickhouse_port: int = typer.Option(8123, envvar="CLICKHOUSE_PORT"),
    clickhouse_user: str = typer.Option("fibrik", envvar="CLICKHOUSE_USER"),
    clickhouse_password: str = typer.Option(..., envvar="CLICKHOUSE_PASSWORD"),
    clickhouse_database: str = typer.Option("fibrik", envvar="CLICKHOUSE_DATABASE"),
    lakekeeper_uri: str = typer.Option(
        "http://fibrik-lakekeeper:8181/catalog/", envvar="LAKEKEEPER_URI"
    ),
    lakekeeper_warehouse: str = typer.Option("gold", envvar="LAKEKEEPER_WAREHOUSE"),
    tables: str = typer.Option(
        "ocsf_authentication",
        "--tables",
        help="Comma-separated ClickHouse table names to poll and mirror into Iceberg.",
    ),
    batch_seconds: int = typer.Option(
        60, help="Seconds between poll/write passes (execution-plan.md §2.1's --batch-seconds)."
    ),
    batch_size: int = typer.Option(10_000, help="Max rows fetched per table per pass."),
    once: bool = typer.Option(
        False, help="Run a single poll/write pass and exit, instead of looping forever."
    ),
) -> None:
    """Consume new ClickHouse OCSF rows and append them to Iceberg via the
    Lakekeeper REST catalog -- the walking skeleton's lake-writer Deployment
    runs this with `once=False` (deploy/helm/fibrik/templates/lake-writer.yaml);
    `make e2e` runs it with `--once` so the test doesn't hang on the loop.
    """
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = LakeWriterConfig(
        clickhouse_host=clickhouse_host,
        clickhouse_port=clickhouse_port,
        clickhouse_user=clickhouse_user,
        clickhouse_password=clickhouse_password,
        clickhouse_database=clickhouse_database,
        lakekeeper_uri=lakekeeper_uri,
        lakekeeper_warehouse=lakekeeper_warehouse,
        tables=[t.strip() for t in tables.split(",") if t.strip()],
        batch_seconds=batch_seconds,
        batch_size=batch_size,
    )
    if once:
        written = run_once(cfg)
        typer.echo(f"wrote={written}")
    else:
        run_forever(cfg)


@app.command("count")
def count(
    table: str = typer.Argument(..., help="Table name, e.g. ocsf_authentication."),
    lakekeeper_uri: str = typer.Option(
        "http://fibrik-lakekeeper:8181/catalog/", envvar="LAKEKEEPER_URI"
    ),
    lakekeeper_warehouse: str = typer.Option("gold", envvar="LAKEKEEPER_WAREHOUSE"),
) -> None:
    """Print the current row count of gold.<table> in Iceberg. Doesn't touch
    ClickHouse -- used by `make e2e` to verify the lake writer's output
    without guessing at ClickHouse's Iceberg-table-function syntax.
    """
    # ClickHouse fields are unused by count_rows but LakeWriterConfig
    # requires them; empty placeholders are fine since no ClickHouse
    # connection is opened on this path.
    cfg = LakeWriterConfig(
        clickhouse_host="", clickhouse_port=0, clickhouse_user="", clickhouse_password="",
        clickhouse_database="", lakekeeper_uri=lakekeeper_uri,
        lakekeeper_warehouse=lakekeeper_warehouse,
    )
    typer.echo(str(count_rows(cfg, table)))
