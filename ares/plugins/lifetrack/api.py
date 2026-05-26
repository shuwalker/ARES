"""ARES LifeTrack — FastAPI endpoints.

REST API for LifeTrack data.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from datetime import datetime, timedelta
from typing import Optional

from .models import DailyReconciliation, WeeklyReport, ActivityCategory
from . import db


router = APIRouter(prefix="/api/lifetrack", tags=["lifetrack"])


@router.get("/today", response_model=DailyReconciliation)
async def get_today():
    """Get today's reconciliation (or yesterday if today not processed)."""
    today = datetime.now()
    reconciliation = db.load_daily_reconciliation(today)
    
    if not reconciliation:
        # Try yesterday
        yesterday = today - timedelta(days=1)
        reconciliation = db.load_daily_reconciliation(yesterday)
        
        if not reconciliation:
            raise HTTPException(status_code=404, detail="No tracking data available")
    
    return reconciliation


@router.get("/date/{date_str}", response_model=DailyReconciliation)
async def get_date(date_str: str):
    """Get reconciliation for a specific date (YYYY-MM-DD)."""
    try:
        date = datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    
    reconciliation = db.load_daily_reconciliation(date)
    
    if not reconciliation:
        raise HTTPException(status_code=404, detail=f"No data for {date_str}")
    
    return reconciliation


@router.get("/week", response_model=WeeklyReport)
async def get_week(
    weeks_back: int = Query(default=0, ge=0, le=52, description="Weeks to look back")
):
    """Get weekly report."""
    today = datetime.now()
    days_since_monday = today.weekday()
    start_of_week = today - timedelta(days=days_since_monday)
    start_of_week = start_of_week - timedelta(weeks=weeks_back)
    end_of_week = start_of_week + timedelta(days=6)
    
    report = db.load_weekly_report(start_of_week, end_of_week)
    
    if not report:
        raise HTTPException(status_code=404, detail="No weekly data available")
    
    return report


@router.get("/stats")
async def get_stats():
    """Get LifeTrack statistics."""
    stats = db.get_stats()
    return {
        "days_tracked": stats["days_tracked"],
        "reconciliations_count": stats["reconciliations_count"],
        "avg_focus_score": round(stats["avg_focus_score"], 3),
        "app_overrides": stats["app_overrides"]
    }


@router.post("/override")
async def set_override(
    bundle_id: str,
    category: str,
    app_name: Optional[str] = None
):
    """Set a custom category for an app."""
    try:
        cat = ActivityCategory(category)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid category. Must be one of: {[c.value for c in ActivityCategory]}"
        )
    
    db.save_app_override(bundle_id, app_name or bundle_id, cat)
    
    return {"status": "ok", "bundle_id": bundle_id, "category": category}


@router.get("/overrides")
async def list_overrides():
    """List all custom app category overrides."""
    overrides = db.load_app_overrides()
    return {
        bundle_id: category.value
        for bundle_id, category in overrides.items()
    }


@router.delete("/override/{bundle_id}")
async def delete_override(bundle_id: str):
    """Delete a custom app category override."""
    from ares.core.db import connect_sqlite

    conn = connect_sqlite(db.DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM app_overrides WHERE bundle_id = ?", (bundle_id,))
    conn.commit()
    conn.close()
    
    return {"status": "ok", "bundle_id": bundle_id}
