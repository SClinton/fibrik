"""The `fibrik` command line."""

import logging
import time

import typer
import uvicorn

from fibrik import clickhouse
from fibrik.lake.catalog import ensure_table, ensure_warehouse, get_catalog
from fibrik.settings import get_settings
from fibrik.storage import ObjectStore

app = typer.Typer(help="Fibrik command line", no_args_is_help=True)
log = logging.getLogger("fibrik")


def _retry(what: str, fn, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while True:
        try:
            fn()
            log.info("%s: ok", what)
            return
        except Exception as e:
            if time.monotonic() > deadline:
                raise
            log.warning("%s: not ready yet (%s); retrying", what, e)
            time.sleep(3)


@app.callback()
def main(verbose: bool = typer.Option(False, "--verbose", "-v")) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


@app.command()
def migrate(timeout: float = typer.Option(300, help="Seconds to wait for dependencies")) -> None:
    """Create the bucket, ClickHouse tables, Iceberg warehouse and tables. Idempotent."""
    s = get_settings()
    _retry("object storage bucket", ObjectStore(s.storage).ensure_bucket, timeout)
    _retry("clickhouse schema", lambda: clickhouse.migrate(s), timeout)
    _retry("iceberg warehouse", lambda: ensure_warehouse(s), timeout)
    _retry("iceberg tables", lambda: ensure_table(get_catalog(s), s), timeout)


@app.command()
def serve(host: str = "0.0.0.0", port: int = 8000) -> None:
    """Run the API server (and the in-process lake writer)."""
    uvicorn.run("fibrik.api.app:create_app", factory=True, host=host, port=port)


if __name__ == "__main__":
    app()
