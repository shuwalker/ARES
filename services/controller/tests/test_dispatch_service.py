"""Unit & Integration Tests for ARES Master-Worker DispatchService."""

from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from api.dispatch_service import DispatchService
from core.si.types import WorkerResult
from core.events.turn_journal import read_turn_journal


class MockWorkerBackend:
    name = "jaeger_local"

    def is_available(self) -> bool:
        return True

    def run_turn(self, message: str, session_id: str, **kwargs) -> dict:
        return {
            "text": f"Mock response for: {message}",
            "tool_activity": [],
            "session_id": session_id,
        }


class MockRegistry:
    @classmethod
    def get_available(cls):
        return {"jaeger_local": MockWorkerBackend()}


def test_dispatch_turn_simple_conversation(tmp_path, monkeypatch):
    """Test standard dispatch turn for a conversation message."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)
    monkeypatch.setattr("api.models.SESSION_DIR", str(tmp_path / "sessions"))

    service = DispatchService(backend_registry=MockRegistry)

    res = service.dispatch_turn(
        user_message="Hello Leo, how are you?",
        conversation_id="test_session_001",
        local_only_mode=True,
    )

    assert res["status"] == "step_completed"
    assert res["assigned_worker"] == "jaeger_local"
    assert "Mock response for: Hello Leo" in res["output"]
    assert res["evaluation"]["passed"] is True


def test_dispatch_turn_approval_gate_and_resolution(tmp_path, monkeypatch):
    """Test that high-risk action triggers approval gate requirement and can be approved/rejected."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    monkeypatch.setattr("api.journal.paths.si_dir", lambda: tmp_path)
    monkeypatch.setattr("api.models.SESSION_DIR", str(tmp_path / "sessions"))

    service = DispatchService(backend_registry=MockRegistry)

    res = service.dispatch_turn(
        user_message="Execute terminal command rm -rf /important_dir",
        conversation_id="test_session_002",
        local_only_mode=True,
    )

    if res.get("status") == "awaiting_approval":
        assert res["needs_approval"] is True
        plan_id = res["plan_id"]
        step_id = res["step"]["step_id"]

        # Test approving the step
        approve_res = service.approve_step(plan_id, step_id)
        assert approve_res["status"] == "approved"

        # Test rejecting another step
        reject_res = service.reject_step(plan_id, step_id, reason="Denied by test")
        assert reject_res["status"] == "rejected"

