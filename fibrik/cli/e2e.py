"""`fibrik e2e` -- the walking skeleton's end-to-end check
(execution-plan.md §2.3 task 5 exit criteria, adapted for ADR-25's
Kafka-free/Trino-free stack): send N synthetic sshd events, assert they
land in ClickHouse, force a lake-writer pass, assert Iceberg grew too.
`make e2e` runs this inside the cluster (same `fibrik:dev` image as the
lake-writer Deployment), since it needs to reach Vector/ClickHouse/
Lakekeeper by their in-cluster Service names.
"""

from __future__ import annotations

import logging
import time

import clickhouse_connect
import typer

from fibrik.lake.seed import send as seed_send
from fibrik.lake.writer import LakeWriterConfig, count_rows, run_once

app = typer.Typer(help="End-to-end pipeline check.")

logger = logging.getLogger("fibrik.e2e")


@app.callback(invoke_without_command=True)
def e2e(
    vector_host: str = typer.Option("fibrik-vector", envvar="VECTOR_HOST"),
    vector_port: int = typer.Option(5514, envvar="VECTOR_SYSLOG_PORT"),
    events: int = typer.Option(20, help="Number of synthetic sshd events to send."),
    table: str = typer.Option("ocsf_authentication"),
    clickhouse_host: str = typer.Option("fibrik-clickhouse", envvar="CLICKHOUSE_HOST"),
    clickhouse_port: int = typer.Option(8123, envvar="CLICKHOUSE_PORT"),
    clickhouse_user: str = typer.Option("fibrik", envvar="CLICKHOUSE_USER"),
    clickhouse_password: str = typer.Option(..., envvar="CLICKHOUSE_PASSWORD"),
    clickhouse_database: str = typer.Option("fibrik", envvar="CLICKHOUSE_DATABASE"),
    lakekeeper_uri: str = typer.Option(
        "http://fibrik-lakekeeper:8181/catalog/", envvar="LAKEKEEPER_URI"
    ),
    lakekeeper_warehouse: str = typer.Option("gold", envvar="LAKEKEEPER_WAREHOUSE"),
    wait_seconds: int = typer.Option(120, help="Max seconds to wait for ClickHouse to catch up."),
) -> None:
    """Exits non-zero (and prints why) on the first failed check."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    ch = clickhouse_connect.get_client(
        host=clickhouse_host, port=clickhouse_port,
        username=clickhouse_user, password=clickhouse_password,
        database=clickhouse_database,
    )
    before = ch.query(f"SELECT count() FROM {table}").result_rows[0][0]
    logger.info("e2e: %s has %d row(s) before seeding", table, before)

    sent = seed_send(vector_host, vector_port, events)
    logger.info("e2e: sent %d synthetic sshd event(s) to %s:%s", sent, vector_host, vector_port)

    target = before + sent
    waited = 0
    after = before
    while waited < wait_seconds:
        after = ch.query(f"SELECT count() FROM {table}").result_rows[0][0]
        logger.info("e2e: %s now has %d row(s) (want >= %d)", table, after, target)
        if after >= target:
            break
        time.sleep(5)
        waited += 5

    if after < target:
        typer.echo(
            f"FAIL: {table} has {after} rows after {wait_seconds}s, wanted >= {target}", err=True
        )
        raise typer.Exit(code=1)
    typer.echo(f"OK: {table} reached {after} rows ({sent} new) in ClickHouse")

    cfg = LakeWriterConfig(
        clickhouse_host=clickhouse_host, clickhouse_port=clickhouse_port,
        clickhouse_user=clickhouse_user, clickhouse_password=clickhouse_password,
        clickhouse_database=clickhouse_database, lakekeeper_uri=lakekeeper_uri,
        lakekeeper_warehouse=lakekeeper_warehouse, tables=[table],
    )
    iceberg_before = count_rows(cfg, table)
    run_once(cfg)
    iceberg_after = count_rows(cfg, table)
    logger.info("e2e: gold.%s went from %d to %d row(s) in Iceberg", table, iceberg_before, iceberg_after)
    if iceberg_after <= iceberg_before:
        typer.echo(
            f"FAIL: gold.{table} didn't grow after a lake write pass "
            f"({iceberg_before} -> {iceberg_after})",
            err=True,
        )
        raise typer.Exit(code=1)
    typer.echo(f"OK: gold.{table} reached {iceberg_after} rows in Iceberg")

    # Informational only: cost_ledger only fills in on Vector's 5-minute
    # aggregate flush (vector.yaml's cost_metrics_agg), far longer than this
    # check should block on -- report what's there now, don't require it.
    cost_rows = ch.query("SELECT count() FROM cost_ledger").result_rows[0][0]
    typer.echo(f"INFO: cost_ledger has {cost_rows} row(s) so far (fills in every 5 minutes)")

    typer.echo("e2e: PASS")
