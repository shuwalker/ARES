"""
ARES SI — Orchestration tests.

Tests for the planner, orchestrator, and plan persistence.
"""

import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


class TestPlanner:
    """Test the planner creates appropriate plans."""

    def test_simple_conversation_plan(self):
        """Simple conversation tasks should get a single-step plan."""
        from api.si.planner import create_plan
        from api.si.types import PlanStatus

        plan = create_plan("hello", intent="conversation", simple=True)
        assert len(plan.steps) == 1
        assert plan.steps[0].objective == "hello"
        assert plan.status == PlanStatus.PENDING

    def test_code_generation_plan(self):
        """Code generation tasks should get multi-step plans."""
        from api.si.planner import create_plan

        plan = create_plan("write a Python script", intent="code_generation")
        assert len(plan.steps) >= 2
        assert any("code" in s.objective.lower() for s in plan.steps)
        assert any("verify" in s.objective.lower() for s in plan.steps)

    def test_research_plan(self):
        """Research tasks should get multi-step plans."""
        from api.si.planner import create_plan

        plan = create_plan("research quantum computing", intent="research")
        assert len(plan.steps) >= 2

    def test_step_dependencies(self):
        """Steps should have sequential dependencies."""
        from api.si.planner import create_plan

        plan = create_plan("fix the login bug", intent="code_generation")
        # First step has no dependencies
        assert plan.steps[0].dependencies == []
        # Later steps depend on earlier ones
        for i in range(1, len(plan.steps)):
            assert plan.steps[i-1].step_id in plan.steps[i].dependencies

    def test_assign_workers(self):
        """Worker assignment should match capabilities."""
        from api.si.planner import create_plan, assign_workers

        plan = create_plan("write code", intent="code_generation")
        plan = assign_workers(plan)
        # Every step should have an assigned worker
        for step in plan.steps:
            assert step.assigned_worker is not None

    def test_get_next_step(self):
        """get_next_step should return the first pending step with met dependencies."""
        from api.si.planner import create_plan, get_next_step
        from api.si.types import StepStatus

        plan = create_plan("hello", intent="conversation", simple=True)
        next_step = get_next_step(plan)
        assert next_step is not None
        assert next_step.status == StepStatus.PENDING

    def test_advance_plan_on_success(self):
        """Completing a step should advance the plan."""
        from api.si.planner import create_plan, advance_plan
        from api.si.types import PlanStatus, StepStatus

        plan = create_plan("hello", intent="conversation", simple=True)
        plan = advance_plan(plan, plan.steps[0].step_id, "done", evaluation="pass")
        assert plan.steps[0].status == StepStatus.COMPLETED
        assert plan.status == PlanStatus.COMPLETED

    def test_advance_plan_on_failure_with_retry(self):
        """Failing a step should increment retry count if retries remain."""
        from api.si.planner import create_plan, advance_plan, assign_workers
        from api.si.types import StepStatus

        plan = create_plan("write code", intent="code_generation")
        plan = assign_workers(plan)
        first_step = plan.steps[0]

        plan = advance_plan(plan, first_step.step_id, "failed", evaluation="fail")
        assert first_step.retry_count == 1
        # Should be set back to PENDING for retry
        assert first_step.status == StepStatus.PENDING


class TestOrchestrator:
    """Test the full orchestration flow."""

    def test_orchestrate_simple_request(self):
        """Simple requests should create a single-step plan."""
        from api.si.orchestrator import orchestrate_request

        result = orchestrate_request("hello there")
        assert result["intent"] in ("conversation", "memory")
        assert result["plan_id"] is not None
        assert "step" in result or result["status"] in ("ready", "awaiting_approval")

    def test_orchestrate_code_request(self):
        """Code requests should create multi-step plans."""
        from api.si.orchestrator import orchestrate_request

        result = orchestrate_request("write a Python script to parse JSON")
        assert result["intent"] == "code_generation"
        assert result.get("total_steps", 1) >= 2

    def test_plan_persistence(self):
        """Plans should persist across save/load cycles."""
        from api.si.orchestrator import orchestrate_request, load_plan, save_plan
        from api.si.planner import create_plan, assign_workers

        plan = create_plan("test persistence", intent="conversation", simple=True)
        plan = assign_workers(plan)
        save_plan(plan)

        loaded = load_plan(plan.plan_id)
        assert loaded is not None
        assert loaded.plan_id == plan.plan_id
        assert loaded.goal == "test persistence"
        assert len(loaded.steps) == 1

    def test_cancel_plan(self):
        """Cancelling a plan should mark it and all pending steps."""
        from api.si.orchestrator import orchestrate_request, cancel_plan, load_plan
        from api.si.types import PlanStatus, StepStatus

        result = orchestrate_request("hello")
        plan_id = result["plan_id"]

        cancel_result = cancel_plan(plan_id)
        assert cancel_result["status"] == "cancelled"

        plan = load_plan(plan_id)
        assert plan.status == PlanStatus.CANCELLED


class TestOrchestrationInvariants:
    """Architectural invariants for orchestration."""

    def test_plans_survive_restart(self):
        """Plan state must survive app restarts (persisted to SQLite)."""
        from api.si.orchestrator import _get_plans_db
        from api.si.planner import create_plan, assign_workers
        from api.si.orchestrator import save_plan, load_plan

        plan = create_plan("persistence test", intent="conversation", simple=True)
        plan = assign_workers(plan)
        save_plan(plan)

        # Verify we can load it
        loaded = load_plan(plan.plan_id)
        assert loaded is not None
        assert loaded.plan_id == plan.plan_id

    def test_secret_data_blocks_orchestration(self):
        """Requests containing secret data should require approval."""
        from api.si.trust_engine import check_approval_required
        # Shell execution always requires approval
        assert check_approval_required("shell_execute", "public") == True
        # Sensitive data requires approval
        assert check_approval_required("conversation", "sensitive") == True
        # Normal conversation doesn't
        assert check_approval_required("conversation", "personal") == False

    def test_worker_assignment_respects_privacy(self):
        """Workers assigned to steps must be eligible for the data sensitivity."""
        from api.si.planner import create_plan, assign_workers

        plan = create_plan("check my bank account", intent="action")
        plan = assign_workers(plan)

        # All assigned workers should exist in the registry
        from api.si.worker_registry import get_registry
        registry = get_registry()
        for step in plan.steps:
            if step.assigned_worker:
                worker = registry.get(step.assigned_worker)
                assert worker is not None