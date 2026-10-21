"""The `fibrik` CLI entry point (pyproject.toml's [project.scripts])."""

import typer

from fibrik.cli import e2e, lake, seed

app = typer.Typer(help="Fibrik: the Open Security Data Fabric for Agentic AI.")
app.add_typer(lake.app, name="lake")
app.add_typer(seed.app, name="seed")
app.add_typer(e2e.app, name="e2e")


if __name__ == "__main__":
    app()
