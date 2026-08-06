"""ARES Backend Adapters — SDK-based, streaming, no subprocesses.

Architecture:
  Every backend uses the provider's native Python SDK (or direct HTTP for
  Ollama) instead of spawning CLI subprocesses. This gives us:
  - True token-by-token streaming
  - Structured tool calls and error handling
  - No subprocess startup latency (200-500ms saved per turn)
  - Proper cancellation via asyncio/coroutines
  - Shared memory for state (no IPC overhead)

  Backends register themselves with BackendRegistry at module import time.
  The router only instantiates backends that are actually available.

  Fallback chain: if the primary backend is unavailable, the router tries
  fallbacks in order before giving up.
"""
from __future__ import annotations

import logging
import os
import threading
import time
from typing import Any, Dict, List

from api.providers.agentic_backend import AgenticBackend

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Dynamic Backend Registry
# ---------------------------------------------------------------------------

class BackendRegistry:
    """Self-registering backend registry.

    Backends call ``BackendRegistry.register(MyBackend)`` at module level.
    The router queries ``get_available()`` to find what's usable right now.
    """

    _backends: dict[str, type[AgenticBackend]] = {}

    @classmethod
    def register(cls, backend_cls: type[AgenticBackend]) -> None:
        """Register a backend class. Called at module import time."""
        name = getattr(backend_cls, "name", None)
        if not name:
            logger.warning("Backend %s has no 'name' attribute, skipping registration", backend_cls.__name__)
            return
        cls._backends[name] = backend_cls
        logger.debug("Registered backend: %s", name)

    @classmethod
    def get_available(cls) -> dict[str, AgenticBackend]:
        """Instantiate and return only backends that are currently available."""
        result: dict[str, AgenticBackend] = {}
        for name, cls_type in cls._backends.items():
            try:
                instance = cls_type()
                if instance.is_available():
                    result[name] = instance
            except Exception as exc:
                logger.debug("Backend %s probe failed: %s", name, exc)
        return result

    @classmethod
    def get_all(cls) -> dict[str, AgenticBackend]:
        """Instantiate all registered backends (for inventory/UI listing)."""
        return {name: cls_type() for name, cls_type in cls._backends.items()}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None


def _cfg_int(config: dict, key: str) -> int | None:
    val = config.get(key)
    return int(val) if isinstance(val, (int, float)) else None


def _credential_value(name: str) -> str | None:
    """Resolve a credential: thread-local env → os.environ."""
    try:
        from api.config import _thread_local_env_value
        return _thread_local_env_value(name).strip() or None
    except ImportError:
        return str(os.environ.get(name) or "").strip() or None


def _ollama_base_url() -> str:
    """Honour OLLAMA_HOST so a remote/non-default Ollama is reachable."""
    return os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")


# ---------------------------------------------------------------------------
# OpenAI SDK Backend (streaming, tool-capable)
# ---------------------------------------------------------------------------

class OpenAICloudBackend(AgenticBackend):
    """OpenAI API backend — uses the OpenAI Python SDK with streaming."""

    name = "openai_cloud"
    supports_tools = True
    supports_persona = False

    def is_available(self) -> bool:
        return bool(_credential_value("OPENAI_API_KEY"))

    def get_backend_name(self) -> str:
        return "OpenAI"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "OpenAI API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "OPENAI_API_KEY not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "OpenAI"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "OpenAI API key not configured.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or kwargs.get("model") or "gpt-4o"
        cancel_event = kwargs.get("cancel_event")
        publish = kwargs.get("publish")

        try:
            import openai
            client = openai.OpenAI(api_key=_credential_value("OPENAI_API_KEY"))

            if publish:
                # Streaming mode
                accumulated = ""
                stream = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": message}],
                    stream=True,
                )
                for chunk in stream:
                    if cancel_event and hasattr(cancel_event, "is_set") and cancel_event.is_set():
                        break
                    delta = chunk.choices[0].delta if chunk.choices else None
                    if delta and delta.content:
                        accumulated += delta.content
                        publish("token", {"text": delta.content})
                return {"text": accumulated, "error": None, "tool_activity": []}
            else:
                response = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": message}],
                )
                text = response.choices[0].message.content or ""
                return {"text": text, "error": None, "tool_activity": []}

        except Exception as exc:
            logger.exception("OpenAI cloud turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}


BackendRegistry.register(OpenAICloudBackend)


# ---------------------------------------------------------------------------
# xAI / Grok API Backend (OpenAI-compatible SDK, streaming)
# ---------------------------------------------------------------------------

class XAICloudBackend(AgenticBackend):
    """xAI/Grok API backend — OpenAI-compatible SDK with streaming."""

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
        return {"status": "error", "latency_ms": 0.0, "message": "XAI_API_KEY not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "xAI Grok"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "xAI API key not configured.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or kwargs.get("model") or "grok-3"
        cancel_event = kwargs.get("cancel_event")
        publish = kwargs.get("publish")

        try:
            import openai
            client = openai.OpenAI(
                api_key=_credential_value("XAI_API_KEY"),
                base_url="https://api.x.ai/v1",
            )

            if publish:
                accumulated = ""
                stream = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": message}],
                    stream=True,
                )
                for chunk in stream:
                    if cancel_event and hasattr(cancel_event, "is_set") and cancel_event.is_set():
                        break
                    delta = chunk.choices[0].delta if chunk.choices else None
                    if delta and delta.content:
                        accumulated += delta.content
                        publish("token", {"text": delta.content})
                return {"text": accumulated, "error": None, "tool_activity": []}
            else:
                response = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": message}],
                )
                text = response.choices[0].message.content or ""
                return {"text": text, "error": None, "tool_activity": []}

        except Exception as exc:
            logger.exception("xAI cloud turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}


BackendRegistry.register(XAICloudBackend)


# ---------------------------------------------------------------------------
# Anthropic / Claude API Backend (SDK, streaming)
# ---------------------------------------------------------------------------

class ClaudeCloudBackend(AgenticBackend):
    """Anthropic Claude API backend — direct SDK, streaming, no subprocess.

    Replaces the old ClaudeLocalBackend that spawned ``claude -p`` as a
    subprocess. Uses the anthropic Python SDK directly for streaming,
    structured errors, and proper cancellation.
    """

    name = "claude_cloud"
    supports_tools = True
    supports_persona = False

    def is_available(self) -> bool:
        return bool(_credential_value("ANTHROPIC_API_KEY"))

    def get_backend_name(self) -> str:
        return "Claude"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "Anthropic API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "ANTHROPIC_API_KEY not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "Claude"}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "Anthropic API key not configured.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or kwargs.get("model") or "claude-sonnet-4-20250514"
        cancel_event = kwargs.get("cancel_event")
        publish = kwargs.get("publish")

        try:
            import anthropic
            client = anthropic.Anthropic(api_key=_credential_value("ANTHROPIC_API_KEY"))

            if publish:
                accumulated = ""
                with client.messages.stream(
                    model=model,
                    max_tokens=4096,
                    messages=[{"role": "user", "content": message}],
                ) as stream:
                    for text_delta in stream.text_stream:
                        if cancel_event and hasattr(cancel_event, "is_set") and cancel_event.is_set():
                            stream.close()
                            break
                        if text_delta:
                            accumulated += text_delta
                            publish("token", {"text": text_delta})
                return {"text": accumulated, "error": None, "tool_activity": []}
            else:
                response = client.messages.create(
                    model=model,
                    max_tokens=4096,
                    messages=[{"role": "user", "content": message}],
                )
                text = response.content[0].text if response.content else ""
                return {"text": text, "error": None, "tool_activity": []}

        except Exception as exc:
            logger.exception("Claude cloud turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}


BackendRegistry.register(ClaudeCloudBackend)


# ---------------------------------------------------------------------------
# Gemini Cloud Backend (SDK, streaming) — re-exported from gemini_cloud.py
# ---------------------------------------------------------------------------

# Imported below to avoid circular dependency. The class is defined in
# gemini_cloud.py and registered there.
from .gemini_cloud import GeminiCloudBackend  # noqa: E402, F811


# ---------------------------------------------------------------------------
# Ollama Local Backend (HTTP, streaming) — already correct, keep as-is
# ---------------------------------------------------------------------------

class OllamaLocalBackend(AgenticBackend):
    """Ollama local model backend — direct HTTP, streaming.

    Already the best-implemented backend. Uses HTTP POST to Ollama's API
    with streaming support, proper timeouts, and cancellation.
    """

    name = "ollama_local"
    supports_tools = False
    supports_persona = False

    def is_available(self) -> bool:
        try:
            import requests
            r = requests.get(f"{_ollama_base_url()}/api/tags", timeout=2)
            return r.status_code == 200
        except Exception:
            return False

    def get_backend_name(self) -> str:
        return "Ollama"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "Ollama is running."}
        return {"status": "error", "latency_ms": 0.0, "message": f"Ollama not reachable at {_ollama_base_url()}."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "Ollama"}

    def inventory(self) -> Dict[str, Any] | None:
        """Installed Ollama models via /api/tags."""
        from model_discovery import list_ollama_local_models
        from catalog import finalize_inventory

        models = list_ollama_local_models()
        if not models:
            return None
        return finalize_inventory({"models": models})

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "Ollama not running.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or kwargs.get("model") or "llama3.2"
        cancel_event = kwargs.get("cancel_event")
        publish = kwargs.get("publish")

        try:
            import requests

            if publish:
                accumulated = ""
                with requests.post(
                    f"{_ollama_base_url()}/api/chat",
                    json={
                        "model": model,
                        "messages": [{"role": "user", "content": message}],
                        "stream": True,
                        "options": {"num_predict": 2048, "temperature": 0.7},
                    },
                    stream=True,
                    timeout=120,
                ) as r:
                    r.raise_for_status()
                    for line in r.iter_lines():
                        if cancel_event and hasattr(cancel_event, "is_set") and cancel_event.is_set():
                            break
                        if not line:
                            continue
                        import json as _json
                        try:
                            chunk = _json.loads(line)
                        except Exception:
                            continue
                        token = chunk.get("message", {}).get("content", "")
                        if token:
                            accumulated += token
                            publish("token", {"text": token})
                        if chunk.get("done"):
                            break
                return {"text": accumulated, "error": None, "tool_activity": []}
            else:
                r = requests.post(
                    f"{_ollama_base_url()}/api/chat",
                    json={
                        "model": model,
                        "messages": [{"role": "user", "content": message}],
                        "stream": False,
                        "options": {"num_predict": 2048, "temperature": 0.7},
                    },
                    timeout=120,
                )
                data = r.json()
                msg = data.get("message", {})
                return {"text": msg.get("content", ""), "error": None, "tool_activity": []}

        except Exception as exc:
            logger.exception("Ollama turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}

    def get_worker_target(self):
        """Return the Ollama direct-streaming worker target."""
        from .cli_backends_legacy import run_ollama_streaming
        return run_ollama_streaming, False, False


BackendRegistry.register(OllamaLocalBackend)


# ---------------------------------------------------------------------------
# App Automation Backends (AppleScript — no SDK alternative)
# ---------------------------------------------------------------------------

class AppAutomationBackend(AgenticBackend):
    """For apps that have no CLI or API but expose a UI.

    Uses AppleScript to push a prompt. No SDK alternative exists for
    driving GUI applications programmatically on macOS.
    """

    name = "app_automation"
    supports_tools = False
    supports_persona = False

    def __init__(self, app_name: str, command_sequence: list):
        self.app_name = app_name
        self.command_sequence = command_sequence

    def is_available(self) -> bool:
        import shutil
        import subprocess
        if shutil.which("osascript") is None:
            return False
        try:
            result = subprocess.run(
                ["/usr/bin/open", "-Ra", self.app_name],
                capture_output=True, text=True, timeout=3,
            )
            return result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def run_turn(self, message: str, session_id: str, **kwargs) -> dict:
        import subprocess

        from api.os_automation_consent import require_os_automation_consent

        if not require_os_automation_consent(
            session_id,
            f'Send input to "{self.app_name}" via AppleScript',
        ):
            return {"text": "", "error": "OS automation denied: user consent was not granted.", "tool_activity": []}

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
                capture_output=True, text=True, timeout=30,
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
    display_label = "Cursor (app)"

    def __init__(self):
        super().__init__("Cursor", ["type_message", "return"])


class OpenCodeAppBackend(AppAutomationBackend):
    name = "opencode_app"
    display_label = "OpenCode (app)"

    def __init__(self):
        super().__init__("OpenCode", ["type_message", "return"])


BackendRegistry.register(AntigravityGeminiBackend)
BackendRegistry.register(CursorAppBackend)
BackendRegistry.register(OpenCodeAppBackend)


# ---------------------------------------------------------------------------
# Jaeger AI Backend (local bridge + cloud gateway, auto-detected)
# ---------------------------------------------------------------------------

class JaegerAIBackend(AgenticBackend):
    """Jaeger AI backend — supports local (bridge) and cloud (gateway) modes.

    Auto-detects configuration from environment variables (no hardcoding):
    - ARES_JAEGER_HOME / JAEGER_HOME: Jaeger installation root
    - ARES_JAEGER_SOURCE_DIR: Development checkout location
    - ARES_JAEGER_INSTANCE / JAEGER_INSTANCE_NAME: Instance selection
    """

    name = "jaeger_local"
    display_label = "Jaeger AI (Local + Cloud)"
    supports_tools = True
    supports_persona = False

    def __init__(self):
        from integrations.workers.jaeger_worker import JaegerWorker
        self._worker = JaegerWorker()

    def is_available(self) -> bool:
        """Check if Jaeger AI is available (bridge or gateway mode)."""
        return self._worker.is_available()

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute a turn in Jaeger AI."""
        return self._worker.run_turn(message, session_id, **kwargs)

    def health(self) -> Dict[str, Any]:
        """Health check status."""
        return self._worker.health()

    def capabilities(self) -> Dict[str, Any]:
        """Available capabilities and models."""
        return self._worker.capabilities()

    def identity_projection(self) -> Dict[str, Any]:
        """Identity info for UI."""
        mode = self._worker.mode or "unknown"
        return {
            "name": self.name,
            "description": f"Jaeger AI ({mode} mode)",
            "avatar_state": "connected" if self._worker.mode else "disconnected",
        }


BackendRegistry.register(JaegerAIBackend)


# ---------------------------------------------------------------------------
# Legacy CLI backends — kept for backward compatibility but deprecated.
# New code should use the SDK-based backends above.
# ---------------------------------------------------------------------------

# Re-export the old names so existing code that imports them still works.
# These will be removed in a future cleanup pass.
from .cli_backends_legacy import (  # noqa: E402, F811
    ClaudeLocalBackend,
    CodexLocalBackend,
    GeminiLocalBackend,
    GrokLocalBackend,
    OpenCodeLocalBackend,
    CursorLocalBackend,
    PiLocalBackend,
    CliBackend,
    _minimal_host_environment,
    _credential_value,
    _ollama_base_url,
    run_ollama_streaming,
)

# The docstring at the top of cli_backends_legacy.py calls these classes
# "deprecated in favor of the SDK-based backends in cli_backends.py" — but
# this file only registers CLOUD-API variants (ClaudeCloudBackend,
# XAICloudBackend); there is no SDK-based replacement for LOCAL CLI dispatch
# (talking to the `claude`, `codex`, `grok` binaries a user already has
# installed and configured). Without registering these, BackendRegistry.
# get_available() — the source of truth DispatchService queries — never
# surfaces them, even though each class's is_available()/inventory() work
# correctly on their own (services/controller/tests/test_ares_backend_adapters.py
# already covers the per-class contract). Registering unblocks real dispatch
# to Claude Code, Codex, Grok, and the other local CLI agents.
BackendRegistry.register(ClaudeLocalBackend)
BackendRegistry.register(CodexLocalBackend)
BackendRegistry.register(GeminiLocalBackend)
BackendRegistry.register(GrokLocalBackend)
BackendRegistry.register(OpenCodeLocalBackend)
BackendRegistry.register(CursorLocalBackend)
BackendRegistry.register(PiLocalBackend)
