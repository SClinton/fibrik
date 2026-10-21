"""Synthetic sshd syslog event generator for `make seed`/`make e2e`
(execution-plan.md §2.3 task 4: "replays OTRF Security-Datasets and
synthetic sshd/CloudTrail/Windows events at a configurable EPS"). This
walking skeleton only has an OCSF mapping for sshd
(deploy/helm/fibrik/templates/vector.yaml's sshd_ocsf transform), so
synthetic sshd lines are the only events worth generating right now --
OTRF replay and the other synthetic source types are deferred until a
later phase adds packs/mappings for them.

RFC5424 framing, newline-delimited over TCP -- both checked against
Vector's `syslog` source docs before writing this (see vector.yaml's
header comment for the same verification note).
"""

from __future__ import annotations

import socket
import time


def _syslog_line(i: int, hostname: str) -> str:
    ip = f"10.0.{(i // 250) % 256}.{i % 250}"
    if i % 3 == 0:
        body = f"Failed password for invalid user bob from {ip} port 2222"
    else:
        body = f"Accepted password for alice from {ip} port 2222"
    # <34> = facility 4 (auth), severity 2 (critical) -- any valid PRI works,
    # Vector doesn't route on it. "-" fields are MSGID and STRUCTURED-DATA
    # (both nil, valid per RFC5424).
    return f"<34>1 2026-01-01T00:00:00Z {hostname} sshd {i} - - {body}"


def send(host: str, port: int, count: int, sleep_seconds: float = 0.0, hostname: str = "fibrik-seed") -> int:
    """Sends `count` synthetic sshd auth lines over TCP syslog to Vector.

    Returns the number of lines actually sent (== count on success; a
    connection error raises rather than returning a partial count).
    """
    sent = 0
    with socket.create_connection((host, port), timeout=5) as sock:
        for i in range(count):
            line = _syslog_line(i, hostname) + "\n"
            sock.sendall(line.encode("utf-8"))
            sent += 1
            if sleep_seconds:
                time.sleep(sleep_seconds)
    return sent
