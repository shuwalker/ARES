"""Tests for heartbeat plan resumption."""

from __future__ import annotations

import pytest
from api.schedule_scheduler import resume_paused_plan
from api.dispatch_service import DispatchService
from core.si import orchestrator, planner
from core.si.types import PlanStatus, StepStatus


class MockRegistry:
    @classmethod
    def get_available(cls):
        return {"jaeger_local": MockWorkerBackend()}


class MockWorkerBackend:
    name = "jaeger_local"
    model_name = "mock-model"

    def is_available(self) -> bool:
        return True

    def run_turn(self, message: str, session_id: str) -> dict:
        if "CONTINUE" in message or "RESUME" in message:
            return {"text": "Resumed step execution", "tokens_used": 50}
        return {"text": f"Response: {message}", "tokens_used": 100}


def test_resume_paused_plan(tmp_path, monkeypatch):
    """A paused plan can be resumed on next heartbeat."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)
    monkeypatch.setattr("core.si.worker_registry._BUILTIN_WORKERS", {
        "jaeger_local": type('WorkerRecord', (), {
            'worker_id': 'jaeger_local',
            'display_name': 'Jaeger AI',
            'capabilities': [type('Capability', (), {'capability_id': 'conversation', 'proficiency': 0.9})()]
        })()
    })

    # Create a multi-step plan
    plan = planner.create_plan(
        goal="Process data and analyze results",
        intent="research",
        simple=False,
    )
    plan = planner.assign_workers(plan)
    orchestrator.save_plan(plan)

    # Manually mark as paused (simulating approval gate)
    plan.status = PlanStatus.PAUSED
    plan.steps[0].status = StepStatus.COMPLETED
    orchestrator.save_plan(plan)

    # Resume via heartbeat
    service = DispatchService(backend_registry=MockRegistry)
    result = resume_paused_plan(plan.plan_id, "conv_1")

    assert result is not None
    assert result["status"] in ["step_completed", "awaiting_approval"]


def test_resume_skips_completed_plan(tmp_path, monkeypatch):
    """Completed plans are not resumed."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    plan = planner.create_plan(goal="Done", intent="conversation", simple=True)
    plan.status = PlanStatus.COMPLETED
    orchestrator.save_plan(plan)

    result = resume_paused_plan(plan.plan_id, "conv_1")

    assert result is None  # Not resumed


def test_resume_skips_failed_plan(tmp_path, monkeypatch):
    """Failed plans are not resumed."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    plan = planner.create_plan(goal="Failed task", intent="conversation", simple=True)
    plan.status = PlanStatus.FAILED
    orchestrator.save_plan(plan)

    result = resume_paused_plan(plan.plan_id, "conv_1")

    assert result is None  # Not resumed


def test_plan_persists_across_restart(tmp_path, monkeypatch):
    """A paused plan survives app restart (persisted in DB)."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    # Create and pause a plan
    plan = planner.create_plan(goal="Long task", intent="research")
    plan.status = PlanStatus.PAUSED
    orchestrator.save_plan(plan)

    # Simulate app restart (new process, same DB)
    loaded = orchestrator.load_plan(plan.plan_id)

    assert loaded is not None
    assert loaded.status == PlanStatus.PAUSED


def test_dispatch_pauses_on_budget(tmp_path, monkeypatch):
    """Dispatch pauses plan when budget exceeded."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)

    from api.budget_service import set_budget_limit, record_cost

    # Set tight budget
    set_budget_limit("jaeger_local", daily_limit=1.0, monthly_limit=10.0)

    # Already spent most of budget
    record_cost("jaeger_local", "conv_1", "plan_1", "step_1", cost_usd=0.99, tokens_used=990, model="claude")

    service = DispatchService(backend_registry=MockRegistry)

    result = service.dispatch_turn(
        user_message="This will exceed budget",
        conversation_id="conv_1",
    )

    assert result["status"] == "paused_budget_limit"
    assert "Daily budget limit" in result["reason"]

    # Plan should be paused
    plan = orchestrator.load_plan(result["plan_id"])
    assert plan.status == PlanStatus.PAUSED
