import gzip
import json

from fibrik.lake.writer import parse_batch


def _line(**over):
    row = {
        "event_time": "2026-10-14T21:00:00.123Z",
        "ingest_time": "2026-10-14T22:01:03.944305542Z",
        "source": "syslog",
        "host": "web01",
        "app": "sshd",
        "severity": "crit",
        "body": "Failed password",
        "attributes": "{}",
        "unexpected": "ignored",
    }
    row.update(over)
    return json.dumps(row)


def test_parse_gzipped_ndjson_with_nanoseconds():
    data = gzip.compress((_line() + "\n" + _line(host="web02") + "\n").encode())
    table = parse_batch(data)
    assert table.num_rows == 2
    assert table.column_names[-1] == "attributes"
    rows = table.to_pylist()
    assert rows[1]["host"] == "web02"
    assert rows[0]["ingest_time"].microsecond == 944305


def test_parse_empty_batch():
    assert parse_batch(b"").num_rows == 0
