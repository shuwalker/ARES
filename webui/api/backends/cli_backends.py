"""Generic CLI-based backend adapter for ARES.

Paperclip pattern: spawn a CLI, capture output, stream to SSE.
Each adapter is just {name}_{deployment}. No roles, no opinions.
"""
from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional

from .base import AgenticBackend

logger = logging.getLogger(__name__)


class CliBackend(AgenticBackend):
    """Generic backend that spawns a CLI subprocess.

    Subclasses set:
      - name (e.g. 'claude_local', 'codex_local')
      - cli_name (e.g. 'claude', 'codex')
      - display_label (e.g. 'Claude Code', 'OpenAI Codex')
    """

    cli_name: str = ""
    display_label: str = ""
    supports_tools: bool = True
    supports_persona: bool = False

    # Cache for availability probe
    _available_cache: bool | None = None
    _available_ts: float = 0.0
    _cache_ttl: float = 10.0
    _version_cache: str | None = None

    def _cli_path(self) -> str:
        path = shutil.which(self.cli_name)
        if path:
            return path
        return ""

    def _probe(self) -> tuple[bool, str | None]:
        now = time.time()
        if self._available_cache is not None and (now - self._available_ts) < self._cache_ttl:
            return self._available_cache, self._version_cache

        cli = self._cli_path()
        if not cli:
            self._available_cache = False
            self._version_cache = None
            self._available_ts = now
            return False, None

        try:
            result = subprocess.run(
                [cli, "--version"],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0:
                version = (result.stdout.strip() or "").split("\n")[-1].strip()
                self._available_cache = True
                self._version_cache = version or "unknown"
                self._available_ts = now
                return True, self._version_cache
        except (subprocess.TimeoutExpired, OSError):
            pass

        self._available_cache = False
        self._version_cache = None
        self._available_ts = now
        return False, None

    def is_available(self) -> bool:
        available, _ = self._probe()
        return available

    def get_backend_name(self) -> str:
        return self.display_label or self.name

    def health(self) -> Dict[str, Any]:
        available, version = self._probe()
        if available:
            return {
                "status": "ok",
                "latency_ms": 0.0,
                "message": f"{self.display_label} {version or ''} is available.",
                "version": version,
            }
        return {
            "status": "error",
            "latency_ms": 0.0,
            "message": f"{self.display_label} CLI not found on $PATH.",
        }

    def identity_projection(self) -> Dict[str, Any]:
        return {
            "name": self.display_label,
            "description": f"{self.display_label} -- {self.name}",
            "avatar_state": "idle",
        }

    def capabilities(self) -> Dict[str, Any]:
        return {
            "chat": True,
            "tools": self.supports_tools,
            "persona": self.supports_persona,
        }

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 128000, "multimodal": True}

    def settings_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "title": "Model",
                    "description": f"Model name for {self.display_label}",
                },
            },
        }

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        _, version = self._probe()
        return {
            "available": available,
            "label": f"{self.display_label} {version or ''}".strip() if available else f"{self.display_label} (not found)",
            "version": version,
        }

    # Per-tool invocation pattern (Paperclip-style native CLI passthrough).
    # Subclasses can override these three attributes to match the exact upstream CLI contract.
    prompt_flag: str | None = None          # e.g. "-p" for claude/gemini
    prompt_position: str = "trailing"     # "trailing" or "positional"
    extra_args: list[str] | None = None   # extra fixed flags (e.g. ["exec"] for codex)
    needs_tty: bool = False                # true if the CLI refuses to run without a pty

    def _build_args(self, cli: str, message: str, model: str) -> list[str]:
        args: list[str] = [cli]
        if self.extra_args:
            args.extend(self.extra_args)
        if self.prompt_flag:
            args.extend([self.prompt_flag, message])
        else:
            args.append(message)
        if model:
            args.extend(["-m", model])
        return args

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        cli = self._cli_path()
        if not cli:
            return {"text": "", "error": f"{self.display_label} CLI not found.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or ""
        timeout_sec = _cfg_int(config, "timeout_sec") or 300

        args = self._build_args(cli, message, model)
        env = dict(os.environ)
        try:
            if self.needs_tty:
                import pty
                stdout_chunks: list[bytes] = []
                stderr_chunks: list[bytes] = []
                pid, fd = pty.fork()
                if pid == 0:
                    os.execvpe(args[0], args, env)
                else:
                    try:
                        import select
                        end = time.monotonic() + timeout_sec
                        while time.monotonic() < end:
                            ready, _, _ = select.select([fd], [], [], 1.0)
                            if ready:
                                try:
                                    chunk = os.read(fd, 4096)
                                    if not chunk:
                                        break
                                    stdout_chunks.append(chunk)
                                except OSError:
                                    break
                            else:
                                break
                        os.waitpid(pid, 0)
                    finally:
                        try:
                            os.close(fd)
                        except OSError:
                            pass
                stdout = b"".join(stdout_chunks).decode("utf-8", errors="replace")
                stderr = ""
                return_code = 0
            else:
                proc = subprocess.run(
                    args, capture_output=True, text=True,
                    timeout=timeout_sec, env=env,
                )
                stdout = proc.stdout or ""
                stderr = proc.stderr or ""
                return_code = proc.returncode

            error = None
            if return_code != 0:
                error_lines = [
                    line for line in stderr.strip().split("\n")
                    if re.search(r"error|exception|traceback|failed", line, re.IGNORECASE)
                ]
                if error_lines:
                    error = "\n".join(error_lines[:5])
                elif stderr.strip():
                    error = stderr.strip()[:500]
            return {"text": stdout.strip(), "error": error, "tool_activity": []}
        except subprocess.TimeoutExpired:
            return {"text": "", "error": f"{self.display_label} turn timed out after {timeout_sec}s.", "tool_activity": []}
        except Exception as exc:
            logger.exception(f"{self.display_label} turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}


# ---------------------------------------------------------------------------
# Concrete adapters
# ---------------------------------------------------------------------------

class ClaudeLocalBackend(CliBackend):
    name = "claude_local"
    cli_name = "claude"
    display_label = "Claude Code"
    supports_tools = True
    prompt_flag = "-p"

class CodexLocalBackend(CliBackend):
    name = "codex_local"
    cli_name = "codex"
    display_label = "OpenAI Codex"
    supports_tools = True
    extra_args = ["exec", "--skip-git-repo-check"]

class GeminiLocalBackend(CliBackend):
    name = "gemini_local"
    cli_name = "gemini"
    display_label = "Google Gemini"
    supports_tools = True
    prompt_flag = "-p"
    extra_args = ["--skip-trust"]

class GrokLocalBackend(CliBackend):
    name = "grok_local"
    cli_name = "grok"
    display_label = "xAI Grok"
    supports_tools = True
    needs_tty = True

class OpenCodeLocalBackend(CliBackend):
    name = "opencode_local"
    cli_name = "opencode"
    display_label = "OpenCode"
    supports_tools = True

class CursorLocalBackend(CliBackend):
    name = "cursor_local"
    cli_name = "cursor"
    display_label = "Cursor"
    supports_tools = True
    prompt_flag = "-p"

    def _cli_path(self) -> str:
        # Cursor has no stable CLI; only claim availability if a real `cursor` binary exists.
        return shutil.which(self.cli_name) or ""

class PiLocalBackend(CliBackend):
    name = "pi_local"
    cli_name = "pi"
    display_label = "Pi Coding Agent"
    supports_tools = True
    prompt_flag = "-p"

    def _build_args(self, cli: str, message: str, model: str) -> list[str]:
        args = [cli, "-p"]
        if model:
            args.extend(["--provider", "ollama", "--model", model])
        args.append(message)
        return args


# ---------------------------------------------------------------------------
# API-based backends (no CLI needed)
# ---------------------------------------------------------------------------

class OpenAICloudBackend(AgenticBackend):
    """OpenAI API backend -- uses the OpenAI Python SDK."""
    name = "openai_cloud"
    supports_tools = True
    supports_persona = False

    def is_available(self) -> bool:
        try:
            import openai
            return bool(os.environ.get("OPENAI_API_KEY"))
        except ImportError:
            return False

    def get_backend_name(self) -> str:
        return "OpenAI"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "OpenAI API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "OpenAI API key not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "OpenAI"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "OpenAI API key not configured.", "tool_activity": []}
        try:
            import openai
            client = openai.OpenAI()
            response = client.chat.completions.create(
                model=kwargs.get("model") or "gpt-4o",
                messages=[{"role": "user", "content": message}],
            )
            text = response.choices[0].message.content or ""
            return {"text": text, "error": None, "tool_activity": []}
        except Exception as exc:
            return {"text": "", "error": str(exc), "tool_activity": []}


class XAICloudBackend(AgenticBackend):
    """xAI/Grok API backend."""
    name = "xai_cloud"
    supports_tools = False
    supports_persona = False

    def is_available(self) -> bool:
        return bool(os.environ.get("XAI_API_KEY"))

    def get_backend_name(self) -> str:
        return "xAI Grok"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "xAI API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "xAI API key not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "xAI Grok"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "xAI API key not configured.", "tool_activity": []}
        try:
            import openai
            client = openai.OpenAI(
                api_key=os.environ["XAI_API_KEY"],
                base_url="https://api.x.ai/v1",
            )
            response = client.chat.completions.create(
                model=kwargs.get("model") or "grok-3",
                messages=[{"role": "user", "content": message}],
            )
            text = response.choices[0].message.content or ""
            return {"text": text, "error": None, "tool_activity": []}
        except Exception as exc:
            return {"text": "", "error": str(exc), "tool_activity": []}


class OllamaLocalBackend(AgenticBackend):
    """Ollama local model backend."""
    name = "ollama_local"
    supports_tools = False
    supports_persona = False

    def is_available(self) -> bool:
        try:
            import requests
            r = requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
            return r.status_code == 200
        except Exception:
            return False

    def get_backend_name(self) -> str:
        return "Ollama"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "Ollama is running."}
        return {"status": "error", "latency_ms": 0.0, "message": "Ollama not reachable on localhost:11434."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "Ollama"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "Ollama not running.", "tool_activity": []}
        try:
            import requests
            model = kwargs.get("model") or "llama3.2"
            r = requests.post(
                "http://127.0.0.1:11434/api/chat",
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": message}],
                    "stream": False,
                    "options": {
                        "num_predict": 120,
                        "temperature": 0.1,
                    },
                },
                timeout=120,
            )
            data = r.json()
            msg = data.get("message", {})
            return {"text": msg.get("content", ""), "error": None, "tool_activity": []}
        except Exception as exc:
            return {"text": "", "error": str(exc), "tool_activity": []}

    def get_worker_target(self):
        """Return the Ollama direct-streaming worker target."""
        return run_ollama_streaming, False, False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None

def _cfg_int(config: dict, key: str) -> int | None:
    val = config.get(key)
    return int(val) if isinstance(val, (int, float)) else None



def run_ollama_streaming(
    session_id: str,
    message: str,
    model: str,
    workspace: str,
    stream_id: str,
    attachments: list,
    *,
    model_provider: str | None = None,
    goal_related: bool = False,
) -> None:
    """Stream a chat turn directly from the local Ollama /api/generate endpoint.

    Matches the Ares worker contract used by chat_runtime._select_chat_worker_target.
    """
    import json as _json
    import queue
    import threading
    import time

    import requests

    from api.streaming import (
        CANCEL_FLAGS,
        STREAM_PARTIAL_TEXT,
        STREAMS,
        STREAMS_LOCK,
        register_active_run,
        unregister_stream_owner,
    )

    q = STREAMS.get(stream_id)
    if q is None:
        unregister_stream_owner(stream_id)
        return

    register_active_run(stream_id, session_id=session_id, started_at=time.time(), phase="ollama")
    cancel_event = CANCEL_FLAGS.get(stream_id)

    # Pick model: prefer the model name, else the installed model (qwen3.6:35b-mlx)
    model_name = model or "qwen3.6:35b-mlx"

    accumulated = ""
    event_seq = 0
    last_partial_time = time.time()

    def _put(event: str, data: dict):
        nonlocal event_seq
        event_seq += 1
        try:
            q.put(
                {
                    "schema_version": 1,
                    "event": event,
                    "data": data,
                    "event_id": f"{stream_id}:{event_seq}",
                    "seq": event_seq,
                    "stream_id": stream_id,
                    "session_id": session_id,
                    "terminal": event in {"stream_end", "error", "cancel"},
                },
                timeout=5,
            )
        except queue.Full:
            pass

    def _finish(text: str = "", error: str | None = None):
        if error:
            _put("error", {"error": error, "message": error})
        else:
            _put("stream_end", {"text": text})
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
        unregister_stream_owner(stream_id)

    try:
        with requests.post(
            "http://127.0.0.1:11434/api/generate",
            json={"model": model_name, "prompt": message, "stream": True, "options": {"temperature": 0.7}},
            stream=True,
            timeout=120,
        ) as r:
            r.raise_for_status()
            for line in r.iter_lines():
                if cancel_event and cancel_event.is_set():
                    _finish(error="Cancelled")
                    return
                if not line:
                    continue
                try:
                    chunk = _json.loads(line)
                except Exception:
                    continue
                token = chunk.get("response", "")
                if token:
                    accumulated += token
                    _put(STREAM_PARTIAL_TEXT, {"text": accumulated, "delta": token})
                    last_partial_time = time.time()
                if chunk.get("done"):
                    break
        _finish(accumulated)
    except Exception as exc:
        _finish(error=f"Ollama streaming error: {exc}")


class AppAutomationBackend:
    """For apps that have no CLI but expose a UI; uses AppleScript to push a prompt."""
    name = "app_automation"
    display_label = "App Automation"
    supports_tools = False

    def __init__(self, app_name: str, command_sequence: list):
        self.app_name = app_name
        self.command_sequence = command_sequence

    def is_available(self) -> bool:
        import shutil
        return shutil.which("osascript") is not None

    def run_turn(self, message: str, session_id: str, **kwargs) -> dict:
        import subprocess
        # Build AppleScript: activate app and type the prompt, then submit
        steps = [f'activate application "{self.app_name}"']
        for step in self.command_sequence:
            if step == "type_message":
                escaped = message.replace('"', '\"')
                steps.append(f'tell application "System Events" to keystroke "{escaped}"')
            elif step == "return":
                steps.append('tell application "System Events" to key code 36')
            elif step == "tab":
                steps.append('tell application "System Events" to key code 48')
        script = "\n".join(steps)
        try:
            r = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=30
            )
            return {"text": "", "error": r.stderr.strip() if r.returncode != 0 else None, "tool_activity": []}
        except Exception as exc:
            return {"text": "", "error": str(exc), "tool_activity": []}


class AntigravityGeminiBackend(AppAutomationBackend):
    name = "gemini_antigravity"
    display_label = "Gemini (Antigravity IDE)"

    def __init__(self):
        super().__init__("Antigravity IDE", ["type_message", "return"])


class CursorAppBackend(AppAutomationBackend):
    name = "cursor_app"
    display_label = "Cursor (App Automation)"

    def __init__(self):
        super().__init__("Cursor", ["type_message", "return"])


class OpenCodeAppBackend(AppAutomationBackend):
    name = "opencode_app"
    display_label = "OpenCode (App Automation)"

    def __init__(self):
        super().__init__("OpenCode", ["type_message", "return"])
