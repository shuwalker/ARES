"""ARES LifeTrack — Classification engine.

Maps raw app usage to activity categories using:
- Bundle ID patterns
- User-defined rules
- Time-of-day context
- Location context
"""

from __future__ import annotations

from typing import Optional
from datetime import datetime

from .models import AppUsage, CalendarEvent, ActivityBlock, ActivityCategory


# === Default App Category Mappings ===

DEFAULT_APP_CATEGORIES = {
    # Development
    "com.apple.Xcode": ActivityCategory.WORK,
    "com.microsoft.VSCode": ActivityCategory.WORK,
    "com.jetbrains.intellij": ActivityCategory.WORK,
    "com.sublimetext.4": ActivityCategory.WORK,
    "com.neovim.neovim": ActivityCategory.WORK,
    "com.apple.Terminal": ActivityCategory.WORK,
    "com.googlecode.iterm2": ActivityCategory.WORK,
    "com.github.Electron": ActivityCategory.WORK,  # Many dev apps
    
    # Communication
    "com.apple.MobileSMS": ActivityCategory.COMMS,
    "com.apple.iChat": ActivityCategory.COMMS,
    "com.hnc.Discord": ActivityCategory.COMMS,
    "com.slack.Slack": ActivityCategory.COMMS,
    "com.microsoft.teams": ActivityCategory.COMMS,
    "us.zoom.xos": ActivityCategory.COMMS,
    "com.google.Chrome": ActivityCategory.RESEARCH,  # Could be work or distraction
    
    # Productivity
    "com.apple.iWork.Pages": ActivityCategory.WORK,
    "com.apple.iWork.Numbers": ActivityCategory.WORK,
    "com.apple.iWork.Keynote": ActivityCategory.WORK,
    "com.microsoft.Word": ActivityCategory.WORK,
    "com.microsoft.Excel": ActivityCategory.WORK,
    "com.microsoft.Powerpoint": ActivityCategory.WORK,
    "com.apple.Notes": ActivityCategory.WORK,
    "com.omnigroup.OmniFocus3": ActivityCategory.WORK,
    "com.culturedcode.ThingsMac": ActivityCategory.WORK,
    
    # Research / Learning
    "com.apple.Safari": ActivityCategory.RESEARCH,
    "org.mozilla.firefox": ActivityCategory.RESEARCH,
    "com.brave.Browser": ActivityCategory.RESEARCH,
    "com.apple.iBooks": ActivityCategory.RESEARCH,
    "com.apple.iBooksX": ActivityCategory.RESEARCH,
    
    # Distractions
    "com.apple.TV": ActivityCategory.DISTRACTION,
    "com.apple.Music": ActivityCategory.DISTRACTION,
    "com.spotify.client": ActivityCategory.DISTRACTION,
    "com.netflix.Netflix": ActivityCategory.DISTRACTION,
    "com.hulu.desktop": ActivityCategory.DISTRACTION,
    "com.twitter.twitter-mac": ActivityCategory.DISTRACTION,
    "com.reddit.reddit": ActivityCategory.DISTRACTION,
    "com.youtube.youtube": ActivityCategory.DISTRACTION,
    
    # Health
    "com.apple.Health": ActivityCategory.HEALTH,
    "com.apple.Fitness": ActivityCategory.HEALTH,
    "com.nike.nikeplus-gps": ActivityCategory.HEALTH,
    "com.strava.stravamac": ActivityCategory.HEALTH,
}

# Bundle ID patterns (regex)
BUNDLE_PATTERNS = [
    (r"com\.apple\.Xcode", ActivityCategory.WORK),
    (r"com\.microsoft\.(Word|Excel|Powerpoint|Teams)", ActivityCategory.WORK),
    (r"com\.jetbrains\.", ActivityCategory.WORK),
    (r"com\.google\.Chrome", ActivityCategory.RESEARCH),
    (r"com\.apple\.(Safari|Mail|Notes)", ActivityCategory.WORK),
    (r"com\.hnc\.Discord", ActivityCategory.COMMS),
    (r"com\.apple\.(TV|Music|Podcasts)", ActivityCategory.DISTRACTION),
]


def classify_app(usage: AppUsage, custom_rules: Optional[dict] = None) -> ActivityCategory:
    """
    Classify an app usage event into a category.
    
    Priority:
    1. Custom user rules
    2. Exact bundle ID match
    3. Pattern match
    4. Default to UNKNOWN
    """
    rules = {**DEFAULT_APP_CATEGORIES, **(custom_rules or {})}
    
    # Check exact match first
    if usage.bundle_id in rules:
        return rules[usage.bundle_id]
    
    # Check patterns
    import re
    for pattern, category in BUNDLE_PATTERNS:
        if re.search(pattern, usage.bundle_id):
            return category
    
    return ActivityCategory.UNKNOWN


def infer_category_from_calendar(event: CalendarEvent) -> ActivityCategory:
    """Infer activity category from calendar event."""
    title_lower = event.title.lower()
    
    # Meeting keywords
    meeting_keywords = ["meeting", "call", "standup", "sync", "interview", "review"]
    if any(kw in title_lower for kw in meeting_keywords):
        return ActivityCategory.MEETING
    
    # Work keywords
    work_keywords = ["work", "code", "build", "deploy", "write", "design", "plan"]
    if any(kw in title_lower for kw in work_keywords):
        return ActivityCategory.WORK
    
    # Health keywords
    health_keywords = ["gym", "workout", "run", "exercise", "yoga", "doctor", "dentist"]
    if any(kw in title_lower for kw in health_keywords):
        return ActivityCategory.HEALTH
    
    # Default
    return ActivityCategory.WORK


def merge_events_with_usage(
    events: list[CalendarEvent],
    usage: list[AppUsage],
    custom_rules: Optional[dict] = None
) -> list[ActivityBlock]:
    """
    Merge calendar events with app usage to create activity blocks.
    
    Algorithm:
    1. Create blocks from app usage (primary source)
    2. Overlay calendar events (higher confidence for categorization)
    3. Fill gaps with inferred blocks
    """
    blocks = []
    
    # Step 1: Convert app usage to blocks
    for app in usage:
        category = classify_app(app, custom_rules)
        blocks.append(ActivityBlock(
            start=app.start,
            end=app.end,
            primary_app=app.app_name,
            category=category,
            confidence=0.7 if category != ActivityCategory.UNKNOWN else 0.3,
            source="app"
        ))
    
    # Step 2: Add calendar events as blocks (may overlap)
    for event in events:
        category = infer_category_from_calendar(event)
        blocks.append(ActivityBlock(
            start=event.start,
            end=event.end,
            primary_app=None,
            category=category,
            confidence=0.9,  # Calendar is explicit intent
            source="calendar",
            notes=event.title
        ))
    
    # Step 3: Sort by start time
    blocks.sort(key=lambda b: b.start)
    
    # Step 4: Merge overlapping blocks (prefer higher confidence)
    merged = []
    for block in blocks:
        if not merged:
            merged.append(block)
            continue
        
        last = merged[-1]
        if block.start < last.end:  # Overlap
            # Keep the one with higher confidence
            if block.confidence > last.confidence:
                merged[-1] = block
        else:
            merged.append(block)
    
    return merged


def calculate_focus_score(
    plan: list[CalendarEvent],
    reality: list[ActivityBlock],
    work_categories: list[ActivityCategory] | None = None
) -> float:
    """
    Calculate focus score: % of planned time actually spent on-task.
    
    Focus = (time on planned activity) / (total planned time)
    """
    if work_categories is None:
        work_categories = [ActivityCategory.WORK, ActivityCategory.RESEARCH, ActivityCategory.MEETING]
    
    if not plan:
        return 0.0
    
    total_planned_minutes = sum(e.duration_minutes for e in plan)
    if total_planned_minutes == 0:
        return 0.0
    
    # Calculate overlap between plan and reality
    on_task_minutes = 0.0
    
    for event in plan:
        # Find reality blocks that overlap with this event
        for block in reality:
            if block.category not in work_categories:
                continue
            
            # Calculate overlap
            overlap_start = max(event.start, block.start)
            overlap_end = min(event.end, block.end)
            
            if overlap_start < overlap_end:
                overlap_minutes = (overlap_end - overlap_start).total_seconds() / 60.0
                on_task_minutes += overlap_minutes
    
    return min(1.0, on_task_minutes / total_planned_minutes)
