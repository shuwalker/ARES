"""Generic CLI-based backend adapter for ARES.

Paperclip pattern: spawn a CLI, capture output, stream to SSE.
Each adapter is just {name}_{deployment}. No roles, no opinions.
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
    credential_env_vars: tuple[str, ...] = ()

    def _runtime_environment(self) -> dict[str, str]:
        """Give a CLI only host context and credentials intended for that adapter."""
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
                        args,
                        stdin=slave_fd,
                        stdout=slave_fd,
                        stderr=slave_fd,
                        env=env,
                        close_fds=True,
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
                            return {
                                "text": "",
                                "error": f"{self.display_label} turn timed out after {timeout_sec}s.",
                                "tool_activity": [],
                            }
                        ready, _, _ = select.select([master_fd], [], [], 0.2)
                        if ready:
                            try:
                                chunk = os.read(master_fd, 4096)
                            except OSError:
                                break
                            if chunk:
                                stdout_chunks.append(chunk)
                    # Drain any bytes written immediately before process exit.
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


# ---------------------------------------------------------------------------
# Concrete adapters
# ---------------------------------------------------------------------------

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
    credential_env_vars = (
        "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
        "OPENAI_API_KEY", "OPENROUTER_API_KEY", "XAI_API_KEY",
    )

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
        return importlib.util.find_spec("openai") is not None and bool(
            _credential_value("OPENAI_API_KEY")
        )

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
            client = openai.OpenAI(api_key=_credential_value("OPENAI_API_KEY"))
            response = client.chat.completions.create(
                model=kwargs.get("model") or "gpt-4o",
                messages=[{"role": "user", "content": message}],
            )
            text = response.choices[0].message.content or ""
            return {"text": text, "error": None, "tool_activity": []}
        except Exception:
            logger.exception("OpenAI cloud turn failed")
            return {"text": "", "error": "OpenAI request failed.", "tool_activity": []}


class XAICloudBackend(AgenticBackend):
    """xAI/Grok API backend."""
    name = "xai_cloud"
    supports_tools = False
    supports_persona = False

    def is_available(self) -> bool:
        return bool(_credential_value("XAI_API_KEY"))

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
                api_key=_credential_value("XAI_API_KEY"),
                base_url="https://api.x.ai/v1",
            )
            response = client.chat.completions.create(
                model=kwargs.get("model") or "grok-3",
                messages=[{"role": "user", "content": message}],
            )
            text = response.choices[0].message.content or ""
            return {"text": text, "error": None, "tool_activity": []}
        except Exception:
            logger.exception("xAI cloud turn failed")
            return {"text": "", "error": "xAI request failed.", "tool_activity": []}


class GeminiCloudBackend(AgenticBackend):
    """Google Gemini API backend."""
    name = "gemini_cloud"
    supports_tools = True
    supports_persona = True

    def is_available(self) -> bool:
        return bool(_credential_value("GEMINI_API_KEY") or _credential_value("GOOGLE_API_KEY"))

    def get_backend_name(self) -> str:
        return "Google Gemini Cloud"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "Gemini API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "GEMINI_API_KEY not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "Google Gemini"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "GEMINI_API_KEY not configured.", "tool_activity": []}
        try:
            import google.generativeai as genai
            genai.configure(api_key=_credential_value("GEMINI_API_KEY") or _credential_value("GOOGLE_API_KEY"))
            model_name = kwargs.get("model") or "gemini-2.5-pro"
            model = genai.GenerativeModel(model_name)
            response = model.generate_content(message)
            return {"text": response.text, "error": None, "tool_activity": []}
        except Exception:
            logger.exception("Gemini cloud turn failed")
            return {"text": "", "error": "Gemini request failed.", "tool_activity": []}


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

    Matches the ARES stream contract used by chat_runtime._select_chat_worker_target.
    """
    import json as _json
    import threading
    import time

    import requests

    from api.streaming import (
        CANCEL_FLAGS,
        STREAM_LAST_EVENT_ID,
        STREAM_PARTIAL_TEXT,
        STREAMS,
        STREAMS_LOCK,
        register_active_run,
        unregister_active_run,
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
        logger.debug("Failed to initialize Ollama run journal for %s", stream_id, exc_info=True)

    # Pick model: prefer the model name, else the installed model (qwen3.6:35b-mlx)
    model_name = model or "qwen3.6:35b-mlx"

    accumulated = ""
    def _put(event: str, data: dict):
        event_id = None
        if run_journal is not None:
            try:
                journaled = run_journal.append_sse_event(event, data)
                event_id = str((journaled or {}).get("event_id") or "") or None
            except Exception:
                logger.debug("Failed to journal Ollama event %s", event, exc_info=True)
        if event_id:
            STREAM_LAST_EVENT_ID[stream_id] = event_id
        try:
            item = (event, data, event_id) if hasattr(q, "subscribe_with_snapshot") else (event, data)
            q.put_nowait(item)
        except Exception:
            logger.debug("Failed to publish Ollama event %s", event, exc_info=True)

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
                session.messages.append({
                    "role": "user",
                    "content": message,
                    "timestamp": int(time.time()),
                })
            if not error and not cancelled:
                if text.strip():
                    session.messages.append({
                        "role": "assistant",
                        "content": text.strip(),
                        "timestamp": int(time.time()),
                    })
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
            logger.debug("Failed to publish Ollama completion marker", exc_info=True)
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
                logger.debug("Failed to close Ollama run journal", exc_info=True)

    try:
        with requests.post(
            "http://127.0.0.1:11434/api/generate",
            json={
                "model": model_name,
                "prompt": message,
                "stream": True,
                # Bound local generations so a malformed/reasoning-heavy model
                # cannot hold the session forever. Future UI controls may lower
                # this value, but the runtime keeps a defensive ceiling.
                "options": {"temperature": 0.7, "num_predict": 2048},
            },
            stream=True,
            timeout=120,
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


class AppAutomationBackend(AgenticBackend):
    """For apps that have no CLI but expose a UI; uses AppleScript to push a prompt."""
    name = "app_automation"
    display_label = "App Automation"
    supports_tools = False

    def __init__(self, app_name: str, command_sequence: list):
        self.app_name = app_name
        self.command_sequence = command_sequence

    def is_available(self) -> bool:
        import shutil
        if shutil.which("osascript") is None:
            return False
        try:
            result = subprocess.run(
                ["/usr/bin/open", "-Ra", self.app_name],
                capture_output=True,
                text=True,
                timeout=3,
                env=_minimal_host_environment(),
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def run_turn(self, message: str, session_id: str, **kwargs) -> dict:
        import subprocess

        # System-category OS automation requires explicit user consent. Deny by
        # default: if the user does not approve (timeout, denial, or no approval
        # channel), the osascript is never executed.
        from api.os_automation_consent import require_os_automation_consent

        if not require_os_automation_consent(
            session_id,
            f'Send input to "{self.app_name}" via AppleScript',
        ):
            return {
                "text": "",
                "error": "OS automation denied: user consent was not granted.",
                "tool_activity": [],
            }

        # Build AppleScript and pass it over stdin so prompts do not appear in
        # the osascript process arguments. Escape the string literal to prevent
        # prompt content from injecting AppleScript statements.
        escaped_message = (
            message.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\r", "\\r")
            .replace("\n", "\\n")
        )
        steps = [f'activate application "{self.app_name}"']
        for step in self.command_sequence:
            if step == "type_message":
                steps.append(f'tell application "System Events" to keystroke "{escaped_message}"')
            elif step == "return":
                steps.append('tell application "System Events" to key code 36')
            elif step == "tab":
                steps.append('tell application "System Events" to key code 48')
        script = "\n".join(steps)
        try:
            r = subprocess.run(
                ["osascript"],
                input=script,
                capture_output=True,
                text=True,
                timeout=30,
                env=_minimal_host_environment(),
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
