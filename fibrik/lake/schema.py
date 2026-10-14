"""Schema of the raw_logs lake table (mirrors the ClickHouse table)."""

import pyarrow as pa
from pyiceberg.partitioning import PartitionField, PartitionSpec
from pyiceberg.schema import Schema
from pyiceberg.transforms import DayTransform
from pyiceberg.types import NestedField, StringType, TimestamptzType

RAW_LOGS = "raw_logs"

ICEBERG_SCHEMA = Schema(
    NestedField(1, "event_time", TimestamptzType(), required=False),
    NestedField(2, "ingest_time", TimestamptzType(), required=False),
    NestedField(3, "source", StringType(), required=False),
    NestedField(4, "host", StringType(), required=False),
    NestedField(5, "app", StringType(), required=False),
    NestedField(6, "severity", StringType(), required=False),
    NestedField(7, "body", StringType(), required=False),
    NestedField(8, "attributes", StringType(), required=False),
)

PARTITION_SPEC = PartitionSpec(
    PartitionField(source_id=1, field_id=1000, transform=DayTransform(), name="event_day")
)

ARROW_SCHEMA = pa.schema(
    [
        pa.field("event_time", pa.timestamp("us", tz="UTC")),
        pa.field("ingest_time", pa.timestamp("us", tz="UTC")),
        pa.field("source", pa.string()),
        pa.field("host", pa.string()),
        pa.field("app", pa.string()),
        pa.field("severity", pa.string()),
        pa.field("body", pa.string()),
        pa.field("attributes", pa.string()),
    ]
)
