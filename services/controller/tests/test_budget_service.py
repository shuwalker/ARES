"""Tests for budget tracking and enforcement."""

from __future__ import annotations

import pytest
from api.budget_service import (
    set_budget_limit,
    record_cost,
    get_daily_spend,
    get_monthly_spend,
    check_budget,
    get_budget_limit,
)


def test_set_and_retrieve_budget_limit(tmp_path, monkeypatch):
    """Budget limits can be set and retrieved."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("test_worker", daily_limit=10.0, monthly_limit=100.0)

    limit = get_budget_limit("test_worker")
    assert limit is not None
    assert limit.daily_limit == 10.0
    assert limit.monthly_limit == 100.0


def test_record_cost(tmp_path, monkeypatch):
    """Costs can be recorded."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_a", daily_limit=10.0, monthly_limit=100.0)

    record_cost(
        worker_id="worker_a",
        session_id="session_1",
        plan_id="plan_1",
        step_id="step_1",
        cost_usd=2.50,
        tokens_used=1000,
        model="claude-opus",
    )

    daily_spent = get_daily_spend("worker_a")
    assert daily_spent == 2.50


def test_check_budget_allows_execution(tmp_path, monkeypatch):
    """Budget check allows execution when budget available."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_b", daily_limit=10.0, monthly_limit=100.0)
    record_cost("worker_b", "s1", "p1", "st1", 5.0, 1000, "claude-opus")

    result = check_budget("worker_b", cost_estimate=2.0)
    assert result["can_execute"] is True
    assert result["daily_spent"] == 5.0


def test_check_budget_blocks_on_daily_limit(tmp_path, monkeypatch):
    """Budget check blocks execution when daily limit exceeded."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_c", daily_limit=10.0, monthly_limit=100.0)
    record_cost("worker_c", "s1", "p1", "st1", 9.5, 1000, "claude-opus")

    result = check_budget("worker_c", cost_estimate=1.0)
    assert result["can_execute"] is False
    assert "Daily budget limit" in result["reason"]


def test_check_budget_blocks_on_monthly_limit(tmp_path, monkeypatch):
    """Budget check blocks execution when monthly limit exceeded."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_d", daily_limit=100.0, monthly_limit=50.0)
    record_cost("worker_d", "s1", "p1", "st1", 49.5, 1000, "claude-opus")

    result = check_budget("worker_d", cost_estimate=1.0)
    assert result["can_execute"] is False
    assert "Monthly budget limit" in result["reason"]


def test_soft_warning_at_threshold(tmp_path, monkeypatch):
    """Soft warning issued at 80% threshold."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_e", daily_limit=10.0, monthly_limit=100.0)
    record_cost("worker_e", "s1", "p1", "st1", 7.0, 1000, "claude-opus")

    result = check_budget("worker_e", cost_estimate=1.0)
    assert result["can_execute"] is True
    assert result["warning"] is not None
    assert "Approaching" in result["warning"]


def test_no_limit_allows_unlimited_spend(tmp_path, monkeypatch):
    """Workers with no limit set can execute unlimited."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    result = check_budget("unlimited_worker", cost_estimate=999.0)
    assert result["can_execute"] is True
    assert result["daily_limit"] is None


def test_get_monthly_spend(tmp_path, monkeypatch):
    """Monthly spend is calculated correctly."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    set_budget_limit("worker_f", daily_limit=100.0, monthly_limit=200.0)

    record_cost("worker_f", "s1", "p1", "st1", 50.0, 1000, "claude-opus")
    record_cost("worker_f", "s2", "p2", "st2", 75.0, 1500, "claude-opus")

    monthly = get_monthly_spend("worker_f")
    assert monthly == 125.0
