#!/usr/bin/env python3
"""Talk to the live ARES Companion over the WebUI HTTP API.

Examples:
  ./scripts/talk_ares.py "Who are you?"
  ./scripts/talk_ares.py --session SID "Remember my favorite color is blue"
  ./scripts/talk_ares.py --chat   # multi-turn REPL
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from typing import Any


def req(base: str, method: str, path: str, body: dict | None = None, timeout: float = 120) -> Any:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        base.rstrip("/") + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data else {},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise SystemExit(f"HTTP {exc.code} {path}: {detail[:500]}") from exc


def wait_stream(base: str, stream_id: str, timeout: float = 120) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = req(base, "GET", f"/api/chat/stream/status?stream_id={stream_id}", timeout=10)
        if not st.get("active"):
            return
        time.sleep(1.5)
    raise SystemExit(f"stream {stream_id} still active after {timeout}s")


def ensure_session(base: str, session_id: str | None) -> str:
    if session_id:
        return session_id
    new = req(base, "POST", "/api/session/new", {})
    return str((new.get("session") or new).get("session_id") or "")


def turn(
    base: str,
    session_id: str,
    message: str,
    worker: str,
    timeout: float,
) -> str:
    start = req(
        base,
        "POST",
        "/api/chat/start",
        {
            "session_id": session_id,
            "message": message,
            "connection_id": worker,
        },
        timeout=timeout,
    )
    stream_id = str(start.get("stream_id") or "")
    if not stream_id:
        raise SystemExit(f"chat/start failed: {start}")
    wait_stream(base, stream_id, timeout=timeout)
    sess = req(base, "GET", f"/api/session?session_id={session_id}", timeout=30)
    s = sess.get("session") or sess
    msgs = s.get("messages") or []
    for m in reversed(msgs):
        if m.get("role") == "assistant":
            return str(m.get("content") or "").strip()
    return ""


def main() -> int:
    p = argparse.ArgumentParser(description="Talk to live ARES Companion")
    p.add_argument("message", nargs="?", help="Single message (omit with --chat)")
    p.add_argument("--base", default="http://127.0.0.1:8787")
    p.add_argument("--worker", default="hermes_local")
    p.add_argument("--session", default=None, help="Reuse session id")
    p.add_argument("--timeout", type=float, default=120)
    p.add_argument("--chat", action="store_true", help="Interactive multi-turn")
    args = p.parse_args()

    health = req(args.base, "GET", "/api/health", timeout=10)
    if health.get("status") != "ok":
        print(f"health not ok: {health}", file=sys.stderr)
        return 1
    if not health.get("si_enabled"):
        print("WARNING: si_enabled is false — Companion path may be bypassed", file=sys.stderr)

    sid = ensure_session(args.base, args.session)
    if not sid:
        print("could not create session", file=sys.stderr)
        return 1
    print(f"[session {sid} | worker {args.worker} | si={health.get('si_enabled')}]", file=sys.stderr)

    if args.chat or not args.message:
        print("Multi-turn chat. Empty line or Ctrl-D to exit.", file=sys.stderr)
        while True:
            try:
                line = input("You> ").strip()
            except (EOFError, KeyboardInterrupt):
                print(file=sys.stderr)
                break
            if not line:
                break
            reply = turn(args.base, sid, line, args.worker, args.timeout)
            print(f"ARES> {reply}\n")
        print(f"[session {sid}]", file=sys.stderr)
        return 0

    reply = turn(args.base, sid, args.message, args.worker, args.timeout)
    print(reply)
    print(f"[session {sid}]", file=sys.stderr)
    return 0 if reply else 2


if __name__ == "__main__":
    raise SystemExit(main())
