"""CLI command: ares lifetrack"""

from __future__ import annotations

import click
from datetime import datetime, timedelta

from ares.plugins.lifetrack import run_pipeline, get_today_summary, get_weekly_summary
from ares.plugins.lifetrack.db import get_stats, load_daily_reconciliation, load_app_overrides, init_db
from ares.plugins.lifetrack.models import ActivityCategory


@click.group(name="lifetrack")
def lifetrack_cli():
    """ARES LifeTrack — automatic time tracking and productivity analysis."""
    pass


@lifetrack_cli.command(name="process")
@click.option("--today", "-t", is_flag=True, help="Process today instead of yesterday")
@click.option("--date", "-d", type=str, help="Process specific date (YYYY-MM-DD)")
@click.option("--dry-run", "-n", is_flag=True, help="Preview only — do not save to database")
def cmd_process(today, date, dry_run):
    """Process a day's tracking data."""
    init_db()  # Auto-init
    
    if date:
        target = datetime.strptime(date, "%Y-%m-%d")
    elif today:
        target = datetime.now()
    else:
        target = datetime.now() - timedelta(days=1)
    
    from ares.plugins.lifetrack import process_day
    
    try:
        reconciliation = process_day(target)
        
        if dry_run:
            click.echo("🔍 DRY RUN — not saving\n")
        else:
            click.echo("✅ Processed and saved\n")
        
        click.echo(reconciliation.summary)
        
    except Exception as e:
        click.echo(f"❌ Error: {str(e)}", err=True)


@lifetrack_cli.command(name="today")
def cmd_today():
    """Show today's tracking summary."""
    init_db()  # Auto-init
    click.echo(get_today_summary())


@lifetrack_cli.command(name="week")
@click.option("--weeks-back", "-w", type=int, default=0, help="Weeks to look back (0 = current week)")
def cmd_week(weeks_back):
    """Show weekly summary."""
    click.echo(get_weekly_summary(weeks_back))


@lifetrack_cli.command(name="stats")
def cmd_stats():
    """Show LifeTrack statistics."""
    stats = get_stats()
    click.echo(f"Days tracked:        {stats['days_tracked']}")
    click.echo(f"Reconciliations:     {stats['reconciliations_count']}")
    click.echo(f"Avg focus score:     {stats['avg_focus_score']:.1%}")
    click.echo(f"App overrides:       {stats['app_overrides']}")


@lifetrack_cli.command(name="override")
@click.argument("bundle_id")
@click.argument("category", type=click.Choice([c.value for c in ActivityCategory]))
@click.option("--app-name", "-n", type=str, help="Optional app name for display")
def cmd_override(bundle_id, category, app_name):
    """Set a custom category for an app.
    
    Example: ares lifetrack override com.apple.Safari research
    """
    from ares.plugins.lifetrack.db import save_app_override
    
    save_app_override(bundle_id, app_name or bundle_id, ActivityCategory(category))
    click.echo(f"✅ Set {bundle_id} → {category}")


@lifetrack_cli.command(name="overrides")
def cmd_overrides():
    """List all custom app category overrides."""
    overrides = load_app_overrides()
    
    if not overrides:
        click.echo("No custom overrides set.")
        return
    
    click.echo("Custom app categories:")
    for bundle_id, category in sorted(overrides.items()):
        click.echo(f"  {bundle_id:<40} → {category.value}")


@lifetrack_cli.command(name="report")
@click.option("--date", "-d", type=str, help="Date to report (YYYY-MM-DD, default: yesterday)")
@click.option("--json", "as_json", is_flag=True, help="Output as JSON")
def cmd_report(date, as_json):
    """Show detailed daily report."""
    if date:
        target = datetime.strptime(date, "%Y-%m-%d")
    else:
        target = datetime.now() - timedelta(days=1)
    
    reconciliation = load_daily_reconciliation(target)
    
    if not reconciliation:
        click.echo(f"No data for {target.strftime('%Y-%m-%d')}. Run 'ares lifetrack process' first.")
        return
    
    if as_json:
        import json
        click.echo(reconciliation.model_dump_json(indent=2))
    else:
        click.echo(reconciliation.summary)
        
        if reconciliation.completed_events:
            click.echo(f"\n✅ Completed events ({len(reconciliation.completed_events)}):")
            for event in reconciliation.completed_events[:10]:
                click.echo(f"   {event.start.strftime('%H:%M')}  {event.title}")
        
        if reconciliation.missed_events:
            click.echo(f"\n⚠️  Missed events ({len(reconciliation.missed_events)}):")
            for event in reconciliation.missed_events[:10]:
                click.echo(f"   {event.start.strftime('%H:%M')}  {event.title}")
