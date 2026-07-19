"""Background Missions orchestrator — CEO-style multi-agent task dispatch.

Distinct from webui/api/goals.py (single-session standing-goal continuation,
the "/goal" command and its Hermes-native GoalManager). A Mission takes one
complex prompt, decomposes it into sub-tasks via a direct Anthropic/OpenAI
call (api/llm_client.py), and dispatches each sub-task either:
  - to the existing Hermes/JROS backends, via an ephemeral sub-session and
    api.routes.start_session_turn — reuses the full agent loop (tools,
    memory, persona) instead of reimplementing turn execution, or
  - directly to Anthropic/OpenAI (api/llm_client.py) for pure-reasoning
    sub-tasks that don't need tool use.

Threading model mirrors api/background_process.py and the goal-continuation
runner in api/goals.py: plain daemon threading.Thread, no asyncio (the rest
of this webui's background work is thread-based, so this stays consistent).
Mission state is in-memory only for v1 (module-level dict + lock) — lost on
server restart, the same tradeoff most in-memory registries in this webui
make. Add SessionDB persistence later the same way api/goals.py's
_ProfileGoalManager does, if missions need to survive restarts.
"""
from __future__ import annotations

import logging
import threading
import time
import uuid
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_MISSIONS: Dict[str, Dict[str, Any]] = {}
_MISSIONS_LOCK = threading.Lock()

_SUBTASK_POLL_INTERVAL_S = 1.0
_SUBTASK_TIMEOUT_S = 900  # 15 min ceiling per agentic sub-task

_DECOMPOSE_SYSTEM_PROMPT = (
    'You are the CEO of a small team of AI agents. Break the user\'s request '
    'into a short list of concrete, independently-executable sub-tasks. '
    'Respond with ONLY a JSON array, no prose, no markdown fences. Each '
    'element: {"description": str, "kind": "coding"|"reasoning", '
    '"backend": "hermes"|"jros"|"anthropic"|"openai"}. Use "coding" + '
    '"hermes" for work needing a terminal/file/tool-using agent. Use '
    '"reasoning" + "anthropic" or "openai" for analysis, review, or writing '
    'that needs no tools. Keep the list to 2-6 sub-tasks.'
)


def _new_id() -> str:
    return uuid.uuid4().hex[:12]


def _mission_payload(mission: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": mission["id"],
        "prompt": mission["prompt"],
        "status": mission["status"],
        "created_at": mission["created_at"],
        "error": mission.get("error"),
        "subtasks": [
            {
                "id": st["id"],
                "description": st["description"],
                "backend": st["backend"],
                "label": st["label"],
                "status": st["status"],
                "result": st.get("result"),
                "error": st.get("error"),
            }
            for st in mission["subtasks"]
        ],
    }


def _emit(session_id: str, mission: Dict[str, Any]) -> None:
    try:
        from api.background_process import _emit_to_session_streams

        _emit_to_session_streams(session_id, "mission_update", _mission_payload(mission))
    except Exception:
        logger.debug("mission_update emit failed for mission %s", mission.get("id"), exc_info=True)


def list_missions(session_id: str) -> List[Dict[str, Any]]:
    sid = str(session_id or "").strip()
    with _MISSIONS_LOCK:
        return [
            _mission_payload(m)
            for m in sorted(_MISSIONS.values(), key=lambda m: m["created_at"], reverse=True)
            if m.get("session_id") == sid
        ]


def get_mission(mission_id: str, session_id: str) -> Optional[Dict[str, Any]]:
    sid = str(session_id or "").strip()
    with _MISSIONS_LOCK:
        m = _MISSIONS.get(str(mission_id or "").strip())
        if not m or m.get("session_id") != sid:
            return None
        return _mission_payload(m)


def cancel_mission(mission_id: str, session_id: str) -> bool:
    """Best-effort cancel: marks the mission cancelled so the runner thread
    stops dispatching further sub-tasks after the one in flight finishes.
    Does not interrupt an already-dispatched agentic sub-task turn."""
    sid = str(session_id or "").strip()
    with _MISSIONS_LOCK:
        m = _MISSIONS.get(str(mission_id or "").strip())
        if not m or m.get("session_id") != sid:
            return False
        if m["status"] not in ("done", "failed", "cancelled"):
            m["status"] = "cancelling"
    return True


def create_mission(session_id: str, prompt: str, *, profile: str | None = None) -> Dict[str, Any]:
    sid = str(session_id or "").strip()
    if not sid:
        raise ValueError("session_id is required")
    prompt = (prompt or "").strip()
    if not prompt:
        raise ValueError("prompt is empty")
    mission: Dict[str, Any] = {
        "id": _new_id(),
        "session_id": sid,
        "prompt": prompt,
        "status": "planning",
        "created_at": time.time(),
        "error": None,
        "subtasks": [],
        "profile": profile,
    }
    with _MISSIONS_LOCK:
        _MISSIONS[mission["id"]] = mission
        # Snapshot before the worker starts: the caller gets the mission in
        # its just-created state ("planning"), never racing the worker to
        # "done" on fast machines.
        payload = _mission_payload(mission)
    threading.Thread(
        target=_run_mission,
        args=(mission["id"],),
        name=f"ares-mission-{mission['id']}",
        daemon=True,
    ).start()
    return payload


def _run_mission(mission_id: str) -> None:
    with _MISSIONS_LOCK:
        mission = _MISSIONS.get(mission_id)
    if mission is None:
        return

    try:
        subtasks = _decompose(mission["prompt"])
    except Exception as exc:
        logger.warning("mission %s decomposition failed", mission_id, exc_info=True)
        with _MISSIONS_LOCK:
            mission["status"] = "failed"
            mission["error"] = f"Planning failed: {exc}"
        _emit(mission["session_id"], mission)
        return

    with _MISSIONS_LOCK:
        mission["subtasks"] = subtasks
        mission["status"] = "running"
    _emit(mission["session_id"], mission)

    for subtask in subtasks:
        with _MISSIONS_LOCK:
            if mission["status"] == "cancelling":
                mission["status"] = "cancelled"
                _emit(mission["session_id"], mission)
                return
            subtask["status"] = "running"
        _emit(mission["session_id"], mission)

        try:
            result = _run_subtask(mission, subtask)
            with _MISSIONS_LOCK:
                subtask["status"] = "done"
                subtask["result"] = result
        except Exception as exc:
            logger.warning("mission %s subtask %s failed", mission_id, subtask["id"], exc_info=True)
            with _MISSIONS_LOCK:
                subtask["status"] = "failed"
                subtask["error"] = str(exc)
        _emit(mission["session_id"], mission)

    with _MISSIONS_LOCK:
        failed = any(st["status"] == "failed" for st in mission["subtasks"])
        mission["status"] = "failed" if failed else "done"
    _emit(mission["session_id"], mission)


def _decompose(prompt: str) -> List[Dict[str, Any]]:
    import json

    from api.llm_client import LLMProviderUnavailable, call_anthropic, call_openai

    try:
        raw = call_anthropic(prompt, system=_DECOMPOSE_SYSTEM_PROMPT)
    except LLMProviderUnavailable:
        raw = call_openai(prompt, system=_DECOMPOSE_SYSTEM_PROMPT)

    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.lower().startswith("json"):
            raw = raw[4:]
    parsed = json.loads(raw)
    if not isinstance(parsed, list) or not parsed:
        raise ValueError("planner returned no sub-tasks")

    subtasks: List[Dict[str, Any]] = []
    for item in parsed:
        if not isinstance(item, dict):
            continue
        description = str(item.get("description") or "").strip()
        if not description:
            continue
        kind = str(item.get("kind") or "reasoning").strip().lower()
        backend = str(item.get("backend") or "").strip().lower()
        if backend not in ("hermes", "jros", "anthropic", "openai"):
            backend = "hermes" if kind == "coding" else "anthropic"
        subtasks.append({
            "id": _new_id(),
            "description": description,
            "kind": kind,
            "backend": backend,
            "label": f"{backend.title()}: {description[:60]}",
            "status": "pending",
            "result": None,
            "error": None,
        })
    if not subtasks:
        raise ValueError("planner returned no usable sub-tasks")
    return subtasks


def _run_subtask(mission: Dict[str, Any], subtask: Dict[str, Any]) -> str:
    backend = subtask["backend"]
    if backend in ("hermes", "jros"):
        return _run_agentic_subtask(mission, subtask, backend)
    from api.llm_client import call_anthropic, call_openai

    if backend == "openai":
        return call_openai(subtask["description"])
    return call_anthropic(subtask["description"])


def _run_agentic_subtask(mission: Dict[str, Any], subtask: Dict[str, Any], backend: str) -> str:
    """Dispatch a sub-task through the real Hermes/JROS agent loop.

    Runs in an ephemeral sub-session so the sub-agent's tool calls, memory,
    and transcript don't pollute the user's main chat session, reusing
    api.routes.start_session_turn — the same HTTP-handler-free entrypoint
    background_process.py's Option Z wakeups and api/goals.py's server-side
    goal continuations use to start a turn with no browser round-trip.
    """
    from api.background_process import _session_has_active_turn
    from api.models import get_session, new_session
    from api.routes import start_session_turn

    sub_session = new_session(profile=mission.get("profile"))
    sub_session.ares_backend = backend
    sub_session.title = f"Mission: {subtask['description'][:60]}"
    sub_session.save()
    subtask["sub_session_id"] = sub_session.id

    resp = start_session_turn(sub_session.id, subtask["description"], source="mission")
    status = int((resp or {}).get("_status", 200) or 200)
    if status >= 400:
        raise RuntimeError((resp or {}).get("error") or f"sub-task turn failed to start (status {status})")

    # Give the daemon worker thread a moment to register the active run
    # before polling for it to clear, so we don't read "idle" before it starts.
    time.sleep(0.5)
    deadline = time.time() + _SUBTASK_TIMEOUT_S
    while time.time() < deadline:
        if not _session_has_active_turn(sub_session.id):
            break
        time.sleep(_SUBTASK_POLL_INTERVAL_S)
    else:
        raise TimeoutError(f"sub-task did not finish within {_SUBTASK_TIMEOUT_S}s")

    finished = get_session(sub_session.id)
    if finished is None:
        raise RuntimeError("sub-task session vanished before completion")
    for msg in reversed(finished.messages or []):
        if msg.get("role") == "assistant":
            content = msg.get("content")
            return content if isinstance(content, str) else str(content)
    return ""
