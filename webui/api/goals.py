"""WebUI bridge for Hermes persistent session goals."""

from __future__ import annotations

import copy
import logging
import re
import threading
import time
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

try:  # Exposed as a module attribute so tests can monkeypatch it directly.
    from hermes_cli.goals import (  # type: ignore
        CONTINUATION_PROMPT_TEMPLATE,
        DEFAULT_MAX_TURNS,
        GoalManager as _NativeGoalManager,
        GoalState,
        judge_goal,
    )
except Exception:  # pragma: no cover - depends on installed hermes-agent
    CONTINUATION_PROMPT_TEMPLATE = ""  # type: ignore
    DEFAULT_MAX_TURNS = 20  # type: ignore
    _NativeGoalManager = None  # type: ignore
    GoalState = None  # type: ignore
    judge_goal = None  # type: ignore

GoalManager = _NativeGoalManager  # type: ignore

_DB_CACHE: dict[str, Any] = {}


def _default_max_turns() -> int:
    """Return the configured /goal turn budget, defaulting to Hermes' 20 turns."""
    try:
        from api import config as _config

        cfg = getattr(_config, "cfg", {}) or {}
        goals_cfg = cfg.get("goals", {}) if isinstance(cfg, dict) else {}
        if not isinstance(goals_cfg, dict):
            return int(DEFAULT_MAX_TURNS or 20)
        return max(1, int(goals_cfg.get("max_turns", DEFAULT_MAX_TURNS or 20) or 20))
    except Exception:
        return int(DEFAULT_MAX_TURNS or 20)


def _meta_key(session_id: str) -> str:
    return f"goal:{session_id}"


def _profile_db(profile_home: str | Path):
    """Return a SessionDB pinned to *profile_home*, without reading HERMES_HOME.

    The upstream Hermes GoalManager persists through hermes_cli.goals.load_goal(),
    which resolves SessionDB from process-global HERMES_HOME. WebUI sessions are
    profile-scoped and can run concurrently, so the WebUI bridge uses an explicit
    state.db path whenever the caller provides the session's profile home.
    """
    home = Path(profile_home).expanduser().resolve()
    key = str(home)
    cached = _DB_CACHE.get(key)
    if cached is not None:
        return cached
    try:
        from hermes_state import SessionDB  # type: ignore

        db = SessionDB(db_path=home / "state.db")
    except Exception as exc:  # pragma: no cover - import/env dependent
        logger.debug("GoalManager profile DB unavailable for %s: %s", home, exc)
        return None
    _DB_CACHE[key] = db
    return db


class _ProfileGoalManager:
    """Small WebUI-local GoalManager adapter with explicit profile persistence."""

    def __init__(self, session_id: str, *, profile_home: str | Path, default_max_turns: int = 20):
        if GoalState is None:
            raise RuntimeError("Hermes goal state unavailable")
        self.session_id = session_id
        self.profile_home = Path(profile_home).expanduser().resolve()
        self.default_max_turns = int(default_max_turns or DEFAULT_MAX_TURNS or 20)
        self._state = self._load()

    @property
    def state(self):
        return self._state

    def _load(self):
        db = _profile_db(self.profile_home)
        if db is None or not self.session_id:
            return None
        try:
            raw = db.get_meta(_meta_key(self.session_id))
        except Exception as exc:
            logger.debug("GoalManager profile get_meta failed: %s", exc)
            return None
        if not raw:
            return None
        try:
            return GoalState.from_json(raw)  # type: ignore[union-attr]
        except Exception as exc:
            logger.warning("GoalManager profile state parse failed for %s: %s", self.session_id, exc)
            return None

    def _save(self, state) -> None:
        db = _profile_db(self.profile_home)
        if db is None or not self.session_id or state is None:
            return
        try:
            db.set_meta(_meta_key(self.session_id), state.to_json())
        except Exception as exc:
            logger.debug("GoalManager profile set_meta failed: %s", exc)

    def is_active(self) -> bool:
        return self._state is not None and self._state.status == "active"

    def has_goal(self) -> bool:
        return self._state is not None and self._state.status in ("active", "paused")

    def status_line(self) -> str:
        s = self._state
        if s is None or s.status in ("cleared",):
            return "No active goal. Set one with /goal <text>."
        turns = f"{s.turns_used}/{s.max_turns} turns"
        if s.status == "active":
            return f"⊙ Goal (active, {turns}): {s.goal}"
        if s.status == "paused":
            extra = f" — {s.paused_reason}" if s.paused_reason else ""
            return f"⏸ Goal (paused, {turns}{extra}): {s.goal}"
        if s.status == "done":
            return f"✓ Goal done ({turns}): {s.goal}"
        return f"Goal ({s.status}, {turns}): {s.goal}"

    def set(self, goal: str, *, max_turns: Optional[int] = None):
        goal = (goal or "").strip()
        if not goal:
            raise ValueError("goal text is empty")
        state = GoalState(  # type: ignore[operator]
            goal=goal,
            status="active",
            turns_used=0,
            max_turns=int(max_turns) if max_turns else self.default_max_turns,
            created_at=time.time(),
            last_turn_at=0.0,
        )
        self._state = state
        self._save(state)
        return state

    def pause(self, reason: str = "user-paused"):
        if not self._state:
            return None
        self._state.status = "paused"
        self._state.paused_reason = reason
        self._save(self._state)
        return self._state

    def resume(self, *, reset_budget: bool = True):
        if not self._state:
            return None
        self._state.status = "active"
        self._state.paused_reason = None
        if reset_budget:
            self._state.turns_used = 0
        self._save(self._state)
        return self._state

    def clear(self) -> None:
        if self._state is None:
            return
        self._state.status = "cleared"
        self._save(self._state)
        self._state = None

    def evaluate_after_turn(self, last_response: str, *, user_initiated: bool = True) -> Dict[str, Any]:
        state = self._state
        if state is None or state.status != "active":
            return {
                "status": state.status if state else None,
                "should_continue": False,
                "continuation_prompt": None,
                "verdict": "inactive",
                "reason": "no active goal",
                "message": "",
            }

        state.turns_used += 1
        state.last_turn_at = time.time()

        if judge_goal is None:
            verdict, reason = "continue", "goal judge unavailable"
        else:
            verdict, reason = judge_goal(state.goal, str(last_response or ""))
        state.last_verdict = verdict
        state.last_reason = reason

        if verdict == "done":
            state.status = "done"
            self._save(state)
            return {
                "status": "done",
                "should_continue": False,
                "continuation_prompt": None,
                "verdict": "done",
                "reason": reason,
                "message": f"✓ Goal achieved: {reason}",
            }

        if state.turns_used >= state.max_turns:
            state.status = "paused"
            state.paused_reason = f"turn budget exhausted ({state.turns_used}/{state.max_turns})"
            self._save(state)
            return {
                "status": "paused",
                "should_continue": False,
                "continuation_prompt": None,
                "verdict": "continue",
                "reason": reason,
                "message": (
                    f"⏸ Goal paused — {state.turns_used}/{state.max_turns} turns used. "
                    "Use /goal resume to keep going, or /goal clear to stop."
                ),
            }

        self._save(state)
        return {
            "status": "active",
            "should_continue": True,
            "continuation_prompt": self.next_continuation_prompt(),
            "verdict": "continue",
            "reason": reason,
            "message": f"↻ Continuing toward goal ({state.turns_used}/{state.max_turns}): {reason}",
        }

    def next_continuation_prompt(self) -> Optional[str]:
        if not self._state or self._state.status != "active":
            return None
        return CONTINUATION_PROMPT_TEMPLATE.format(goal=self._state.goal)


def _manager(session_id: str, *, profile_home: str | Path | None = None):
    if GoalManager is None:
        return None
    if profile_home and GoalManager is _NativeGoalManager and GoalState is not None:
        try:
            return _ProfileGoalManager(
                session_id=session_id,
                profile_home=profile_home,
                default_max_turns=_default_max_turns(),
            )
        except Exception as exc:
            logger.debug("Profile-scoped GoalManager unavailable: %s", exc)
            return None
    return GoalManager(session_id=session_id, default_max_turns=_default_max_turns())


def _state_payload(state: Any) -> Optional[Dict[str, Any]]:
    if state is None:
        return None
    return {
        "goal": getattr(state, "goal", "") or "",
        "status": getattr(state, "status", "") or "",
        "turns_used": int(getattr(state, "turns_used", 0) or 0),
        "max_turns": int(getattr(state, "max_turns", 0) or 0),
        "last_verdict": getattr(state, "last_verdict", None),
        "last_reason": getattr(state, "last_reason", None),
        "paused_reason": getattr(state, "paused_reason", None),
    }


def _payload(
    *,
    ok: bool = True,
    action: str,
    message: str,
    state: Any = None,
    error: str | None = None,
    kickoff_prompt: str | None = None,
    decision: Dict[str, Any] | None = None,
    message_key: str | None = None,
    message_args: list[Any] | None = None,
) -> Dict[str, Any]:
    body: Dict[str, Any] = {
        "ok": bool(ok),
        "action": action,
        "message": message,
        "goal": _state_payload(state),
    }
    if error:
        body["error"] = error
    if kickoff_prompt:
        body["kickoff_prompt"] = kickoff_prompt
    if decision is not None:
        body["decision"] = decision
    if message_key:
        body["message_key"] = message_key
    if message_args is not None:
        body["message_args"] = [a for a in message_args if a is not None]
    return body


def _goal_status_payload(state: Any, *, default_message: str | None = None) -> Dict[str, Any]:
    """Build localized-status style payload fields from a goal state."""
    if default_message is None:
        default_message = "No active goal. Set one with /goal <text>."
    if state is None:
        return {"message": default_message, "message_key": "goal_status_none"}
    status = str(getattr(state, "status", "") or "").strip()
    if status in ("cleared",):
        return {"message": default_message, "message_key": "goal_status_none"}
    turns_used = int(getattr(state, "turns_used", 0) or 0)
    max_turns = int(getattr(state, "max_turns", 0) or 0)
    goal = str(getattr(state, "goal", "") or "")
    if status == "active":
        return {
            "message": f"⊙ Goal (active, {turns_used}/{max_turns} turns): {goal}",
            "message_key": "goal_status_active",
            "message_args": [turns_used, max_turns, goal],
        }
    if status == "paused":
        reason = str(getattr(state, "paused_reason", "") or "")
        return {
            "message": f"⏸ Goal (paused, {turns_used}/{max_turns}{' — ' + reason if reason else ''}): {goal}",
            "message_key": "goal_status_paused",
            "message_args": [turns_used, max_turns, reason, goal],
        }
    if status == "done":
        return {
            "message": f"✓ Goal done ({turns_used}/{max_turns}): {goal}",
            "message_key": "goal_status_done",
            "message_args": [turns_used, max_turns, goal],
        }
    return {
        "message": f"Goal ({status}, {turns_used}/{max_turns}): {goal}",
        "message_args": [status, turns_used, max_turns, goal],
    }


def _extract_goal_turns_from_message(message: str) -> tuple[int, int]:
    """Best-effort extraction for continuation messages like '(1/20)'."""
    if not message:
        return 0, 0
    match = re.search(r"\((\d+)\s*/\s*(\d+)\)", message)
    if not match:
        return 0, 0
    try:
        return int(match.group(1)), int(match.group(2))
    except Exception:
        return 0, 0


def _goal_decision_payload(
    decision: Dict[str, Any],
    state: Any,
) -> Dict[str, Any]:
    """Attach goal message i18n key/args to an evaluation decision."""
    if not isinstance(decision, dict):
        return decision
    status = str(decision.get("status") or "").strip()
    reason = str(decision.get("reason") or "").strip()
    turns_used = int(getattr(state, "turns_used", 0) or 0)
    max_turns = int(getattr(state, "max_turns", 0) or 0)
    if (turns_used, max_turns) == (0, 0):
        turns_used, max_turns = _extract_goal_turns_from_message(str(decision.get("message") or ""))

    if status == "done":
        return {
            **decision,
            "message_key": "goal_achieved",
            "message_args": [reason],
        }
    if status == "paused":
        return {
            **decision,
            "message_key": "goal_paused_budget_exhausted",
            "message_args": [turns_used, max_turns],
        }
    if decision.get("should_continue"):
        return {
            **decision,
            "message_key": "goal_continuing",
            "message_args": [turns_used, max_turns, reason],
        }
    return decision


def goal_state_snapshot(session_id: str, *, profile_home: str | Path | None = None) -> Any:
    """Return a deep copy of current goal state for rollback before kickoff."""
    mgr = _manager(str(session_id or ""), profile_home=profile_home)
    if mgr is None:
        return None
    return copy.deepcopy(getattr(mgr, "state", None))


def restore_goal_state(session_id: str, snapshot: Any, *, profile_home: str | Path | None = None) -> None:
    """Restore a prior goal state after kickoff stream creation fails."""
    mgr = _manager(str(session_id or ""), profile_home=profile_home)
    if mgr is None:
        return
    if snapshot is None:
        try:
            mgr.clear()
        except Exception:
            pass
        return
    if isinstance(mgr, _ProfileGoalManager):
        mgr._state = snapshot
        mgr._save(snapshot)
        return
    try:
        from hermes_cli.goals import save_goal  # type: ignore

        save_goal(str(session_id or ""), snapshot)
    except Exception as exc:  # pragma: no cover - native fallback only
        logger.debug("Goal state restore failed for %s: %s", session_id, exc)


def goal_command_payload(
    session_id: str,
    args: str = "",
    *,
    stream_running: bool = False,
    profile_home: str | Path | None = None,
) -> Dict[str, Any]:
    """Return the WebUI response payload for a /goal command.

    Mirrors the gateway command semantics:
    - /goal or /goal status shows status
    - /goal pause pauses
    - /goal resume resumes without auto-starting a turn
    - /goal clear|stop|done clears
    - /goal <text> sets a new active goal and returns kickoff_prompt so the
      caller can start the first normal user-role turn immediately.
    """
    sid = str(session_id or "").strip()
    if not sid:
        return _payload(ok=False, action="error", error="missing_session", message="session_id required")

    mgr = _manager(sid, profile_home=profile_home)
    if mgr is None:
        return _payload(ok=False, action="error", error="unavailable", message="Goals unavailable on this session.")

    text = str(args or "").strip()
    lower = text.lower()

    if not text or lower == "status":
        state = getattr(mgr, "state", None)
        status_payload = _goal_status_payload(state)
        return _payload(action="status", state=state, **status_payload)

    if lower == "pause":
        state = mgr.pause(reason="user-paused")
        if state is None:
            return _payload(
                ok=False,
                action="pause",
                error="no_goal",
                message="No goal set.",
                message_key="goal_no_goal",
            )
        return _payload(
            action="pause",
            message=f"⏸ Goal paused: {state.goal}",
            message_key="goal_paused",
            message_args=[str(state.goal)],
            state=state,
        )

    if lower == "resume":
        state = mgr.resume()
        if state is None:
            return _payload(
                ok=False,
                action="resume",
                error="no_goal",
                message="No goal to resume.",
                message_key="goal_no_goal",
            )
        return _payload(
            action="resume",
            message=(
                f"▶ Goal resumed: {state.goal}\n"
                "Send a new message, or type continue, to kick it off."
            ),
            message_key="goal_resumed",
            message_args=[str(state.goal)],
            state=state,
        )

    if lower in ("clear", "stop", "done"):
        had = bool(mgr.has_goal())
        mgr.clear()
        return _payload(
            action="clear",
            message="Goal cleared." if had else "No active goal.",
            message_key="goal_cleared" if had else "goal_no_goal",
            state=getattr(mgr, "state", None),
        )

    if stream_running:
        return _payload(
            ok=False,
            action="set",
            error="agent_running",
            message=(
                "Agent is running — use /goal status / pause / clear mid-run, "
                "or /stop before setting a new goal."
            ),
        )

    try:
        state = mgr.set(text)
    except ValueError as exc:
        return _payload(ok=False, action="set", error="invalid_goal", message=f"Invalid goal: {exc}")

    return _payload(
        action="set",
        message=(
            f"⊙ Goal set ({state.max_turns}-turn budget): {state.goal}\n"
            "I'll keep working until the goal is done, you pause/clear it, or the budget is exhausted.\n"
            "Controls: /goal status · /goal pause · /goal resume · /goal clear"
        ),
        message_key="goal_set",
        message_args=[state.max_turns, state.goal],
        state=state,
        kickoff_prompt=state.goal,
    )


def has_active_goal(
    session_id: str,
    *,
    profile_home: str | Path | None = None,
) -> bool:
    """Return True when the session has an active standing goal to evaluate."""
    sid = str(session_id or "").strip()
    if not sid:
        return False
    mgr = _manager(sid, profile_home=profile_home)
    if mgr is None:
        return False
    try:
        return bool(mgr.is_active())
    except Exception as exc:
        logger.debug("goal active-state check failed for session=%s: %s", sid, exc)
        return False


def evaluate_goal_after_turn(
    session_id: str,
    last_response: str,
    *,
    user_initiated: bool = True,
    profile_home: str | Path | None = None,
) -> Dict[str, Any]:
    """Evaluate a completed turn against the standing goal, if any."""
    sid = str(session_id or "").strip()
    if not sid:
        return {
            "status": None,
            "should_continue": False,
            "continuation_prompt": None,
            "verdict": "inactive",
            "reason": "missing session_id",
            "message": "",
        }
    mgr = _manager(sid, profile_home=profile_home)
    if mgr is None:
        return {
            "status": None,
            "should_continue": False,
            "continuation_prompt": None,
            "verdict": "inactive",
            "reason": "goals unavailable",
            "message": "",
        }
    try:
        if not mgr.is_active():
            return {
                "status": getattr(getattr(mgr, "state", None), "status", None),
                "should_continue": False,
                "continuation_prompt": None,
                "verdict": "inactive",
                "reason": "no active goal",
                "message": "",
            }
        decision = mgr.evaluate_after_turn(str(last_response or ""), user_initiated=user_initiated)
    except Exception as exc:
        logger.debug("goal evaluation failed for session=%s: %s", sid, exc)
        return {
            "status": None,
            "should_continue": False,
            "continuation_prompt": None,
            "verdict": "error",
            "reason": f"goal evaluation failed: {type(exc).__name__}",
            "message": "",
        }
    if not isinstance(decision, dict):
        decision = {}
    decision.setdefault("should_continue", False)
    decision.setdefault("continuation_prompt", None)
    decision.setdefault("message", "")
    decision = dict(decision)
    decision = _goal_decision_payload(decision, getattr(mgr, "state", None))
    return decision


# ── Server-side goal continuation (Option Z parity) ─────────────────────────
# evaluate_goal_after_turn() only decides whether to continue; historically the
# actual next turn was started by the FRONTEND re-POSTing continuation_prompt
# after receiving the 'goal_continue' SSE event. If no tab is open when a
# goal-related turn finishes, that event has no listener, the continuation
# prompt is never resubmitted, and the goal silently stalls until some client
# happens to reconnect. api/background_process.py already solved the identical
# shape of problem for background-process notify_on_complete wakeups (Option
# Z: server-side turn start, no browser round-trip); this mirrors that pattern
# for goal continuations instead of duplicating a browser-mediated path.
_DEFERRED_GOAL_CONTINUATIONS: Dict[str, str] = {}
_DEFERRED_GOAL_CONTINUATIONS_LOCK = threading.Lock()


def record_deferred_goal_continuation(session_id: str, continuation_prompt: str) -> None:
    """Persist a goal continuation prompt for delivery once the session goes idle.

    Called from the streaming worker at the point a goal-related turn decides
    should_continue=True. The turn that just decided this is itself still the
    active run for the session, so the continuation cannot be started here —
    it would race its own teardown and 409. drain_deferred_goal_continuation_
    for_session() (called from the SAME worker right after unregister_active_run)
    claims and delivers it once the session is genuinely idle.
    """
    sid = str(session_id or "").strip()
    prompt = str(continuation_prompt or "").strip()
    if not sid or not prompt:
        return
    with _DEFERRED_GOAL_CONTINUATIONS_LOCK:
        _DEFERRED_GOAL_CONTINUATIONS[sid] = prompt


def claim_deferred_goal_continuation(session_id: str) -> Optional[str]:
    """Atomically pop and return the deferred continuation prompt, if any."""
    sid = str(session_id or "").strip()
    if not sid:
        return None
    with _DEFERRED_GOAL_CONTINUATIONS_LOCK:
        return _DEFERRED_GOAL_CONTINUATIONS.pop(sid, None) or None


def _start_server_side_goal_continuation_turn(session_id: str, continuation_prompt: str) -> None:
    """Start the goal-continuation turn server-side (Option Z for goals).

    Runs on a short-lived daemon thread so the caller (turn teardown) never
    blocks. Reuses api.routes.start_session_turn — the same HTTP-handler-free
    entrypoint background_process.py uses for process-wakeup turns — so
    concurrency (per-session agent lock, 409 on an already-active turn) and
    session/model resolution are identical to a human-typed turn. A human
    reopening the tab and re-sending continuation_prompt themselves races this
    exactly like a human /api/chat/start races a process wakeup: whichever
    gets the per-session lock first wins, the other 409s.
    """

    def _runner() -> None:
        try:
            from api.routes import start_session_turn

            resp = start_session_turn(session_id, continuation_prompt, source="goal_continuation")
            status = int((resp or {}).get("_status", 200) or 200)
            if status == 409:
                # Raced an active turn (human reconnect, or a sibling
                # deferred-continuation thread). Re-defer so the winning
                # turn's own teardown redelivers it instead of losing it.
                record_deferred_goal_continuation(session_id, continuation_prompt)
                logger.debug(
                    "server-side goal continuation raced an active turn for session %s; re-deferred",
                    session_id,
                )
            elif status >= 400:
                logger.warning(
                    "server-side goal continuation failed for session %s: status=%s err=%r",
                    session_id,
                    status,
                    (resp or {}).get("error"),
                )
            else:
                logger.info(
                    "server-side goal continuation turn started for session %s (stream_id=%s)",
                    session_id,
                    (resp or {}).get("stream_id"),
                )
        except Exception:
            logger.warning(
                "server-side goal continuation turn raised for session %s",
                session_id,
                exc_info=True,
            )

    threading.Thread(
        target=_runner,
        name=f"hermes-webui-goal-continuation-{str(session_id)[:8]}",
        daemon=True,
    ).start()


def drain_deferred_goal_continuation_for_session(session_id: str) -> int:
    """Turn-teardown idle-hook: redeliver a deferred goal continuation once idle.

    Must be called AFTER unregister_active_run() for this stream so
    _session_has_active_turn() no longer counts the just-ended turn. If a
    different stream for the same session is still active (cancel/reconnect),
    the entry is left in place for that stream's own teardown to claim.

    Returns 1 if a continuation turn was started, 0 otherwise.
    """
    sid = str(session_id or "").strip()
    if not sid:
        return 0
    try:
        from api.background_process import _session_has_active_turn

        if _session_has_active_turn(sid):
            return 0
    except Exception:
        logger.debug("goal continuation idle-check failed for session %s", sid, exc_info=True)
        return 0
    prompt = claim_deferred_goal_continuation(sid)
    if not prompt:
        return 0
    _start_server_side_goal_continuation_turn(sid, prompt)
    return 1
