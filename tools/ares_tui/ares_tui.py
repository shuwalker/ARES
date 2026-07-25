#!/usr/bin/env python3
"""ARES TUI — Jaeger-method client for the live Companion controller.

Jaeger method (same idea as ``jros_client.py``):
  * One file you can copy/run
  * Talks to an EXISTING runtime (ARES WebUI on :8787) — does not embed an LLM
  * Synchronous turns: send message → wait → print reply
  * No required third-party deps (stdlib only)

Later we can skin this into a full Fallout/Aliens CRT dashboard. This v1 is
the solid bridge + chat loop.

Usage:
  python3 tools/ares_tui/ares_tui.py
  python3 tools/ares_tui/ares_tui.py --worker claude_local
  ares tui
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any


# ── CRT palette (Fallout-lite; pure ANSI, no deps) ─────────────────────
class C:
    RESET = "\033[0m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    AMBER = "\033[38;5;214m"
    AMBER_DIM = "\033[38;5;172m"
    GREEN = "\033[38;5;70m"
    RED = "\033[38;5;167m"
    GREY = "\033[38;5;245m"
    WHITE = "\033[38;5;230m"


def _supports_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


USE_COLOR = _supports_color()


def paint(text: str, *codes: str) -> str:
    if not USE_COLOR or not codes:
        return text
    return "".join(codes) + text + C.RESET


# ── AresClient (Jaeger-style: drive existing install) ──────────────────

class AresError(RuntimeError):
    """Controller unreachable, turn failed, or bad protocol response."""


@dataclass
class AresClient:
    """Drive the ARES Companion over the WebUI HTTP API.

    Analogous to ``JrosClient`` speaking NDJSON to ``jaeger bridge`` — here the
    "bridge" is the always-on ARES controller (LaunchAgent / uvicorn).
    """

    base_url: str = "http://127.0.0.1:8787"
    worker: str = "hermes_local"
    session_id: str = ""
    timeout: float = 180.0
    ready: dict[str, Any] = field(default_factory=dict)

    # ── lifecycle ─────────────────────────────────────────────────
    def start(self) -> dict[str, Any]:
        """Handshake: health + optional session. Raises AresError if down."""
        health = self._req("GET", "/api/health", timeout=10)
        if health.get("status") != "ok":
            raise AresError(f"controller unhealthy: {health}")
        if not self.session_id:
            new = self._req("POST", "/api/session/new", {})
            sid = (new.get("session") or new).get("session_id")
            if not sid:
                raise AresError(f"session/new failed: {new}")
            self.session_id = str(sid)
        self.ready = {
            "status": health.get("status"),
            "si_enabled": bool(health.get("si_enabled")),
            "uptime_seconds": health.get("uptime_seconds"),
            "role": health.get("role"),
            "session_id": self.session_id,
            "worker": self.worker,
            "base_url": self.base_url,
        }
        return self.ready

    def close(self) -> None:
        """No persistent subprocess; session remains on server."""
        return None

    def __enter__(self) -> "AresClient":
        self.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    # ── turns ─────────────────────────────────────────────────────
    def turn(self, text: str) -> dict[str, Any]:
        """One Companion turn. Returns ``{"text", "error", "worker", "elapsed"}``."""
        if not self.session_id:
            raise AresError("not started")
        clean = (text or "").strip()
        if not clean:
            return {"text": "", "error": "empty message", "worker": self.worker, "elapsed": 0.0}

        t0 = time.time()
        start = self._req(
            "POST",
            "/api/chat/start",
            {
                "session_id": self.session_id,
                "message": clean,
                "connection_id": self.worker,
            },
            timeout=self.timeout,
        )
        stream_id = str(start.get("stream_id") or "")
        if not stream_id:
            err = start.get("error") or start.get("message") or str(start)
            return {
                "text": "",
                "error": f"chat/start failed: {err}",
                "worker": self.worker,
                "elapsed": round(time.time() - t0, 1),
            }

        self._wait_stream(stream_id)
        reply = self._latest_assistant()
        return {
            "text": reply,
            "error": None if reply else "empty assistant reply",
            "worker": self.worker,
            "elapsed": round(time.time() - t0, 1),
            "stream_id": stream_id,
        }

    def status(self) -> dict[str, Any]:
        health = self._req("GET", "/api/health", timeout=10)
        return {
            **health,
            "session_id": self.session_id,
            "worker": self.worker,
            "base_url": self.base_url,
        }

    def set_worker(self, worker: str) -> None:
        worker = (worker or "").strip()
        if not worker:
            raise AresError("worker id required")
        self.worker = worker
        if self.ready:
            self.ready["worker"] = worker

    # ── internals ─────────────────────────────────────────────────
    def _req(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        timeout: float | None = None,
    ) -> Any:
        data = None if body is None else json.dumps(body).encode()
        url = self.base_url.rstrip("/") + path
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={"Content-Type": "application/json"} if data else {},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout or self.timeout) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:500]
            raise AresError(f"HTTP {exc.code} {path}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise AresError(
                f"cannot reach ARES at {self.base_url} ({exc.reason}). "
                "Is com.ares.webui running?"
            ) from exc

    def _wait_stream(self, stream_id: str) -> None:
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            st = self._req(
                "GET",
                f"/api/chat/stream/status?stream_id={stream_id}",
                timeout=15,
            )
            if not st.get("active"):
                return
            time.sleep(1.2)
        raise AresError(f"stream {stream_id} still active after {self.timeout}s")

    def _latest_assistant(self) -> str:
        sess = self._req("GET", f"/api/session?session_id={self.session_id}", timeout=30)
        s = sess.get("session") or sess
        for m in reversed(s.get("messages") or []):
            if m.get("role") == "assistant":
                return str(m.get("content") or "").strip()
        return ""


# ── Terminal UI (Jaeger REPL + CRT frame) ──────────────────────────────

BANNER = r"""
╔══════════════════════════════════════════════════════════════╗
║   A R E S   //  COMPANION TERMINAL                           ║
║   Artificial Reasoning & Execution System                    ║
║   method: jaeger-client  ·  bridge: webui controller         ║
╚══════════════════════════════════════════════════════════════╝
"""

HELP = """
commands:
  /help              this text
  /status            controller health + session
  /worker [id]       show or set worker adapter (e.g. hermes_local, claude_local)
  /session           print session id
  /clear             clear local scrollback (server session kept)
  /quit  /exit       leave TUI

anything else is sent as a Companion turn through the active worker.
"""


def _frame_line(width: int = 62) -> str:
    return paint("─" * width, C.AMBER_DIM)


def print_banner(ready: dict[str, Any]) -> None:
    print(paint(BANNER.strip("\n"), C.AMBER, C.BOLD))
    si = "ON" if ready.get("si_enabled") else "OFF"
    print(
        paint("  link ", C.AMBER_DIM)
        + paint(str(ready.get("base_url")), C.GREEN)
        + paint("  si=", C.AMBER_DIM)
        + paint(si, C.GREEN if ready.get("si_enabled") else C.RED)
        + paint("  worker=", C.AMBER_DIM)
        + paint(str(ready.get("worker")), C.WHITE)
    )
    print(
        paint("  session ", C.AMBER_DIM)
        + paint(str(ready.get("session_id")), C.GREY)
    )
    print(_frame_line())
    print(paint("  type to talk · /help for commands · /quit to exit", C.DIM))
    print()


def print_status(client: AresClient) -> None:
    try:
        st = client.status()
    except AresError as exc:
        print(paint(f"  ! {exc}", C.RED))
        return
    print(paint("  STATUS", C.AMBER, C.BOLD))
    for key in ("status", "si_enabled", "uptime_seconds", "role", "sessions", "active_streams"):
        if key in st:
            print(paint(f"    {key}: ", C.AMBER_DIM) + paint(str(st.get(key)), C.WHITE))
    print(paint(f"    worker: {client.worker}", C.WHITE))
    print(paint(f"    session: {client.session_id}", C.GREY))


def run_tui(client: AresClient) -> int:
    print_banner(client.ready)
    while True:
        try:
            prompt = paint("YOU › ", C.AMBER, C.BOLD)
            line = input(prompt)
        except (EOFError, KeyboardInterrupt):
            print()
            print(paint("  link closed.", C.AMBER_DIM))
            return 0

        text = line.strip()
        if not text:
            continue

        if text.startswith("/"):
            parts = text.split(maxsplit=1)
            cmd = parts[0].lower()
            arg = parts[1].strip() if len(parts) > 1 else ""

            if cmd in ("/quit", "/exit", "/q"):
                print(paint("  link closed.", C.AMBER_DIM))
                return 0
            if cmd in ("/help", "/h", "/?"):
                print(paint(HELP, C.AMBER_DIM))
                continue
            if cmd == "/status":
                print_status(client)
                continue
            if cmd == "/session":
                print(paint(f"  session {client.session_id}", C.GREY))
                continue
            if cmd == "/worker":
                if not arg:
                    print(paint(f"  worker={client.worker}", C.WHITE))
                    print(
                        paint(
                            "  examples: hermes_local claude_local grok_local "
                            "codex_local gemini_local ollama_local pi_local",
                            C.DIM,
                        )
                    )
                else:
                    client.set_worker(arg)
                    print(paint(f"  worker → {client.worker}", C.GREEN))
                continue
            if cmd == "/clear":
                # Local visual clear only
                os.system("clear" if os.name != "nt" else "cls")
                print_banner(client.ready)
                continue
            print(paint(f"  unknown command: {cmd}  (try /help)", C.RED))
            continue

        # Companion turn
        print(paint("  … routing through SI / worker …", C.DIM))
        try:
            result = client.turn(text)
        except AresError as exc:
            print(paint(f"ARES ! {exc}", C.RED))
            continue

        elapsed = result.get("elapsed")
        worker = result.get("worker")
        err = result.get("error")
        reply = result.get("text") or ""

        if err and not reply:
            print(paint(f"ARES ! {err}", C.RED))
            continue

        print(paint("ARES › ", C.GREEN, C.BOLD) + paint(reply, C.WHITE))
        print(paint(f"  [{worker} · {elapsed}s]", C.DIM))
        print()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="ARES Companion TUI (Jaeger-method client)")
    p.add_argument("--base", default=os.environ.get("ARES_BASE_URL", "http://127.0.0.1:8787"))
    p.add_argument("--worker", default=os.environ.get("ARES_WORKER", "hermes_local"))
    p.add_argument("--session", default=None, help="Reuse existing session id")
    p.add_argument("--timeout", type=float, default=180.0)
    p.add_argument("-q", "--query", default=None, help="Single-shot message (no interactive loop)")
    args = p.parse_args(argv)

    client = AresClient(
        base_url=args.base,
        worker=args.worker,
        session_id=args.session or "",
        timeout=args.timeout,
    )
    try:
        client.start()
    except AresError as exc:
        print(paint(f"boot failed: {exc}", C.RED), file=sys.stderr)
        return 1

    if args.query:
        result = client.turn(args.query)
        if result.get("error") and not result.get("text"):
            print(result["error"], file=sys.stderr)
            return 2
        print(result.get("text") or "")
        return 0

    return run_tui(client)


if __name__ == "__main__":
    raise SystemExit(main())
