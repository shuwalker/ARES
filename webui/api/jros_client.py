"""jros_client — the single-file Python client for a JROS agent.

Copy this ONE file into your app. Stdlib only, no dependencies, no JROS
package in your venv: it drives an EXISTING JROS install by spawning its
``jaeger bridge`` and speaking the v1 NDJSON client protocol over stdio.

    from jros_client import JrosClient

    with JrosClient() as jros:                 # uses env/configured JROS home
        reply = jros.turn("hello", session="myapp")
        print(reply["text"])

Pick an agent:       JrosClient(instance="lilith")
Non-default install: JrosClient(jaeger_home="/opt/jaeger")
Full control:        JrosClient(command=["/path/to/jaeger", "bridge"])

The wire contract is jaeger_os/interfaces/protocol.py (v1); this file is
tested against the same protocol_v1_fixtures.json that pins the Swift
client, so it cannot silently drift.
"""

from __future__ import annotations

import json
import os
import subprocess
import threading
from pathlib import Path
from typing import Any, Callable

from api.jros_paths import jaeger_home as resolve_jaeger_home
from api.jros_paths import jaeger_launcher as resolve_jaeger_launcher
from api.jros_paths import jros_instance_name as resolve_jros_instance_name

PROTOCOL_VERSION = "1"


class JrosError(RuntimeError):
    """The bridge failed to boot, died mid-turn, or returned a fatal."""


def _default_command(jaeger_home: str | None, instance: str | None = None) -> list[str]:
    """Resolve the installed launcher command: <home>/jaeger bridge [instance].

    JROS 0.7's implicit default bridge can emit ``ready`` and still stall on
    the first real turn. ARES therefore passes the resolved instance as a
    positional bridge argument whenever it knows one.
    """
    raw_home = resolve_jaeger_home() if jaeger_home is None else jaeger_home
    launcher = resolve_jaeger_launcher() if jaeger_home is None else Path(str(raw_home)).expanduser() / "jaeger"
    home = launcher.parent
    if not launcher.exists():
        raise JrosError(
            f"no JROS install at {home} — install first "
            "(https://github.com/JenkinsRobotics/JROS) or pass "
            "jaeger_home=/path/to/install")
    command = [str(launcher), "bridge"]
    if instance:
        command.append(instance)
    return command


def _append_instance_arg_if_bridge(command: list[str], instance: str | None) -> list[str]:
    """Append instance to explicit ``jaeger bridge`` commands when absent."""
    out = list(command)
    if not instance or len(out) != 2:
        return out
    if Path(out[0]).name == "jaeger" and out[1] == "bridge":
        out.append(instance)
    return out


# ── wire helpers (client side of jaeger_os/interfaces/protocol.py) ──

def _parse(line: str) -> dict[str, Any] | None:
    line = line.strip()
    if not line:
        return None
    try:
        obj = json.loads(line)
    except (json.JSONDecodeError, ValueError):
        return None
    if not isinstance(obj, dict) or not ("type" in obj or "op" in obj):
        return None
    return obj


def _encode(frame: dict[str, Any]) -> str:
    return json.dumps(frame, ensure_ascii=False) + "\n"


def send_op(text: str, session: str = "") -> dict[str, Any]:
    return {"op": "send", "text": text, "session": session}


def respond_op(id: str, answer: str) -> dict[str, Any]:
    return {"op": "respond", "id": id, "answer": answer}


def quit_op() -> dict[str, Any]:
    return {"op": "quit"}


class JrosClient:
    """Drive a JROS agent over the v1 client protocol.

    Synchronous, one turn at a time (one local model). Tool/state events
    and mid-turn requests surface via the ``turn()`` callbacks.
    """

    def __init__(self, jaeger_home: str | None = None,
                 instance: str | None = None,
                 command: list[str] | None = None,
                 env: dict | None = None, cwd: str | None = None) -> None:
        resolved_instance = instance or resolve_jros_instance_name()
        self._command = (
            _append_instance_arg_if_bridge(command, resolved_instance)
            if command is not None else _default_command(jaeger_home, resolved_instance)
        )
        self._env = dict(env) if env is not None else os.environ.copy()
        if resolved_instance:
            self._env["JAEGER_INSTANCE_NAME"] = resolved_instance
        self._cwd = cwd
        self._proc: subprocess.Popen | None = None
        self._stderr_lines: list[str] = []
        self._stderr_thread: threading.Thread | None = None
        self.ready: dict[str, Any] | None = None

    # ── lifecycle ─────────────────────────────────────────────────
    def start(self) -> dict[str, Any]:
        """Spawn the bridge and await its ``ready`` handshake. Returns
        ``{"instance": ..., "model": ...}``. Raises :class:`JrosError`."""
        self._proc = subprocess.Popen(
            self._command,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,        # capture stderr for diagnostics
            text=True, bufsize=1, env=self._env, cwd=self._cwd,
        )
        # Drain stderr on a background thread so it doesn't block stdout reads
        self._stderr_lines = []
        if self._proc.stderr is not None:
            def _drain_stderr():
                try:
                    for line in self._proc.stderr:
                        self._stderr_lines.append(line.rstrip())
                except Exception:
                    pass
            self._stderr_thread = threading.Thread(target=_drain_stderr, daemon=True)
            self._stderr_thread.start()
        for line in self._proc.stdout:        # type: ignore[union-attr]
            frame = _parse(line)
            if frame is None:
                continue
            if frame.get("type") == "ready":
                self.ready = {"instance": frame.get("instance"),
                              "model": frame.get("model")}
                return self.ready
            if frame.get("type") == "fatal":
                # Surface stderr in the error message for diagnostics
                stderr_tail = "\n".join(self._stderr_lines[-10:]) if self._stderr_lines else ""
                msg = str(frame.get("error", "boot failed"))
                if stderr_tail:
                    msg = f"{msg}\nBridge stderr:\n{stderr_tail}"
                raise JrosError(msg)
        # Bridge exited before ready — include stderr for diagnostics
        stderr_tail = "\n".join(self._stderr_lines[-10:]) if self._stderr_lines else ""
        msg = "bridge exited before ready"
        if stderr_tail:
            msg = f"{msg}\nBridge stderr:\n{stderr_tail}"
        raise JrosError(msg)

    def close(self) -> None:
        proc = self._proc
        if proc is not None and proc.poll() is None:
            try:
                self._write(quit_op())
            except Exception:  # noqa: BLE001
                pass
            try:
                proc.wait(timeout=3)
            except Exception:  # noqa: BLE001
                try:
                    proc.terminate()
                    proc.wait(timeout=3)
                except Exception:  # noqa: BLE001
                    try:
                        proc.kill()
                        proc.wait(timeout=3)
                    except Exception:  # noqa: BLE001
                        pass
        self._proc = None

    def __enter__(self) -> "JrosClient":
        self.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    # ── turns ─────────────────────────────────────────────────────
    def turn(self, text: str, session: str = "", *,
             on_event: Callable[[dict], None] | None = None,
             on_request: Callable[[dict], str] | None = None) -> dict[str, Any]:
        """Run one turn; return ``{"text": ..., "error": ...}``.

        ``on_event(frame)`` fires for each tool/state frame; ``on_request``
        is called for a mid-turn prompt (approval/clarify/secret) and must
        return the answer (default "deny")."""
        if self._proc is None:
            raise JrosError("not started")
        self._write(send_op(text, session))
        for line in self._proc.stdout:        # type: ignore[union-attr]
            frame = _parse(line)
            if frame is None:
                continue
            kind = frame.get("type")
            if kind == "reply":
                return {"text": frame.get("text", ""),
                        "error": frame.get("error")}
            if kind == "request":
                answer = on_request(frame) if on_request else "deny"
                self._write(respond_op(
                    str(frame.get("id", "")), answer or "deny"))
            elif kind in ("tool", "state"):
                if on_event is not None:
                    on_event(frame)
            elif kind == "fatal":
                raise JrosError(str(frame.get("error", "bridge failed")))
        raise JrosError("bridge exited mid-turn")

    # ── internals ─────────────────────────────────────────────────
    def _write(self, frame: dict[str, Any]) -> None:
        assert self._proc is not None and self._proc.stdin is not None
        self._proc.stdin.write(_encode(frame))
        self._proc.stdin.flush()
