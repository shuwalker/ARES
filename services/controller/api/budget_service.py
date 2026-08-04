"""Budget tracking and enforcement for workers.

Tracks daily/monthly spending per worker and enforces hard/soft limits.
"""

from __future__ import annotations

import logging
import sqlite3
import time
from datetime import datetime
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class BudgetLimit:
    """Budget cap for a worker."""

    def __init__(self, worker_id: str, daily_limit: float, monthly_limit: float, soft_threshold: float = 0.8):
        self.worker_id = worker_id
        self.daily_limit = daily_limit
        self.monthly_limit = monthly_limit
        self.soft_threshold = soft_threshold


def _get_budget_db() -> sqlite3.Connection:
    """Get or create budget tracking database."""
    from api.journal.paths import si_dir

    db_path = si_dir() / "budget.db"
    db = sqlite3.connect(str(db_path))
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS budget_limits (
            worker_id TEXT PRIMARY KEY,
            daily_limit REAL,
            monthly_limit REAL,
            soft_threshold REAL DEFAULT 0.8,
            created_at REAL
        )
    """
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS cost_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id TEXT,
            session_id TEXT,
            plan_id TEXT,
            step_id TEXT,
            cost_usd REAL,
            tokens_used INTEGER,
            model TEXT,
            timestamp REAL
        )
    """
    )
    db.commit()
    return db


def set_budget_limit(worker_id: str, daily_limit: float, monthly_limit: float, soft_threshold: float = 0.8) -> None:
    """Set budget limits for a worker."""
    db = _get_budget_db()
    db.execute(
        """
        INSERT OR REPLACE INTO budget_limits (worker_id, daily_limit, monthly_limit, soft_threshold, created_at)
        VALUES (?, ?, ?, ?, ?)
    """,
        (worker_id, daily_limit, monthly_limit, soft_threshold, time.time()),
    )
    db.commit()
    logger.info("Budget set for %s: $%.2f/day, $%.2f/month", worker_id, daily_limit, monthly_limit)


def get_budget_limit(worker_id: str) -> Optional[BudgetLimit]:
    """Get budget limit for a worker. Returns None if no limit set."""
    db = _get_budget_db()
    row = db.execute(
        "SELECT worker_id, daily_limit, monthly_limit, soft_threshold FROM budget_limits WHERE worker_id = ?",
        (worker_id,),
    ).fetchone()

    if not row:
        return None

    return BudgetLimit(worker_id=row[0], daily_limit=row[1], monthly_limit=row[2], soft_threshold=row[3])


def record_cost(
    worker_id: str,
    session_id: str,
    plan_id: str,
    step_id: str,
    cost_usd: float,
    input_tokens: int | str = 0,  # Can be int or str (for backward compat)
    output_tokens: int | str = 0,  # Can be int or str (for backward compat)
    model: str = "unknown",
    provider: str = "unknown",
    tokens_used: Optional[int] = None,  # Backward compatibility
) -> None:
    """Record the cost of a step execution with detailed token breakdown.

    Supports both calling conventions:
    - New: record_cost(..., input_tokens=1000, output_tokens=500, model="claude-opus")
    - Old: record_cost(..., tokens_used=1500, model="claude-opus")
    """
    db = _get_budget_db()

    # Handle backward compatibility
    # Old style: record_cost(worker_id, session_id, plan_id, step_id, cost_usd, tokens_used, model)
    # New style: record_cost(worker_id, session_id, plan_id, step_id, cost_usd, input_tokens=0, output_tokens=0, model="", ...)

    total_tokens = 0

    if isinstance(output_tokens, str):
        # Old calling style detected: input_tokens is actually tokens_used (int)
        # output_tokens is actually model (str)
        total_tokens = int(input_tokens)
        model = output_tokens
    elif tokens_used is not None:
        # Explicit tokens_used provided
        total_tokens = tokens_used
    else:
        # New style: input_tokens + output_tokens
        total_tokens = int(input_tokens) + int(output_tokens)

    db.execute(
        """
        INSERT INTO cost_records (worker_id, session_id, plan_id, step_id, cost_usd, tokens_used, model, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
        (worker_id, session_id, plan_id, step_id, cost_usd, total_tokens, model, time.time()),
    )
    db.commit()


def get_daily_spend(worker_id: str) -> float:
    """Get total spending for a worker today (UTC)."""
    db = _get_budget_db()

    now = time.time()
    today_start = now - (now % 86400)

    row = db.execute(
        "SELECT SUM(cost_usd) FROM cost_records WHERE worker_id = ? AND timestamp >= ?",
        (worker_id, today_start),
    ).fetchone()

    return row[0] if row and row[0] else 0.0


def get_monthly_spend(worker_id: str) -> float:
    """Get total spending for a worker this calendar month."""
    db = _get_budget_db()

    now = datetime.utcnow()
    month_start = datetime(now.year, now.month, 1)
    month_start_timestamp = month_start.timestamp()

    row = db.execute(
        "SELECT SUM(cost_usd) FROM cost_records WHERE worker_id = ? AND timestamp >= ?",
        (worker_id, month_start_timestamp),
    ).fetchone()

    return row[0] if row and row[0] else 0.0


def check_budget(worker_id: str, cost_estimate: float = 0.0) -> Dict[str, Any]:
    """Check if worker can execute next step.

    Returns dict with:
        - can_execute: bool
        - daily_spent: float
        - daily_limit: Optional[float]
        - monthly_spent: float
        - monthly_limit: Optional[float]
        - warning: Optional[str]
        - reason: Optional[str] (if can_execute=False)
    """
    limit = get_budget_limit(worker_id)

    if limit is None:
        return {
            "can_execute": True,
            "daily_spent": 0.0,
            "daily_limit": None,
            "monthly_spent": 0.0,
            "monthly_limit": None,
            "warning": None,
            "reason": None,
        }

    daily_spent = get_daily_spend(worker_id)
    monthly_spent = get_monthly_spend(worker_id)

    result = {
        "can_execute": True,
        "daily_spent": daily_spent,
        "daily_limit": limit.daily_limit,
        "monthly_spent": monthly_spent,
        "monthly_limit": limit.monthly_limit,
        "warning": None,
        "reason": None,
    }

    # Check monthly limit first
    if monthly_spent + cost_estimate >= limit.monthly_limit:
        result["can_execute"] = False
        result["reason"] = f"Monthly budget limit (${limit.monthly_limit:.2f}) exceeded"
        return result

    # Check daily limit
    if daily_spent + cost_estimate >= limit.daily_limit:
        result["can_execute"] = False
        result["reason"] = f"Daily budget limit (${limit.daily_limit:.2f}) exceeded"
        return result

    # Soft warning at threshold
    daily_percent = (daily_spent + cost_estimate) / limit.daily_limit if limit.daily_limit > 0 else 0
    if daily_percent >= limit.soft_threshold:
        result["warning"] = f"Approaching daily limit: {daily_percent * 100:.0f}% spent"

    return result


def get_all_budgets() -> Dict[str, BudgetLimit]:
    """Get all configured budget limits."""
    db = _get_budget_db()
    rows = db.execute("SELECT worker_id, daily_limit, monthly_limit, soft_threshold FROM budget_limits").fetchall()

    return {row[0]: BudgetLimit(row[0], row[1], row[2], row[3]) for row in rows}
