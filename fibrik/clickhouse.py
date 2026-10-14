"""ClickHouse access: the hot store for search and the cost ledger."""

import clickhouse_connect
from clickhouse_connect.driver.client import Client

from fibrik.settings import Settings


def connect(s: Settings, database: str | None = None) -> Client:
    scheme, rest = s.clickhouse_url.split("://", 1)
    host, _, port = rest.rstrip("/").partition(":")
    return clickhouse_connect.get_client(
        host=host,
        port=int(port or (8443 if scheme == "https" else 8123)),
        secure=scheme == "https",
        username=s.clickhouse_user,
        password=s.clickhouse_password,
        database=database or "default",
    )


def migrate(s: Settings) -> None:
    """Create the database and tables. Safe to run on every start."""
    client = connect(s)
    db = s.clickhouse_database
    client.command(f"CREATE DATABASE IF NOT EXISTS {db}")
    # One row per event, as normalized by Vector (deploy/helm/fibrik/files/
    # normalize.vrl). OCSF columns join this table from week 2.
    client.command(
        f"""
        CREATE TABLE IF NOT EXISTS {db}.raw_logs (
            event_time  DateTime64(3, 'UTC'),
            ingest_time DateTime64(3, 'UTC'),
            source      LowCardinality(String),
            host        LowCardinality(String),
            app         LowCardinality(String),
            severity    LowCardinality(String),
            body        String,
            attributes  String
        )
        ENGINE = MergeTree
        PARTITION BY toDate(event_time)
        ORDER BY (source, event_time)
        TTL toDateTime(event_time) + INTERVAL {int(s.hot_ttl_days)} DAY
        """
    )


def raw_log_count(s: Settings) -> int:
    return int(connect(s, s.clickhouse_database).command("SELECT count() FROM raw_logs"))
