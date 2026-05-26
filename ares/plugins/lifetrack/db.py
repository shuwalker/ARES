"""ARES LifeTrack — SQLite database for persistence.

Stores:
- Activity blocks (daily)
- Daily reconciliations
- Weekly reports
- User corrections/labels
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from .models import (
    ActivityBlock, ActivityCategory, DailyPlan, DailyReality,
    DailyReconciliation, WeeklyReport, CalendarEvent
)


DB_PATH = Path.home() / ".ares" / "lifetrack.db"


def init_db():
    """Initialize the LifeTrack database schema."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    # Activity blocks table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS activity_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            start TEXT NOT NULL,
            end TEXT NOT NULL,
            primary_app TEXT,
            category TEXT NOT NULL,
            confidence REAL NOT NULL,
            source TEXT NOT NULL,
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Daily reconciliations table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS daily_reconciliations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL UNIQUE,
            plan_total_minutes REAL,
            reality_total_minutes REAL,
            focus_score REAL NOT NULL,
            distraction_minutes REAL,
            unplanned_work_minutes REAL,
            json_data TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # User corrections table (manual labels)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_corrections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            block_id INTEGER,
            original_category TEXT,
            corrected_category TEXT,
            reason TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (block_id) REFERENCES activity_blocks(id)
        )
    """)
    
    # App category overrides table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS app_overrides (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id TEXT NOT NULL UNIQUE,
            app_name TEXT,
            category TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Indexes for performance
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_blocks_date ON activity_blocks(date)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_blocks_category ON activity_blocks(category)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_reconciliations_date ON daily_reconciliations(date)")
    
    conn.commit()
    conn.close()


def save_activity_blocks(blocks: list[ActivityBlock], date: datetime):
    """Save activity blocks for a specific date."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    date_str = date.strftime("%Y-%m-%d")
    
    # Clear existing blocks for this date (avoid duplicates)
    cursor.execute("DELETE FROM activity_blocks WHERE date = ?", (date_str,))
    
    for block in blocks:
        cursor.execute("""
            INSERT INTO activity_blocks 
            (date, start, end, primary_app, category, confidence, source, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            date_str,
            block.start.isoformat(),
            block.end.isoformat(),
            block.primary_app,
            block.category.value,
            block.confidence,
            block.source,
            block.notes
        ))
    
    conn.commit()
    conn.close()


def load_activity_blocks(date: datetime) -> list[ActivityBlock]:
    """Load activity blocks for a specific date."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    date_str = date.strftime("%Y-%m-%d")
    cursor.execute("""
        SELECT start, end, primary_app, category, confidence, source, notes
        FROM activity_blocks
        WHERE date = ?
        ORDER BY start
    """, (date_str,))
    
    rows = cursor.fetchall()
    conn.close()
    
    blocks = []
    for row in rows:
        blocks.append(ActivityBlock(
            start=datetime.fromisoformat(row[0]),
            end=datetime.fromisoformat(row[1]),
            primary_app=row[2],
            category=ActivityCategory(row[3]),
            confidence=row[4],
            source=row[5],
            notes=row[6] or ""
        ))
    
    return blocks


def save_daily_reconciliation(reconciliation: DailyReconciliation):
    """Save a daily reconciliation record."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    date_str = reconciliation.date.strftime("%Y-%m-%d")
    
    cursor.execute("""
        INSERT OR REPLACE INTO daily_reconciliations
        (date, plan_total_minutes, reality_total_minutes, focus_score,
         distraction_minutes, unplanned_work_minutes, json_data)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        date_str,
        reconciliation.plan.total_planned_minutes,
        reconciliation.reality.total_tracked_minutes,
        reconciliation.focus_score,
        reconciliation.distraction_minutes,
        reconciliation.unplanned_work_minutes,
        reconciliation.model_dump_json()
    ))
    
    conn.commit()
    conn.close()


def load_daily_reconciliation(date: datetime) -> Optional[DailyReconciliation]:
    """Load a daily reconciliation record."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    date_str = date.strftime("%Y-%m-%d")
    cursor.execute("""
        SELECT json_data FROM daily_reconciliations WHERE date = ?
    """, (date_str,))
    
    row = cursor.fetchone()
    conn.close()
    
    if row and row[0]:
        import json
        data = json.loads(row[0])
        return DailyReconciliation(**data)
    
    return None


def load_weekly_report(start_date: datetime, end_date: datetime) -> Optional[WeeklyReport]:
    """Load or build a weekly report from daily reconciliations."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    start_str = start_date.strftime("%Y-%m-%d")
    end_str = end_date.strftime("%Y-%m-%d")
    
    cursor.execute("""
        SELECT json_data FROM daily_reconciliations
        WHERE date >= ? AND date <= ?
        ORDER BY date
    """, (start_str, end_str))
    
    rows = cursor.fetchall()
    conn.close()
    
    if not rows:
        return None
    
    daily_reconciliations = []
    for row in rows:
        if row[0]:
            import json
            data = json.loads(row[0])
            daily_reconciliations.append(DailyReconciliation(**data))
    
    return WeeklyReport(
        start_date=start_date,
        end_date=end_date,
        daily_reconciliations=daily_reconciliations
    )


def save_app_override(bundle_id: str, app_name: str, category: ActivityCategory):
    """Save a user-defined app category override."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT OR REPLACE INTO app_overrides (bundle_id, app_name, category)
        VALUES (?, ?, ?)
    """, (bundle_id, app_name, category.value))
    
    conn.commit()
    conn.close()


def load_app_overrides() -> dict[str, ActivityCategory]:
    """Load all user-defined app category overrides."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    cursor.execute("SELECT bundle_id, category FROM app_overrides")
    rows = cursor.fetchall()
    conn.close()
    
    return {row[0]: ActivityCategory(row[1]) for row in rows}


def get_stats() -> dict:
    """Get basic LifeTrack statistics."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()
    
    # Count days tracked
    cursor.execute("SELECT COUNT(DISTINCT date) FROM activity_blocks")
    days_tracked = cursor.fetchone()[0]
    
    # Count reconciliations
    cursor.execute("SELECT COUNT(*) FROM daily_reconciliations")
    reconciliations_count = cursor.fetchone()[0]
    
    # Average focus score
    cursor.execute("SELECT AVG(focus_score) FROM daily_reconciliations")
    avg_focus = cursor.fetchone()[0] or 0.0
    
    # Total app overrides
    cursor.execute("SELECT COUNT(*) FROM app_overrides")
    overrides_count = cursor.fetchone()[0]
    
    conn.close()
    
    return {
        "days_tracked": days_tracked,
        "reconciliations_count": reconciliations_count,
        "avg_focus_score": avg_focus,
        "app_overrides": overrides_count
    }
