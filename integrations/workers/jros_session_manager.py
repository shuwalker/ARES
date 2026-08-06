"""Session-scoped lifecycle manager for integrations.providers.jaeger.bridge_client.JrosClient.

Why this exists: BackendRegistry.get_available() (integrations/workers/
cli_backends.py) instantiates a fresh JaegerWorker on every single dispatch
turn. A persistent bridge process therefore cannot live as an attribute on
JaegerWorker itself — the object holding it is thrown away right after the
turn, which would leak one orphaned, model-loaded ``jaeger bridge`` process
per turn. This module is the one place that owns the actual long-lived
JrosClient per ARES session_id, shared across those short-lived JaegerWorker
instances.

Deliberately uses integrations.providers.jaeger.bridge_client's JrosClient,
not a hand-rolled or separately-vendored copy: that module already resolves
the launcher/instance correctly via api.providers.jaeger.paths (including a
fix for a known JROS 0.7 "ready-then-stall" bug on the implicit default
bridge) and already has its own turn-level locking and stderr diagnostics.
Duplicating that here would recreate exactly the kind of "two
implementations quietly disagree" problem already found once this session
(two separate classes both registering as "jaeger_local").

Crash handling relies entirely on JrosClient's own documented contract: a
dead or misbehaving bridge surfaces as ``JrosError`` from ``turn()``/
``start()``, treated as "this session's process is gone" and retried once
with a fresh process. If the retry also fails, the error is raised to the
caller — CLAUDE.md's "report what it dropped" rule: a crashed worker must
be an honest error, never silently empty text.
"""
from __future__ import annotations

import logging
import threading
from typing import Any, Callable

from integrations.providers.jaeger.bridge_client import JrosClient, JrosError

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_clients: dict[str, JrosClient] = {}


def run_turn(
    session_id: str,
    message: str,
    *,
    jaeger_home: str | None = None,
    command: list[str] | None = None,
    on_event: Callable[[dict], None] | None = None,
    on_request: Callable[[dict], str] | None = None,
) -> dict[str, Any]:
    """Run one turn on the persistent bridge process for ``session_id``,
    starting it on first use. ``jaeger_home`` should be the root JaegerWorker
    already detected as available (integrations/workers/jaeger_worker.py's
    self.bridge_root) so this never re-resolves and potentially disagrees
    with what is_available() already checked. ``command`` is an explicit
    override, mainly for tests that fake the bridge process rather than
    requiring a real JaegerAI install.

    Returns ``{"text": ..., "error": ...}`` per JrosClient.turn(); raises
    JrosError if the bridge cannot be started or stays dead after one
    restart attempt.
    """
    client = _get_or_start(session_id, jaeger_home=jaeger_home, command=command)
    try:
        return client.turn(message, session=session_id, on_event=on_event, on_request=on_request)
    except JrosError:
        logger.warning("Jaeger bridge for session %s died mid-turn; restarting once", session_id)
        with _lock:
            _clients.pop(session_id, None)
        fresh = _get_or_start(session_id, jaeger_home=jaeger_home, command=command)
        return fresh.turn(message, session=session_id, on_event=on_event, on_request=on_request)


def _get_or_start(session_id: str, *, jaeger_home: str | None, command: list[str] | None) -> JrosClient:
    with _lock:
        existing = _clients.get(session_id)
        if existing is not None:
            return existing
    # Boot outside the lock: cold start is multi-second (LLM + tool + voice
    # model load per the real bridge), and it must not stall other sessions.
    client = JrosClient(jaeger_home=jaeger_home, command=command)
    client.start()
    with _lock:
        # Another thread may have won the race for this session_id while we
        # were booting; keep whichever process claimed the slot first and
        # close the loser rather than leaking it.
        winner = _clients.setdefault(session_id, client)
        if winner is not client:
            client.close()
        return winner


def close_session(session_id: str) -> None:
    """Tear down the bridge process for one session, if any is running."""
    with _lock:
        client = _clients.pop(session_id, None)
    if client is not None:
        try:
            client.close()
        except Exception:
            logger.warning("Failed to close Jaeger bridge for session %s", session_id, exc_info=True)


def close_all() -> None:
    """Best-effort teardown of every live bridge process.

    Call from the controller's shutdown_runtime() (fastapi_app/lifecycle.py)
    so a restarted or crashed ARES process never leaves an orphaned,
    model-loaded ``jaeger bridge`` process running in the background.
    """
    with _lock:
        clients = list(_clients.items())
        _clients.clear()
    for session_id, client in clients:
        try:
            client.close()
        except Exception:
            logger.warning("Failed to close Jaeger bridge for session %s", session_id, exc_info=True)
