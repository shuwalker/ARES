"""Legacy CLI-based backend adapters — kept for backward compatibility.

These backends spawn CLI subprocesses (``claude -p``, ``codex exec``, etc.).
They are DEPRECATED in favor of the SDK-based backends in cli_backends.py
which offer streaming, structured errors, and no subprocess overhead.

New code should import from cli_backends.py (OpenAICloudBackend, XAICloudBackend,
ClaudeCloudBackend, OllamaLocalBackend) instead of these.
"""
from __future__ import annotations

import importlib.util
import logging
import os
import re
import shutil
import subprocess
import time
from typing import Any, Dict

from .base import AgenticBackend

logger = logging.getLogger(__name__)


def _minimal_host_environment(credential_names: tuple[str, ...] = ()) -> dict[str, str]:
    safe_names = {
        "HOME", "LANG", "LC_ALL", "LOGNAME", "PATH", "SHELL",
        "SSH_AUTH_SOCK", "SSL_CERT_FILE", "TMPDIR", "USER",
        "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
    }
    env = {
        key: value
        for key, value in os.environ.items()
        if key in safe_names or key.startswith("LC_")
    }
    for key in credential_names:
        try:
            from api.config import _thread_local_env_value
            value = _thread_local_env_value(key)
        except ImportError:
            value = os.environ.get(key)
        if value:
            env[key] = value
    return env


def _credential_value(name: str) -> str | None:
    try:
        from api.config import _thread_local_env_value
        return _thread_local_env_value(name).strip() or None
    except ImportError:
        return str(os.environ.get(name) or "").strip() or None


def _ollama_base_url() -> str:
    return os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")


def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None


def _cfg_int(config: dict, key: str) -> int | None:
    val = config.get(key)
    return int(val) if isinstance(val, (int, float)) else None


class CliBackend(AgenticBackend):
    """DEPRECATED: Generic backend that spawns a CLI subprocess.

    Use the SDK-based backends in cli_backends.py instead.
    """
    cli_name: str = ""
    display_label: str = ""
    supports_tools: bool = True
    supports_persona: bool = False

    _available_cache: bool | None = None
    _available_ts: float = 0.0
    _cache_ttl: float = 10.0
    _version_cache: str | None = None

    prompt_flag: str | None = None
    prompt_position: str = "trailing"
    extra_args: list[str] | None = None
    needs_tty: bool = False
    credential_env_vars: tuple[str, ...] = ()

    def _cli_path(self) -> str:
        path = shutil.which(self.cli_name)
        return path or ""

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
            return {"status": "ok", "latency_ms": 0.0, "message": f"{self.display_label} {version or ''} is available.", "version": version}
        return {"status": "error", "latency_ms": 0.0, "message": f"{self.display_label} CLI not found on $PATH."}

    def _runtime_environment(self) -> dict[str, str]:
        return _minimal_host_environment(self.credential_env_vars)

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
        env = self._runtime_environment()
        try:
            if self.needs_tty:
                import pty
                stdout_chunks: list[bytes] = []
                import select
                master_fd, slave_fd = pty.openpty()
                try:
                    proc = subprocess.Popen(
                        args, stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
                        env=env, close_fds=True,
                    )
                except Exception:
                    os.close(master_fd)
                    raise
                finally:
                    os.close(slave_fd)
                try:
                    deadline = time.monotonic() + timeout_sec
                    while proc.poll() is None:
                        if time.monotonic() >= deadline:
                            proc.terminate()
                            try:
                                proc.wait(timeout=2)
                            except subprocess.TimeoutExpired:
                                proc.kill()
                                proc.wait(timeout=2)
                            return {"text": "", "error": f"{self.display_label} turn timed out after {timeout_sec}s.", "tool_activity": []}
                        ready, _, _ = select.select([master_fd], [], [], 0.2)
                        if ready:
                            try:
                                chunk = os.read(master_fd, 4096)
                            except OSError:
                                break
                            if chunk:
                                stdout_chunks.append(chunk)
                    while select.select([master_fd], [], [], 0)[0]:
                        try:
                            chunk = os.read(master_fd, 4096)
                        except OSError:
                            break
                        if not chunk:
                            break
                        stdout_chunks.append(chunk)
                finally:
                    os.close(master_fd)
                stdout = b"".join(stdout_chunks).decode("utf-8", errors="replace")
                stderr = ""
                return_code = proc.returncode if proc.returncode is not None else 1
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


class ClaudeLocalBackend(CliBackend):
    name = "claude_local"
    cli_name = "claude"
    display_label = "Claude Code"
    supports_tools = True
    prompt_flag = "-p"
    credential_env_vars = ("ANTHROPIC_API_KEY",)


class CodexLocalBackend(CliBackend):
    name = "codex_local"
    cli_name = "codex"
    display_label = "OpenAI Codex"
    supports_tools = True
    extra_args = ["exec", "--skip-git-repo-check"]
    credential_env_vars = ("OPENAI_API_KEY",)


class GeminiLocalBackend(CliBackend):
    name = "gemini_local"
    cli_name = "gemini"
    display_label = "Google Gemini"
    supports_tools = True
    prompt_flag = "-p"
    extra_args = ["--skip-trust"]
    credential_env_vars = ("GEMINI_API_KEY", "GOOGLE_API_KEY")


class GrokLocalBackend(CliBackend):
    name = "grok_local"
    cli_name = "grok"
    display_label = "xAI Grok"
    supports_tools = True
    needs_tty = True
    credential_env_vars = ("XAI_API_KEY",)


class OpenCodeLocalBackend(CliBackend):
    name = "opencode_local"
    cli_name = "opencode"
    display_label = "OpenCode"
    supports_tools = True
    credential_env_vars = ("ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY", "XAI_API_KEY")


class CursorLocalBackend(CliBackend):
    name = "cursor_local"
    cli_name = "cursor"
    display_label = "Cursor"
    supports_tools = True
    prompt_flag = "-p"

    def _cli_path(self) -> str:
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
    """Stream a chat turn directly from the local Ollama /api/generate endpoint."""
    import json as _json
    import threading
    import time
    import requests
    from api.streaming import (
        CANCEL_FLAGS, STREAM_LAST_EVENT_ID, STREAM_PARTIAL_TEXT,
        STREAMS, STREAMS_LOCK, register_active_run, unregister_active_run,
        unregister_stream_owner,
    )
    from api.run_journal import RunJournalWriter

    q = STREAMS.get(stream_id)
    if q is None:
        unregister_stream_owner(stream_id)
        return

    register_active_run(stream_id, session_id=session_id, started_at=time.time(), phase="ollama")
    cancel_event = CANCEL_FLAGS.get(stream_id) or threading.Event()
    with STREAMS_LOCK:
        CANCEL_FLAGS[stream_id] = cancel_event
        STREAM_PARTIAL_TEXT[stream_id] = ""
    try:
        run_journal = RunJournalWriter(session_id, stream_id)
    except Exception:
        run_journal = None

    model_name = model or "qwen3.6:35b-mlx"
    accumulated = ""

    def _put(event: str, data: dict):
        event_id = None
        if run_journal is not None:
            try:
                journaled = run_journal.append_sse_event(event, data)
                event_id = str((journaled or {}).get("event_id") or "") or None
            except Exception:
                pass
        if event_id:
            STREAM_LAST_EVENT_ID[stream_id] = event_id
        try:
            q.put_nowait((event, data, event_id) if event_id else (event, data))
        except Exception:
            pass

    def _finish(text: str = "", error: str | None = None, *, cancelled: bool = False):
        try:
            from api.models import get_session
            session = get_session(session_id)
            existing = list(getattr(session, "messages", None) or [])
            latest = existing[-1] if existing and isinstance(existing[-1], dict) else {}
            if message.strip() and not (
                latest.get("role") == "user"
                and " ".join(str(latest.get("content") or "").split())
                == " ".join(message.split())
            ):
                session.messages.append({"role": "user", "content": message, "timestamp": int(time.time())})
            if not error and not cancelled:
                if text.strip():
                    session.messages.append({"role": "assistant", "content": text.strip(), "timestamp": int(time.time())})
            if getattr(session, "active_stream_id", None) == stream_id:
                session.active_stream_id = None
                session.pending_user_message = None
                session.pending_attachments = []
                session.pending_started_at = None
                session.pending_user_source = None
            session.save()
        except Exception:
            logger.exception("Ollama worker failed to finalize session %s", session_id)
        if cancelled:
            _put("cancel", {"message": "Cancelled by user"})
        elif error:
            _put("error", {"error": error, "message": error})
        else:
            _put("stream_end", {"text": text})
        try:
            q.put_nowait(("done", {"session_id": session_id, "stream_id": stream_id}))
        except Exception:
            pass
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
            CANCEL_FLAGS.pop(stream_id, None)
            STREAM_PARTIAL_TEXT.pop(stream_id, None)
            STREAM_LAST_EVENT_ID.pop(stream_id, None)
        unregister_active_run(stream_id)
        unregister_stream_owner(stream_id)
        if run_journal is not None:
            try:
                run_journal.close()
            except Exception:
                pass

    try:
        with requests.post(
            f"{_ollama_base_url()}/api/generate",
            json={"model": model_name, "prompt": message, "stream": True, "options": {"temperature": 0.7, "num_predict": 2048}},
            stream=True, timeout=120,
        ) as r:
            r.raise_for_status()
            for line in r.iter_lines():
                if cancel_event and cancel_event.is_set():
                    _finish(cancelled=True)
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
                    STREAM_PARTIAL_TEXT[stream_id] = accumulated
                    _put("token", {"text": token})
                if chunk.get("done"):
                    break
        _finish(accumulated)
    except Exception:
        logger.exception("Ollama streaming request failed")
        _finish(error="Ollama request failed.")
