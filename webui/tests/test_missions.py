"""api.missions — CEO multi-agent Missions orchestrator.

Distinct from test_goals-style coverage: missions.py decomposes a prompt into
sub-tasks via api.llm_client and dispatches each either through the existing
Hermes/JROS agent loop (ephemeral sub-session + start_session_turn) or a
direct Anthropic/OpenAI call. These tests monkeypatch both dispatch paths so
they exercise the orchestrator's own logic without needing a real model, a
real Hermes/JROS install, or a live server.
"""
import time
from types import SimpleNamespace

import pytest

from api import missions


@pytest.fixture(autouse=True)
def _clear_missions_registry():
    missions._MISSIONS.clear()
    yield
    missions._MISSIONS.clear()


def _wait_until(predicate, timeout=2.0, interval=0.02):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


def test_create_mission_requires_session_id_and_prompt():
    with pytest.raises(ValueError):
        missions.create_mission("", "do something")
    with pytest.raises(ValueError):
        missions.create_mission("sid-1", "   ")


def test_create_mission_runs_reasoning_only_plan_to_completion(monkeypatch):
    monkeypatch.setattr(
        missions,
        "_decompose",
        lambda prompt: [
            {
                "id": "st1",
                "description": "Review the architecture",
                "kind": "reasoning",
                "backend": "anthropic",
                "label": "Anthropic: Review the architecture",
                "status": "pending",
                "result": None,
                "error": None,
            }
        ],
    )
    monkeypatch.setattr("api.llm_client.call_anthropic", lambda prompt, **kw: "Looks solid.")

    mission = missions.create_mission("sid-1", "Review my app")
    assert mission["status"] in ("planning", "running")

    ok = _wait_until(lambda: missions.get_mission(mission["id"], "sid-1")["status"] == "done")
    assert ok, "mission never reached done"

    final = missions.get_mission(mission["id"], "sid-1")
    assert final["subtasks"][0]["status"] == "done"
    assert final["subtasks"][0]["result"] == "Looks solid."


def test_mission_marked_failed_when_decomposition_unavailable(monkeypatch):
    from api.llm_client import LLMProviderUnavailable

    def _boom(prompt, **kw):
        raise LLMProviderUnavailable("no key configured")

    monkeypatch.setattr("api.llm_client.call_anthropic", _boom)
    monkeypatch.setattr("api.llm_client.call_openai", _boom)

    mission = missions.create_mission("sid-1", "Do a thing")
    ok = _wait_until(lambda: missions.get_mission(mission["id"], "sid-1")["status"] == "failed")
    assert ok, "mission never reached failed"
    assert "no key configured" in missions.get_mission(mission["id"], "sid-1")["error"]


def test_mission_marked_failed_when_a_subtask_errors(monkeypatch):
    monkeypatch.setattr(
        missions,
        "_decompose",
        lambda prompt: [
            {
                "id": "st1", "description": "x", "kind": "reasoning", "backend": "anthropic",
                "label": "Anthropic: x", "status": "pending", "result": None, "error": None,
            }
        ],
    )

    def _boom(prompt, **kw):
        raise RuntimeError("provider exploded")

    monkeypatch.setattr("api.llm_client.call_anthropic", _boom)

    mission = missions.create_mission("sid-1", "Do a thing")
    ok = _wait_until(lambda: missions.get_mission(mission["id"], "sid-1")["status"] == "failed")
    assert ok
    final = missions.get_mission(mission["id"], "sid-1")
    assert final["subtasks"][0]["status"] == "failed"
    assert "provider exploded" in final["subtasks"][0]["error"]


def test_list_missions_filters_by_session(monkeypatch):
    monkeypatch.setattr(missions, "_decompose", lambda prompt: [])
    m1 = missions.create_mission("sid-a", "task a")
    m2 = missions.create_mission("sid-b", "task b")
    _wait_until(lambda: missions.get_mission(m1["id"], "sid-a")["status"] in ("done", "failed"))
    _wait_until(lambda: missions.get_mission(m2["id"], "sid-b")["status"] in ("done", "failed"))

    sid_a_missions = missions.list_missions("sid-a")
    assert [m["id"] for m in sid_a_missions] == [m1["id"]]
    assert missions.get_mission(m1["id"], "sid-b") is None, "must not leak across sessions"


def test_cancel_mission_ownership_check(monkeypatch):
    monkeypatch.setattr(missions, "_decompose", lambda prompt: [])
    mission = missions.create_mission("sid-a", "task a")
    assert missions.cancel_mission(mission["id"], "sid-wrong") is False
    assert missions.cancel_mission(mission["id"], "sid-a") is True
    assert missions.cancel_mission("no-such-id", "sid-a") is False


def test_run_agentic_subtask_extracts_last_assistant_message(monkeypatch):
    fake_session = SimpleNamespace(id="sub-1", ares_backend=None, title=None, save=lambda: None)
    monkeypatch.setattr("api.models.new_session", lambda **kw: fake_session)
    monkeypatch.setattr("api.routes.start_session_turn", lambda *a, **kw: {"_status": 200, "stream_id": "s1"})
    monkeypatch.setattr("api.background_process._session_has_active_turn", lambda sid: False)
    monkeypatch.setattr(
        "api.models.get_session",
        lambda sid: SimpleNamespace(messages=[
            {"role": "user", "content": "do it"},
            {"role": "assistant", "content": "done, here's the PR"},
        ]),
    )
    monkeypatch.setattr(missions.time, "sleep", lambda *_: None)

    subtask = {"description": "write the feature", "sub_session_id": None}
    result = missions._run_agentic_subtask({"profile": None}, subtask, "hermes")
    assert result == "done, here's the PR"
    assert fake_session.ares_backend == "hermes"


def test_run_agentic_subtask_raises_on_start_failure(monkeypatch):
    fake_session = SimpleNamespace(id="sub-2", ares_backend=None, title=None, save=lambda: None)
    monkeypatch.setattr("api.models.new_session", lambda **kw: fake_session)
    monkeypatch.setattr(
        "api.routes.start_session_turn",
        lambda *a, **kw: {"_status": 409, "error": "session already has an active stream"},
    )

    with pytest.raises(RuntimeError):
        missions._run_agentic_subtask({"profile": None}, {"description": "x"}, "hermes")
