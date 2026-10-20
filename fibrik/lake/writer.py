"""Polls ClickHouse OCSF tables and appends new rows to Iceberg via PyIceberg
against the Lakekeeper REST catalog (execution-plan.md §2.3 task 3: "the MVP
lake writer... consume ocsf.*, micro-batch to Arrow, write with pyiceberg to
gold.ocsf_<class>"). Originally spec'd as a Kafka consumer; this walking
skeleton has no Kafka (ADR-25), so it polls ClickHouse -- already the first
landing place for every mapped OCSF row -- by a stored watermark instead.

API shapes used here (clickhouse_connect.get_client/query_arrow/insert,
pyiceberg.catalog.load_catalog/create_table/table.append) were checked
against the installed clickhouse-connect wheel and PyIceberg's published docs
before writing this, not recalled from memory -- see the PR description for
what's still unverified (no live ClickHouse/Lakekeeper to run this against
in the build sandbox; first real run is the `make ci-kind` job once this
component ships there).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

import clickhouse_connect
import pyarrow as pa
from pyiceberg.catalog import load_catalog

logger = logging.getLogger("fibrik.lake")

GOLD_NAMESPACE = "gold"


@dataclass
class LakeWriterConfig:
    clickhouse_host: str
    clickhouse_port: int
    clickhouse_user: str
    clickhouse_password: str
    clickhouse_database: str
    lakekeeper_uri: str
    lakekeeper_warehouse: str
    tables: list[str] = field(default_factory=lambda: ["ocsf_authentication"])
    batch_seconds: int = 60
    batch_size: int = 10_000


def _clickhouse_client(cfg: LakeWriterConfig):
    return clickhouse_connect.get_client(
        host=cfg.clickhouse_host,
        port=cfg.clickhouse_port,
        username=cfg.clickhouse_user,
        password=cfg.clickhouse_password,
        database=cfg.clickhouse_database,
    )


def _iceberg_catalog(cfg: LakeWriterConfig, retries: int = 6, retry_seconds: float = 5.0):
    """The actual root cause, after three wrong guesses (a project-id
    prefix that wasn't needed; a retry loop that didn't retry the right
    call; a URL-encoding theory never actually isolated): PyIceberg's
    RestCatalog sends `Authorization: Bearer None` on every request,
    including this one, whenever no credential/token is configured --
    `LegacyOAuth2AuthManager.auth_header()` does an unguarded
    `f"Bearer {self._token}"` with `self._token` still `None`
    (pyiceberg/catalog/rest/auth.py). curl, which has no such default,
    never sends an Authorization header at all for the exact same
    request -- confirmed directly with a local HTTP server that echoes
    back the Authorization header it receives: PyIceberg sent
    `'Bearer None'`; curl against the same byte-identical GetConfig
    request sent none. Lakekeeper's own authn middleware evidently
    doesn't fall through to the same anonymous-default-project path for
    an unparseable-but-present bearer token the way it does for no
    token at all, so the warehouse lookup resolves a different (and
    empty) project and 404s.

    Fixed by explicitly selecting PyIceberg's `NoopAuthManager` (`auth:
    {type: noop}`), which returns `None` from `auth_header()` --
    `AuthManagerAdapter.__call__` only sets the header at all when
    `auth_header()` is truthy, so this is the one config that actually
    sends zero Authorization header, matching curl. The retry loop
    (originally added to explain the first, wrong, propagation-race
    theory) stays: harmless, and still real insurance against an
    actual not-ready-yet race on first deploy.
    """
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            return load_catalog(
                "fibrik",
                **{
                    "uri": cfg.lakekeeper_uri,
                    "warehouse": cfg.lakekeeper_warehouse,
                    "auth": {"type": "noop"},
                },
            )
        except Exception as e:  # noqa: BLE001 -- deliberately broad: any
            # failure here means "not ready yet," not a reason to pick
            # apart exception types we can't be sure PyIceberg will keep
            # raising the same way across versions.
            last_error = e
            logger.warning(
                "lake writer: catalog handshake attempt %d/%d failed (%s), retrying in %.0fs",
                attempt, retries, e, retry_seconds,
            )
            if attempt < retries:
                time.sleep(retry_seconds)
    raise RuntimeError(
        f"lake writer: catalog handshake failed after {retries} attempts"
    ) from last_error


def _get_watermark(client, table: str):
    result = client.query(
        "SELECT max(last_time) FROM _lake_writer_state WHERE table_name = {table:String}",
        parameters={"table": table},
    )
    if not result.result_rows:
        return None
    value = result.result_rows[0][0]
    # ClickHouse's max() over zero matching rows returns the type's zero
    # value (1970-01-01), not NULL -- treat that the same as "no watermark
    # yet" rather than a real timestamp.
    if value is None or value.year < 1971:
        return None
    return value


def _set_watermark(client, table: str, new_watermark) -> None:
    client.insert(
        "_lake_writer_state",
        [[table, new_watermark]],
        column_names=["table_name", "last_time"],
    )


def _fetch_batch(client, cfg: LakeWriterConfig, table: str, watermark) -> "pa.Table":
    if watermark is None:
        where, params = "1 = 1", {}
    else:
        # Strict `>`: a batch that's truncated mid-timestamp by batch_size
        # can skip same-timestamp rows past the cut. Acceptable for a
        # walking skeleton; a real watermark needs a monotonic cursor
        # (e.g. an inserted-at sequence column), not just `time`.
        where, params = "time > {watermark:DateTime64(3)}", {"watermark": watermark}
    query = f"SELECT * FROM {table} WHERE {where} ORDER BY time LIMIT {cfg.batch_size}"
    return client.query_arrow(query, parameters=params)


def _ensure_iceberg_table(catalog, namespace: str, table_name: str, schema: "pa.Schema"):
    identifier = f"{namespace}.{table_name}"
    if (namespace,) not in catalog.list_namespaces():
        catalog.create_namespace(namespace)
    if not catalog.table_exists(identifier):
        logger.info("lake writer: creating Iceberg table %s", identifier)
        return catalog.create_table(identifier, schema=schema)
    return catalog.load_table(identifier)


def count_rows(cfg: LakeWriterConfig, table: str) -> int:
    """Current row count of an Iceberg table -- `make e2e`'s verification
    step uses this (via `fibrik lake count`) instead of querying through
    ClickHouse's Iceberg table functions, whose exact syntax for a
    Lakekeeper REST-catalog-backed table isn't verified against the pinned
    ClickHouse version yet. Returns 0 if the table doesn't exist (nothing
    written yet is a valid state, not an error, for this check).
    """
    catalog = _iceberg_catalog(cfg)
    identifier = f"{GOLD_NAMESPACE}.{table}"
    if not catalog.table_exists(identifier):
        return 0
    return catalog.load_table(identifier).scan().to_arrow().num_rows


def run_once(cfg: LakeWriterConfig) -> dict[str, int]:
    """One poll-and-write pass over every configured table.

    Returns the number of rows written per table (0 if nothing was new).
    """
    ch_client = _clickhouse_client(cfg)
    catalog = _iceberg_catalog(cfg)
    written: dict[str, int] = {}
    for table in cfg.tables:
        watermark = _get_watermark(ch_client, table)
        batch = _fetch_batch(ch_client, cfg, table, watermark)
        written[table] = batch.num_rows
        if batch.num_rows == 0:
            continue
        iceberg_table = _ensure_iceberg_table(catalog, GOLD_NAMESPACE, table, batch.schema)
        iceberg_table.append(batch)
        new_watermark = None
        if "time" in batch.column_names:
            new_watermark = batch.column("time")[-1].as_py()
        if new_watermark is not None:
            _set_watermark(ch_client, table, new_watermark)
        logger.info(
            "lake writer: wrote %d row(s) from %s to %s.%s",
            batch.num_rows, table, GOLD_NAMESPACE, table,
        )
    return written


def run_forever(cfg: LakeWriterConfig) -> None:
    """The long-running process Deployment -- one poll/write pass every
    `batch_seconds`, forever. A failed pass is logged and retried on the
    next interval rather than crashing the process, since a transient
    ClickHouse/Lakekeeper hiccup shouldn't need a pod restart to recover.
    """
    while True:
        try:
            run_once(cfg)
        except Exception:
            logger.exception("lake writer: batch failed, retrying next interval")
        time.sleep(cfg.batch_seconds)
