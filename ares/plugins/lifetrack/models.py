"""ARES LifeTrack — Pydantic models.

Structured types for activity blocks, daily reports, and reconciliation.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal
from enum import Enum

from pydantic import BaseModel, Field


class ActivityCategory(str, Enum):
    """High-level activity categories."""
    WORK = "work"
    COMMS = "comms"
    RESEARCH = "research"
    DISTRACTION = "distraction"
    HEALTH = "health"
    MEETING = "meeting"
    UNKNOWN = "unknown"


class AppUsage(BaseModel):
    """Raw app usage event from Screen Time."""
    
    bundle_id: str = Field(description="App bundle ID (e.g. 'com.apple.Safari')")
    app_name: str = Field(description="Human-readable app name")
    start: datetime
    end: datetime
    duration_seconds: int = Field(ge=0)
    
    @property
    def duration_minutes(self) -> float:
        return self.duration_seconds / 60.0


class CalendarEvent(BaseModel):
    """Calendar event from Apple Calendar."""
    
    title: str
    start: datetime
    end: datetime
    location: str | None = None
    calendar_name: str = "Calendar"
    is_all_day: bool = False
    
    @property
    def duration_minutes(self) -> float:
        delta = self.end - self.start
        return delta.total_seconds() / 60.0


class ActivityBlock(BaseModel):
    """A classified time block — merged app usage + context."""
    
    start: datetime
    end: datetime
    primary_app: str | None = None
    category: ActivityCategory = ActivityCategory.UNKNOWN
    confidence: float = Field(ge=0.0, le=1.0, default=0.5)
    source: Literal["app", "calendar", "location", "inferred"] = "app"
    notes: str = ""
    
    @property
    def duration_minutes(self) -> float:
        delta = self.end - self.start
        return delta.total_seconds() / 60.0


class LocationSample(BaseModel):
    """Location data point from Significant Locations."""
    
    timestamp: datetime
    latitude: float
    longitude: float
    location_name: str | None = None  # e.g. "Home", "Work"
    confidence: float = Field(ge=0.0, le=1.0, default=0.5)


class DailyPlan(BaseModel):
    """Planned activities from calendar."""
    
    date: datetime
    events: list[CalendarEvent] = Field(default_factory=list)
    total_planned_minutes: float = 0.0
    
    def __init__(self, **data):
        super().__init__(**data)
        if not self.total_planned_minutes and self.events:
            self.total_planned_minutes = sum(e.duration_minutes for e in self.events)


class DailyReality(BaseModel):
    """Actual activities from tracking data."""
    
    date: datetime
    blocks: list[ActivityBlock] = Field(default_factory=list)
    total_tracked_minutes: float = 0.0
    
    def __init__(self, **data):
        super().__init__(**data)
        if not self.total_tracked_minutes and self.blocks:
            self.total_tracked_minutes = sum(b.duration_minutes for b in self.blocks)


class DailyReconciliation(BaseModel):
    """Comparison: planned vs. actual for a single day."""
    
    date: datetime
    plan: DailyPlan
    reality: DailyReality
    
    # Metrics
    focus_score: float = Field(ge=0.0, le=1.0, description="% of planned time on-task")
    distraction_minutes: float = 0.0
    unplanned_work_minutes: float = 0.0
    missed_events: list[CalendarEvent] = Field(default_factory=list)
    completed_events: list[CalendarEvent] = Field(default_factory=list)
    
    @property
    def summary(self) -> str:
        focus_pct = int(self.focus_score * 100)
        return (
            f"📅 {self.date.strftime('%Y-%m-%d')} | Focus: {focus_pct}%\n"
            f"   Planned: {self.plan.total_planned_minutes:.0f}m | "
            f"Actual: {self.reality.total_tracked_minutes:.0f}m\n"
            f"   Distractions: {self.distraction_minutes:.0f}m | "
            f"Missed: {len(self.missed_events)} events"
        )


class WeeklyReport(BaseModel):
    """Aggregated report for a week."""
    
    start_date: datetime
    end_date: datetime
    daily_reconciliations: list[DailyReconciliation] = Field(default_factory=list)
    
    @property
    def avg_focus_score(self) -> float:
        if not self.daily_reconciliations:
            return 0.0
        return sum(r.focus_score for r in self.daily_reconciliations) / len(self.daily_reconciliations)
    
    @property
    def total_work_minutes(self) -> float:
        total = 0.0
        for r in self.daily_reconciliations:
            for block in r.reality.blocks:
                if block.category in [ActivityCategory.WORK, ActivityCategory.RESEARCH]:
                    total += block.duration_minutes
        return total
    
    @property
    def summary(self) -> str:
        avg_focus = int(self.avg_focus_score * 100)
        work_hours = self.total_work_minutes / 60.0
        return (
            f"📊 Week {self.start_date.strftime('%m/%d')} - {self.end_date.strftime('%m/%d')}\n"
            f"   Avg Focus: {avg_focus}% | Total Work: {work_hours:.1f}h\n"
            f"   Days tracked: {len(self.daily_reconciliations)}"
        )
