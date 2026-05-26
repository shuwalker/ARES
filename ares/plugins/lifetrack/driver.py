"""ARES LifeTrack — Data ingestion driver.

Fetches raw data from macOS system sources:
- Screen Time (app usage)
- Apple Calendar (events)
- Significant Locations (via AppleScript)
"""

from __future__ import annotations

import subprocess
import plistlib
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from .models import AppUsage, CalendarEvent, LocationSample


# === Screen Time Data ===
# macOS stores Screen Time data in ScreenTime archive
# Location: ~/Library/Application Support/com.apple.ScreenTime/

def get_screen_time_data(start: datetime, end: datetime) -> list[AppUsage]:
    """
    Fetch app usage data from Screen Time for a time range.
    
    Uses `screenutil` CLI or direct database query.
    Returns list of AppUsage events.
    """
    # Try screenutil first (if installed)
    try:
        result = subprocess.run(
            ["screenutil", "export", "--start", start.isoformat(), "--end", end.isoformat()],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return _parse_screenutil_output(result.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    # Fallback: query ScreenTime SQLite DB directly
    return _query_screentime_db(start, end)


def _parse_screenutil_output(output: str) -> list[AppUsage]:
    """Parse screenutil JSON/CSV output."""
    import json
    try:
        data = json.loads(output)
        events = []
        for item in data.get("events", []):
            events.append(AppUsage(
                bundle_id=item.get("bundle_id", ""),
                app_name=item.get("app_name", ""),
                start=datetime.fromisoformat(item["start"]),
                end=datetime.fromisoformat(item["end"]),
                duration_seconds=item.get("duration_seconds", 0)
            ))
        return events
    except (json.JSONDecodeError, KeyError):
        return []


def _query_screentime_db(start: datetime, end: datetime) -> list[AppUsage]:
    """
    Query ScreenTime SQLite database directly.
    
    DB location: ~/Library/Application Support/com.apple.ScreenTime/ScreenTimeArchive.sqlite
    """
    import sqlite3
    
    db_path = Path.home() / "Library" / "Application Support" / "com.apple.ScreenTime" / "ScreenTimeArchive.sqlite"
    
    if not db_path.exists():
        return []
    
    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        
        # ScreenTime schema varies by macOS version
        # This query works for macOS 13+ (Ventura and later)
        query = """
            SELECT bundle_id, app_name, start_time, end_time, duration
            FROM app_usage
            WHERE start_time >= ? AND end_time <= ?
            ORDER BY start_time
        """
        
        cursor.execute(query, (start.timestamp(), end.timestamp()))
        rows = cursor.fetchall()
        conn.close()
        
        events = []
        for row in rows:
            bundle_id, app_name, start_ts, end_ts, duration = row
            events.append(AppUsage(
                bundle_id=bundle_id or "",
                app_name=app_name or "Unknown",
                start=datetime.fromtimestamp(start_ts),
                end=datetime.fromtimestamp(end_ts),
                duration_seconds=int(duration) if duration else 0
            ))
        return events
        
    except (sqlite3.Error, KeyError):
        return []


# === Calendar Data ===

def get_calendar_events(start: datetime, end: datetime) -> list[CalendarEvent]:
    """
    Fetch calendar events from Apple Calendar for a time range.
    
    Uses osascript to query Calendar.app
    """
    applescript = f'''
    tell application "System Events"
        set calendarRunning to (name of processes) contains "Calendar"
    end tell
    
    if not calendarRunning then
        tell application "Calendar" to activate
        delay 1
    end if
    
    tell application "Calendar"
        set output to ""
        set theDate to date "{start.strftime('%Y-%m-%d %H:%M:%S')}"
        set endDate to date "{end.strftime('%Y-%m-%d %H:%M:%S')}"
        
        repeat with aCalendar in calendars
            repeat with anEvent in (every event of aCalendar where start date ≥ theDate and start date ≤ endDate)
                set eventTitle to summary of anEvent
                set eventStart to start date of anEvent
                set eventEnd to end date of anEvent
                set eventLocation to location of anEvent
                set calendarName to name of aCalendar
                set allDay to allday event of anEvent
                
                set output to output & eventTitle & "||" & (eventStart as string) & "||" & (eventEnd as string) & "||" & (eventLocation as text) & "||" & calendarName & "||" & (allDay as string) & "
"
            end repeat
        end repeat
        
        return output
    end tell
    '''
    
    try:
        result = subprocess.run(
            ["osascript", "-e", applescript],
            capture_output=True,
            text=True,
            timeout=15
        )
        
        if result.returncode == 0:
            return _parse_calendar_output(result.stdout)
    except subprocess.TimeoutExpired:
        pass
    
    return []


def _parse_calendar_output(output: str) -> list[CalendarEvent]:
    """Parse Calendar.app AppleScript output."""
    events = []
    lines = output.strip().split("\n")
    
    for line in lines:
        if not line.strip():
            continue
        
        parts = line.split("||")
        if len(parts) >= 6:
            title = parts[0].strip()
            start_str = parts[1].strip()
            end_str = parts[2].strip()
            location = parts[3].strip() if parts[3].strip() != "missing value" else None
            calendar_name = parts[4].strip()
            is_all_day = parts[5].strip().lower() == "true"
            
            try:
                # macOS date format parsing
                start = _parse_macos_date(start_str)
                end = _parse_macos_date(end_str)
                
                events.append(CalendarEvent(
                    title=title,
                    start=start,
                    end=end,
                    location=location,
                    calendar_name=calendar_name,
                    is_all_day=is_all_day
                ))
            except (ValueError, TypeError):
                continue
    
    return events


def _parse_macos_date(date_str: str) -> datetime:
    """Parse macOS AppleScript date string."""
    # Format: "Monday, January 1, 2024 at 2:00:00 PM"
    import re
    
    # Try standard format first
    patterns = [
        "%A, %B %d, %Y at %I:%M:%S %p",
        "%A, %B %d, %Y at %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
    ]
    
    for pattern in patterns:
        try:
            return datetime.strptime(date_str, pattern)
        except ValueError:
            continue
    
    # Fallback: use dateutil if available
    try:
        from dateutil import parser
        return parser.parse(date_str)
    except ImportError:
        pass
    
    raise ValueError(f"Could not parse date: {date_str}")


# === Location Data ===

def get_significant_locations(start: datetime, end: datetime) -> list[LocationSample]:
    """
    Fetch Significant Locations from Apple Maps.
    
    Requires user permission and may be limited by macOS privacy settings.
    Uses AppleScript to query Maps.app or reads from location database.
    """
    # This is restricted in macOS 13+
    # Attempt AppleScript query first
    applescript = f'''
    tell application "Finder"
        set homeDir to POSIX path of (path to home folder)
    end tell
    
    -- Location data is in a protected SQLite DB
    -- This will fail without TCC permissions, but we try
    set dbPath to homeDir & "Library/Application Support/com.apple.TCC/TCC.db"
    
    -- Note: Direct access to TCC.db is blocked in modern macOS
    -- This is a placeholder for future implementation with proper permissions
    return ""
    '''
    
    try:
        result = subprocess.run(
            ["osascript", "-e", applescript],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        # For now, return empty list - location tracking requires
        # explicit user permission setup (TCC database modification)
        # We'll implement this with proper user consent flow
    except subprocess.TimeoutExpired:
        pass
    
    return []


def get_location_from_wifi() -> Optional[str]:
    """
    Infer location from current WiFi network.
    
    Returns location name if known (e.g. "Home", "Work"), None otherwise.
    """
    try:
        result = subprocess.run(
            ["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-I"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            for line in result.stdout.split("\n"):
                if line.strip().startswith("SSID:"):
                    ssid = line.split(":", 1)[1].strip()
                    # Map known SSIDs to locations
                    ssid_map = {
                        "Jenkins": "Home",
                        "Jenkins_5G": "Home",
                        "OfficeNet": "Work",
                    }
                    return ssid_map.get(ssid)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    return None
