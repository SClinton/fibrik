"""fibrik-api: the control-plane API, plus the in-process lake writer.

Two listeners: the public API (port 8000, behind Caddy at /api, bearer
tokens required) and an internal one (port 8001, cluster-only) for probes
and operational checks. The lean profile runs API, MCP servers and
background jobs as one process group (zero-cost-mvp.md §3).
"""

import asyncio
import logging
import threading
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Response

from fibrik import __version__, clickhouse
from fibrik.api.auth import TokenVerifier, User
from fibrik.lake.catalog import get_catalog
from fibrik.lake.schema import RAW_LOGS
from fibrik.lake.writer import LakeWriter
from fibrik.settings import Settings, get_settings
from fibrik.storage import ObjectStore

log = logging.getLogger(__name__)


def lake_row_count(s: Settings) -> int:
    table = get_catalog(s).load_table((s.lake_namespace, RAW_LOGS))
    snap = table.current_snapshot()
    if snap is None or snap.summary is None:
        return 0
    return int(snap.summary.additional_properties.get("total-records", 0))


def pipeline_stats(s: Settings) -> dict:
    """Rows in the hot store and the lake: the week-1 end-to-end check."""
    return {
        "clickhouse": {"raw_logs": clickhouse.raw_log_count(s)},
        "lake": {"raw_logs": lake_row_count(s)},
    }


def create_app(settings: Settings | None = None) -> FastAPI:
    """The public API."""
    s = settings or get_settings()
    app = FastAPI(title="Fibrik API", version=__version__, root_path="/api")
    app.state.verifier = TokenVerifier(s) if s.auth_enabled else None

    @app.get("/healthz")
    def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/v1/info")
    def info() -> dict:
        return {"name": "fibrik", "version": __version__}

    @app.get("/v1/me")
    def me(user: User) -> dict:
        keys = ("sub", "email", "name", "preferred_username")
        return {k: user[k] for k in keys if k in user}

    @app.get("/v1/pipeline/stats")
    def stats(user: User) -> dict:
        return pipeline_stats(s)

    return app


def create_internal_app(settings: Settings | None = None) -> FastAPI:
    """Cluster-only endpoints: probes, stats for e2e tests, and the lake writer."""
    s = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        stop = threading.Event()
        if s.lake_writer_enabled:
            table = get_catalog(s).load_table((s.lake_namespace, RAW_LOGS))
            st = s.storage
            writer = LakeWriter(ObjectStore(st), table, st.pending_prefix, st.archive_prefix)
            threading.Thread(
                target=writer.run_forever,
                args=(s.lake_writer_interval_seconds, stop),
                name="lake-writer",
                daemon=True,
            ).start()
        yield
        stop.set()

    app = FastAPI(title="Fibrik internal", version=__version__, lifespan=lifespan)

    @app.get("/healthz")
    def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz(response: Response) -> dict:
        try:
            clickhouse.connect(s).ping()
        except Exception as e:  # report, don't crash the probe
            response.status_code = 503
            return {"status": "unavailable", "clickhouse": str(e)}
        return {"status": "ready"}

    @app.get("/v1/pipeline/stats")
    def stats() -> dict:
        return pipeline_stats(s)

    return app


def serve(host: str, port: int, internal_port: int) -> None:
    s = get_settings()
    servers = [
        uvicorn.Server(uvicorn.Config(create_app(s), host=host, port=port)),
        uvicorn.Server(uvicorn.Config(create_internal_app(s), host=host, port=internal_port)),
    ]

    async def main() -> None:
        await asyncio.gather(*(srv.serve() for srv in servers))

    asyncio.run(main())
