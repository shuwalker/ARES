#!/usr/bin/env python3
"""Standalone JROS gateway launcher — serve a JROS checkout over HTTP for ARES.

ARES's JROS backend talks to a JROS gateway server (see
``webui/api/jros_gateway_chat.py``). The gateway properly lives in the JROS
repo as ``jaeger gateway`` (``jaeger_os/interfaces/http_gateway.py``), but
that change is pending upstream — so this single file is the drop-in twin
for JROS installs that don't have it yet. Copy it next to (or point it at)
any JROS checkout and run it on the machine where JROS lives:

    python3 jros_gateway.py --jros-dir /path/to/JROS               # localhost:8643
    python3 jros_gateway.py --jros-dir /path/to/JROS --host 0.0.0.0  # serve the LAN

Then, on the machine running ARES (skip when it's the same machine):

    export ARES_JROS_GATEWAY_URL=http://<jros-host>:8643

If the JROS checkout already ships ``jaeger_os/interfaces/http_gateway.py``
(the upstreamed version), this launcher delegates to it, so upstream fixes
win automatically. Otherwise the bundled implementation below runs — it is
a verbatim vendored copy of the module submitted to the JROS repo.

Endpoints: GET /v1/health, POST /v1/chat/completions (OpenAI-compatible,
``stream`` supported), POST /v1/reset. Optional bearer auth via
``JAEGER_GATEWAY_KEY``. No dependencies beyond the JROS checkout itself.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8643
_BOOT_WAIT_S = 600.0
_AUTH_KEY_ENV = "JAEGER_GATEWAY_KEY"


def _resolve_jros_dir(cli_value: str | None) -> Path:
    raw = (cli_value or os.environ.get("ARES_JROS_DIR", "")).strip()
    if raw:
        root = Path(raw).expanduser().resolve()
    else:
        # Also allow running from inside a JROS checkout with no flag at all.
        root = Path.cwd()
    if not (root / "jaeger_os").is_dir():
        raise SystemExit(
            f"error: {root} does not contain jaeger_os/ — pass --jros-dir "
            "/path/to/JROS (or set ARES_JROS_DIR) pointing at your JROS checkout."
        )
    return root


# ── vendored from JROS jaeger_os/interfaces/http_gateway.py ─────────────


class GatewayState:
    """Shared agent state across request threads and the boot thread.

    Mirrors the JROS bridge's fast-ready split: health works from the first
    request; chat blocks on ``booted`` until the model is up (or the boot
    has failed, which chat then reports instead of hanging)."""

    def __init__(self, instance: str | None = None) -> None:
        self.instance = instance
        self.boot: Any = None
        self.client: Any = None
        self.boot_error: str | None = None
        self.booted = threading.Event()
        self.boot_started = False
        self.boot_lock = threading.Lock()
        self.turn_lock = threading.Lock()
        self.started_at = time.time()


def _boot_worker(state: GatewayState) -> None:
    """Background boot — never raises; failures land in ``boot_error``."""
    try:
        from jaeger_os.core.instance.instance import (
            InstanceLayout, default_instance_name, resolve_instance_dir)

        instance = state.instance or default_instance_name()
        state.instance = instance
        # FIRST-RUN GUARD: with no instance on disk, ``boot_for_tui`` fires
        # the INTERACTIVE CLI wizard, whose input() would hang a headless
        # server. Report instead.
        layout = InstanceLayout(resolve_instance_dir(instance))
        if not layout.exists():
            state.boot_error = (
                f"no instance named {instance!r} exists yet — run "
                "`jaeger setup` on this machine first")
            return
        from jaeger_os.main import boot_for_tui
        with contextlib.redirect_stdout(sys.stderr):
            boot = boot_for_tui(instance_name=instance, with_memory=True,
                                warmup=False, prewarm_model=False)
    except Exception as exc:  # noqa: BLE001 — reported via health/chat, never raised
        state.boot_error = str(exc)
    else:
        state.boot = boot
        state.client = boot.client
        state.boot_error = None
    finally:
        state.booted.set()


def start_boot(state: GatewayState) -> None:
    """Kick off the background boot at most once per cycle.

    A boot in flight or already successful is left alone; a FAILED boot
    re-arms, so the next chat request retries after the operator fixes
    whatever broke (e.g. closed the TUI that held the instance lock)."""
    with state.boot_lock:
        if state.boot_started:
            in_flight = not state.booted.is_set()
            succeeded = state.client is not None
            if in_flight or succeeded or state.boot_error is None:
                return
        state.boot_started = True
        state.booted.clear()
        state.boot_error = None
        threading.Thread(target=_boot_worker, args=(state,),
                         name="gateway-boot", daemon=True).start()


def reset_boot(state: GatewayState) -> None:
    """Drop the cached boot (releasing the instance lock + extensions) and
    re-boot in the background so on-disk config changes take effect."""
    with state.boot_lock:
        state.booted.wait(timeout=_BOOT_WAIT_S)  # never tear down mid-boot
        boot, state.boot, state.client = state.boot, None, None
        state.boot_started = False
    cleanup = getattr(boot, "cleanup", None) if boot is not None else None
    if callable(cleanup):
        try:
            cleanup()
        except Exception:  # noqa: BLE001 — best-effort teardown
            pass
    start_boot(state)


def _model_info(state: GatewayState) -> dict[str, Any]:
    """Best-effort model/provider labels for health — a miss is cosmetic."""
    info: dict[str, Any] = {"model": None, "provider": None, "character": None}
    boot = state.boot
    if boot is None:
        return info
    try:
        from jaeger_os.interfaces.bridge import _active_character, _model_name
        info["model"] = _model_name(boot)
        name, _icon = _active_character(boot)
        info["character"] = name
    except Exception:  # noqa: BLE001
        pass
    try:
        from jaeger_os.core.instance.schemas import Config, load_yaml
        cfg = load_yaml(boot.layout.config_path, Config)
        ext = getattr(cfg, "external_model", None)
        if ext is not None and getattr(ext, "enabled", False):
            info["provider"] = getattr(ext, "provider", None) or None
            info["model"] = getattr(ext, "model", None) or info["model"]
        else:
            info["provider"] = "local"
    except Exception:  # noqa: BLE001
        pass
    return info


def handle_health(state: GatewayState) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "ok": True,
        "backend": "jros",
        "instance": state.instance,
        "booted": state.booted.is_set() and state.client is not None,
        "boot_error": state.boot_error,
        "uptime_s": round(time.time() - state.started_at, 1),
        "timestamp": time.time(),
    }
    payload.update(_model_info(state))
    return payload


def _turn_text_and_session(payload: dict[str, Any]) -> tuple[str, str, str | None]:
    """Extract (turn_text, session_key, error) from an OpenAI-style body.

    The last user message is the turn — JROS keeps its own per-session
    history, so earlier messages in the array are the CLIENT's transcript,
    not instructions to replay."""
    messages = payload.get("messages")
    if not isinstance(messages, list) or not messages:
        return "", "", "body must include a non-empty 'messages' array"
    text = ""
    for msg in reversed(messages):
        if not isinstance(msg, dict) or msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            text = content.strip()
        elif isinstance(content, list):  # multimodal parts — keep the text ones
            text = "\n".join(
                str(part.get("text") or "").strip()
                for part in content
                if isinstance(part, dict) and part.get("type") == "text"
            ).strip()
        break
    if not text:
        return "", "", "no user message text found in 'messages'"
    session = str(payload.get("user") or "").strip() or "http-gateway"
    return text, session, None


def run_turn(state: GatewayState, text: str, session_key: str) -> dict[str, Any]:
    """Run one agent turn, booting first if needed. Returns the
    ``run_for_voice`` result dict, or ``{"error": …}`` when the agent
    can't run at all."""
    start_boot(state)
    if not state.booted.wait(timeout=_BOOT_WAIT_S):
        return {"text": "", "error": "agent boot timed out", "tool_activity": []}
    if state.client is None:
        return {"text": "", "error": state.boot_error or "agent failed to boot",
                "tool_activity": []}
    from jaeger_os.main import run_for_voice
    with state.turn_lock:
        with contextlib.redirect_stdout(sys.stderr):
            return run_for_voice(state.client, text, session_key=session_key)


def _completion_id() -> str:
    return f"jroscmpl-{int(time.time() * 1000)}"


def _usage_block(result: dict[str, Any]) -> dict[str, int]:
    # JROS doesn't meter tokens at this layer; report a word-count floor so
    # clients that display usage have something monotonic, never zero-div.
    text = str(result.get("text") or "")
    return {"prompt_tokens": 0,
            "completion_tokens": max(1, len(text.split())) if text else 0,
            "total_tokens": max(1, len(text.split())) if text else 0}


def completion_response(result: dict[str, Any], model: str) -> dict[str, Any]:
    """Non-streaming OpenAI-style completion object for a finished turn."""
    return {
        "id": _completion_id(),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{
            "index": 0,
            "message": {"role": "assistant",
                        "content": str(result.get("text") or "")},
            "finish_reason": "stop",
        }],
        "usage": _usage_block(result),
        "jros": {
            "tool_activity": [str(t) for t in result.get("tool_activity") or []],
            "elapsed_s": result.get("elapsed_s"),
        },
    }


def sse_frames(result: dict[str, Any], model: str) -> list[str]:
    """SSE frames for a finished turn, in the dialect ARES's gateway client
    already parses for Ares: ``ares.tool.progress`` events for tool
    activity, then one OpenAI-style content delta, then ``[DONE]``."""
    frames: list[str] = []
    error = str(result.get("error") or "").strip()
    if error:
        frames.append("event: jros.error\n"
                      f"data: {json.dumps({'message': error})}\n\n")
        frames.append("data: [DONE]\n\n")
        return frames
    for activity in result.get("tool_activity") or []:
        line = str(activity).strip()
        if not line:
            continue
        payload = {"event": "tool.completed", "tool": "jros",
                   "status": "completed", "label": line}
        frames.append("event: ares.tool.progress\n"
                      f"data: {json.dumps(payload, ensure_ascii=False)}\n\n")
    chunk = {
        "id": _completion_id(),
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{
            "index": 0,
            "delta": {"role": "assistant",
                      "content": str(result.get("text") or "")},
            "finish_reason": "stop",
        }],
        "usage": _usage_block(result),
    }
    frames.append(f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n")
    frames.append("data: [DONE]\n\n")
    return frames


class _GatewayServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr: tuple[str, int], state: GatewayState) -> None:
        super().__init__(addr, _Handler)
        self.state = state


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server: _GatewayServer

    # -- plumbing ---------------------------------------------------------
    def log_message(self, fmt: str, *args: Any) -> None:  # noqa: A003
        sys.stderr.write(f"[gateway] {self.address_string()} {fmt % args}\n")

    def _send_json(self, code: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, code: int, message: str, err_type: str) -> None:
        self._send_json(code, {"error": {"message": message, "type": err_type}})

    def _authorized(self) -> bool:
        key = os.environ.get(_AUTH_KEY_ENV, "").strip()
        if not key:
            return True
        supplied = str(self.headers.get("Authorization") or "").strip()
        return supplied == f"Bearer {key}"

    def _read_body(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length > 0 else b""
            payload = json.loads(raw.decode("utf-8")) if raw else {}
            return payload if isinstance(payload, dict) else None
        except Exception:  # noqa: BLE001 — malformed body → 400 at the caller
            return None

    # -- routes -----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802 — http.server contract
        if not self._authorized():
            return self._send_error_json(401, "missing or bad bearer key",
                                         "auth_error")
        if self.path.rstrip("/") == "/v1/health":
            return self._send_json(200, handle_health(self.server.state))
        return self._send_error_json(404, f"unknown path: {self.path}",
                                     "not_found")

    def do_POST(self) -> None:  # noqa: N802 — http.server contract
        if not self._authorized():
            return self._send_error_json(401, "missing or bad bearer key",
                                         "auth_error")
        path = self.path.rstrip("/")
        if path == "/v1/reset":
            reset_boot(self.server.state)
            return self._send_json(200, {"ok": True, "rebooting": True})
        if path != "/v1/chat/completions":
            return self._send_error_json(404, f"unknown path: {self.path}",
                                         "not_found")
        payload = self._read_body()
        if payload is None:
            return self._send_error_json(400, "body must be a JSON object",
                                         "invalid_request")
        text, session, err = _turn_text_and_session(payload)
        if err:
            return self._send_error_json(400, err, "invalid_request")
        model = str(payload.get("model") or "jros")
        if payload.get("stream"):
            return self._stream_turn(text, session, model)
        result = run_turn(self.server.state, text, session)
        error = str(result.get("error") or "").strip()
        if error and not str(result.get("text") or "").strip():
            return self._send_error_json(502, error, "jros_turn_error")
        return self._send_json(200, completion_response(result, model))

    def _stream_turn(self, text: str, session: str, model: str) -> None:
        """SSE reply: a status frame flushes BEFORE the turn runs, so the
        client sees the connection is live during a long turn; the content
        arrives as one delta when the turn finishes (JROS has no token
        stream at this layer)."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            status = {"status": "running",
                      "booted": self.server.state.booted.is_set()}
            self.wfile.write(("event: jros.status\n"
                              f"data: {json.dumps(status)}\n\n").encode("utf-8"))
            self.wfile.flush()
            result = run_turn(self.server.state, text, session)
            for frame in sse_frames(result, model):
                self.wfile.write(frame.encode("utf-8"))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass  # client hung up mid-turn; the turn already ran its course


# ── launcher ─────────────────────────────────────────────────────────────


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Standalone JROS HTTP gateway for ARES — serve a JROS "
                    "checkout over the network")
    p.add_argument("--jros-dir", default=None,
                   help="path to the JROS checkout (the directory containing "
                        "jaeger_os/); defaults to $ARES_JROS_DIR, then the "
                        "current directory")
    p.add_argument("--host", default=DEFAULT_HOST,
                   help=f"bind address (default {DEFAULT_HOST}; use 0.0.0.0 "
                        "to serve the LAN)")
    p.add_argument("--port", type=int, default=DEFAULT_PORT,
                   help=f"port (default {DEFAULT_PORT})")
    p.add_argument("--instance", default=None,
                   help="instance name (default: the active instance)")
    args = p.parse_args(argv)

    root = _resolve_jros_dir(args.jros_dir)
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

    # Prefer the native `jaeger gateway` when the checkout ships it — the
    # upstreamed module is the source of truth and its fixes win.
    try:
        from jaeger_os.interfaces import http_gateway as native
    except ImportError:
        native = None
    if native is not None:
        native_args = ["--host", args.host, "--port", str(args.port)]
        if args.instance:
            native_args += ["--instance", args.instance]
        print(f"[gateway] using native jaeger gateway from {root}",
              file=sys.stderr, flush=True)
        return native.main(native_args)

    state = GatewayState(instance=args.instance)
    start_boot(state)
    server = _GatewayServer((args.host, args.port), state)
    key_note = "bearer key required" if os.environ.get(_AUTH_KEY_ENV, "").strip() \
        else f"no auth (set {_AUTH_KEY_ENV} to require a bearer key)"
    print(f"[gateway] serving JROS at {root}", file=sys.stderr, flush=True)
    print(f"[gateway] listening on http://{args.host}:{args.port}  ({key_note})",
          file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        boot = state.boot
        cleanup = getattr(boot, "cleanup", None) if boot is not None else None
        if callable(cleanup):
            try:
                cleanup()
            except Exception:  # noqa: BLE001 — best-effort teardown
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
