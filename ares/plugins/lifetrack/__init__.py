"""ARES LifeTrack — Orchestrator.

Runs the full tracking pipeline: ingest, classify, reconcile, report.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from .models import (
    DailyPlan, DailyReality, DailyReconciliation, ActivityBlock,
    ActivityCategory, WeeklyReport
)
from . import driver, classify, db


def ingest_day(date: Optional[datetime] = None) -> tuple[list, list]:
    """
    Ingest raw data for a specific day.
    
    Returns: (app_usage_events, calendar_events)
    """
    if date is None:
        date = datetime.now()
    
    start = date.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    
    # Fetch raw data
    app_usage = driver.get_screen_time_data(start, end)
    calendar_events = driver.get_calendar_events(start, end)
    # location_data = driver.get_significant_locations(start, end)  # Requires permissions
    
    return app_usage, calendar_events


def process_day(date: Optional[datetime] = None, custom_rules: Optional[dict] = None) -> DailyReconciliation:
    """
    Process a full day: ingest, classify, reconcile.
    
    Returns a DailyReconciliation with metrics.
    """
    if date is None:
        date = datetime.now()
    
    # Load user overrides
    overrides = db.load_app_overrides()
    if custom_rules:
        overrides.update(custom_rules)
    
    # Ingest
    app_usage, calendar_events = ingest_day(date)
    
    # Classify and merge
    blocks = classify.merge_events_with_usage(calendar_events, app_usage, overrides)
    
    # Build plan and reality
    plan = DailyPlan(
        date=date,
        events=calendar_events
    )
    
    reality = DailyReality(
        date=date,
        blocks=blocks
    )
    
    # Calculate metrics
    focus_score = classify.calculate_focus_score(calendar_events, blocks)
    
    distraction_minutes = sum(
        b.duration_minutes for b in blocks 
        if b.category == ActivityCategory.DISTRACTION
    )
    
    unplanned_work_minutes = sum(
        b.duration_minutes for b in blocks 
        if b.category in [ActivityCategory.WORK, ActivityCategory.RESEARCH]
        and b.source == "app"
    )
    
    # Identify missed vs completed events
    missed_events = []
    completed_events = []
    
    for event in calendar_events:
        # Check if there's a matching reality block
        matched = False
        for block in blocks:
            if block.start <= event.start and block.end >= event.end:
                if block.category in [ActivityCategory.WORK, ActivityCategory.MEETING]:
                    completed_events.append(event)
                else:
                    missed_events.append(event)
                matched = True
                break
        
        if not matched:
            missed_events.append(event)
    
    # Build reconciliation
    reconciliation = DailyReconciliation(
        date=date,
        plan=plan,
        reality=reality,
        focus_score=focus_score,
        distraction_minutes=distraction_minutes,
        unplanned_work_minutes=unplanned_work_minutes,
        missed_events=missed_events,
        completed_events=completed_events
    )
    
    # Save to DB
    db.save_activity_blocks(blocks, date)
    db.save_daily_reconciliation(reconciliation)
    
    return reconciliation


def get_today_summary() -> str:
    """Get a quick summary of today's tracking."""
    today = datetime.now()
    
    # Try to load existing reconciliation
    reconciliation = db.load_daily_reconciliation(today)
    
    if reconciliation:
        return reconciliation.summary
    
    # If not processed yet, return placeholder
    return f"📅 {today.strftime('%Y-%m-%d')} | Not yet processed\n   Run: ares lifetrack process --today"


def get_weekly_summary(weeks_back: int = 0) -> str:
    """Get weekly report summary."""
    today = datetime.now()
    
    # Calculate week boundaries (Monday-Sunday)
    days_since_monday = today.weekday()
    start_of_week = today - timedelta(days=days_since_monday)
    
    # Adjust for weeks_back
    start_of_week = start_of_week - timedelta(weeks=weeks_back)
    end_of_week = start_of_week + timedelta(days=6)
    
    report = db.load_weekly_report(start_of_week, end_of_week)
    
    if report:
        return report.summary
    
    return f"📊 Week {start_of_week.strftime('%m/%d')} - {end_of_week.strftime('%m/%d')}\n   No data yet"


def run_pipeline(dry_run: bool = False) -> str:
    """
    Run the full LifeTrack pipeline.
    
    Processes yesterday (most common use case) or today if --today flag.
    """
    # Default: process yesterday
    target_date = datetime.now() - timedelta(days=1)
    
    lines = []
    lines.append(f"⏱  Processing {target_date.strftime('%Y-%m-%d')}...")
    
    try:
        reconciliation = process_day(target_date)
        
        if dry_run:
            lines.append("🔍  DRY RUN — not saving to database")
        else:
            lines.append("✅  Saved to database")
        
        lines.append("")
        lines.append(reconciliation.summary)
        
        if reconciliation.missed_events:
            lines.append("")
            lines.append(f"⚠️   Missed events ({len(reconciliation.missed_events)}):")
            for event in reconciliation.missed_events[:5]:
                lines.append(f"   • {event.title} ({event.start.strftime('%H:%M')})")
            if len(reconciliation.missed_events) > 5:
                lines.append(f"   ... and {len(reconciliation.missed_events) - 5} more")
        
        return "\n".join(lines)
        
    except Exception as e:
        return f"❌  Error processing day: {str(e)}"
