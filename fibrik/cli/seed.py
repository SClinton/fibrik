"""`fibrik seed` -- send synthetic test events into Vector (`make seed`)."""

from __future__ import annotations

import logging

import typer

from fibrik.lake.seed import send

app = typer.Typer(help="Send synthetic test events.")

logger = logging.getLogger("fibrik.seed")


@app.callback(invoke_without_command=True)
def seed(
    vector_host: str = typer.Option("fibrik-vector", envvar="VECTOR_HOST"),
    vector_port: int = typer.Option(5514, envvar="VECTOR_SYSLOG_PORT"),
    events: int = typer.Option(20, help="Number of synthetic sshd events to send."),
    sleep_seconds: float = typer.Option(0.0, help="Delay between events, for a target EPS."),
) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    sent = send(vector_host, vector_port, events, sleep_seconds=sleep_seconds)
    typer.echo(f"sent {sent} synthetic sshd event(s) to {vector_host}:{vector_port}")
