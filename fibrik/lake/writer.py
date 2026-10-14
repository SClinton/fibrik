"""Micro-batch lake writer.

Vector lands newline-delimited JSON batches under the pending prefix. Each
run commits every pending file to the raw_logs Iceberg table, then moves it
to the archive prefix. The file key is stored in the snapshot summary, so a
crash between commit and move never commits the same file twice.
"""

import gzip
import io
import logging
import threading

import pyarrow as pa
import pyarrow.json as pajson
from pyiceberg.table import Table

from fibrik.lake.schema import ARROW_SCHEMA
from fibrik.storage import ObjectStore

log = logging.getLogger(__name__)

SUMMARY_KEY = "fibrik.source-file"
_PARSE_SCHEMA = pa.schema(
    [
        pa.field(f.name, pa.timestamp("ns", tz="UTC")) if pa.types.is_timestamp(f.type) else f
        for f in ARROW_SCHEMA
    ]
)
# How many recent snapshots to check for already-committed files.
DEDUP_SNAPSHOTS = 200


def parse_batch(data: bytes) -> pa.Table:
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if not data.strip():
        return ARROW_SCHEMA.empty_table()
    # Vector writes RFC 3339 timestamps with nanoseconds; Iceberg stores
    # microseconds, so parse at ns and truncate.
    opts = pajson.ParseOptions(explicit_schema=_PARSE_SCHEMA, unexpected_field_behavior="ignore")
    table = pajson.read_json(io.BytesIO(data), parse_options=opts).select(ARROW_SCHEMA.names)
    return table.cast(ARROW_SCHEMA, safe=False)


def committed_files(table: Table) -> set[str]:
    done = set()
    for snap in table.metadata.snapshots[-DEDUP_SNAPSHOTS:]:
        key = snap.summary.additional_properties.get(SUMMARY_KEY) if snap.summary else None
        if key:
            done.add(key)
    return done


class LakeWriter:
    def __init__(self, store: ObjectStore, table: Table, pending: str, archive: str):
        self.store, self.table = store, table
        self.pending, self.archive = pending, archive

    def run_once(self) -> int:
        """Commit all pending files. Returns the number of rows written."""
        self.table.refresh()
        done = committed_files(self.table)
        rows = 0
        for obj in self.store.list(self.pending):
            if obj.key not in done:
                batch = parse_batch(self.store.read(obj.key))
                if batch.num_rows:
                    self.table.append(batch, snapshot_properties={SUMMARY_KEY: obj.key})
                    rows += batch.num_rows
            self.store.move(obj.key, self.archive + obj.key.removeprefix(self.pending))
        if rows:
            log.info("lake writer committed %d rows", rows)
        return rows

    def run_forever(self, interval: float, stop: threading.Event) -> None:
        while not stop.is_set():
            try:
                self.run_once()
            except Exception:
                log.exception("lake writer run failed; retrying")
            stop.wait(interval)
