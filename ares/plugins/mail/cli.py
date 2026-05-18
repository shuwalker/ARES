"""CLI command: ares mail triage"""

from __future__ import annotations

import click

from ares.plugins.mail import triage
from ares.plugins.mail.db import get_stats


@click.group(name="mail")
def mail_cli():
    """ARES mail triage plugin."""
    pass


@mail_cli.command(name="triage")
@click.option("--dry-run", "-n", is_flag=True, help="Preview only — do not move messages")
@click.option("--json", "as_json", is_flag=True, help="Output as JSON instead of pretty text")
def cmd_triage(dry_run, as_json):
    """Run mail triage on all configured accounts."""
    result = triage(dry_run=dry_run)
    if as_json:
        import json
        click.echo(result.model_dump_json(indent=2))
    else:
        click.echo(result.summary)


@mail_cli.command(name="stats")
def cmd_stats():
    """Show learned mail triage stats."""
    stats = get_stats()
    click.echo(f"Junk senders tracked: {stats['junk_senders']}")
    click.echo(f"Keep  senders tracked: {stats['keep_senders']}")
    click.echo(f"Junk domains tracked:  {stats['junk_domains']}")
