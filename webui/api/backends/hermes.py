"""Hermes Agent Backend Adapter for ARES.

Spawns ``hermes chat -q "..." -Q`` as a subprocess, streams output,
and returns structured results. This is pure ARES-side routing --
Hermes Agent itself is never modified.

Availability: True when the ``hermes`` CLI is on $PATH and responds
to ``hermes --version`` within a 5-second timeout.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from typing import Any, Dict, List

from .base import AgenticBackend

logger = logging.getLogger(__name__)

_HERMES_AVAILABLE_CACHE: bool | None = None
_HERMES_AVAILABLE_TS: float = 0.0
_HERMES_CACHE_TTL = 10.0
_HERMES_VERSION_CACHE: str | None = None

# Regex to extract session_id from Hermes quiet-mode output
_SESSION_ID_RE = re.compile(r"^session_id:\s*(\S+)", re.MULTILINE)
_SESSION_ID_LEGACY_RE = re.compile(r"session[_ ](?:id|saved)[:\s]+([a-zA-Z0-9_-]+)", re.IGNORECASE)


def _hermes_cli() -> str:
    """Return the path to the hermes CLI, or empty string if not found."""
    path = shutil.which("hermes")
    if path:
        return path
    # Check common install locations
    for candidate in (
        os.path.expanduser("~/.hermes/hermes-agent/run_agent.py"),
        "/usr/local/bin/hermes",
    ):
        if os.path.isfile(candidate):
            return candidate
    return ""


def _probe_hermes() -> tuple[bool, str | None]:
    """Check whether Hermes CLI is available and cache the version string."""
    global _HERMES_AVAILABLE_CACHE, _HERMES_VERSION_CACHE, _HERMES_AVAILABLE_TS

    now = time.time()
    if _HERMES_AVAILABLE_CACHE is not None and (now - _HERMES_AVAILABLE_TS) < _HERMES_CACHE_TTL:
        return _HERMES_AVAILABLE_CACHE, _HERMES_VERSION_CACHE

    cli = _hermes_cli()
    if not cli:
        _HERMES_AVAILABLE_CACHE = False
        _HERMES_VERSION_CACHE = None
        _HERMES_AVAILABLE_TS = now
        return False, None

    try:
        result = subprocess.run(
            [cli, "--version"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            version = (result.stdout.strip() or "").split("\n")[-1].strip()
            _HERMES_AVAILABLE_CACHE = True
            _HERMES_VERSION_CACHE = version or "unknown"
            _HERMES_AVAILABLE_TS = now
            return True, _HERMES_VERSION_CACHE
    except (subprocess.TimeoutExpired, OSError):
        pass

    _HERMES_AVAILABLE_CACHE = False
    _HERMES_VERSION_CACHE = None
    _HERMES_AVAILABLE_TS = now
    return False, None


def _clean_response(raw: str) -> str:
    """Strip Hermes noise lines (tool markers, session IDs, timestamps)."""
    lines = []
    for line in raw.split("\n"):
        stripped = line.strip()
        if not stripped:
            lines.append("")
            continue
        if stripped.startswith(("[tool]", "[hermes]", "[paperclip]")):
            continue
        if stripped.startswith("session_id:"):
            continue
        if re.match(r"^\[\d{4}-\d{2}-\d{2}T", stripped):
            continue
        if re.match(r"^\[done\]\s*┊", stripped):
            continue
        # Clean leading chat bubble
        cleaned = re.sub(r"^[\s]*┊\s*💬\s*", "", line).strip()
        cleaned = re.sub(r"^\[done\]\s*", "", cleaned).strip()
        if cleaned:
            lines.append(cleaned)
    return "\n".join(lines).strip()


class HermesBackend(AgenticBackend):
    """Hermes Agent adapter -- routes chat through the local Hermes CLI."""

    name = "hermes_local"
    supports_tools = True
    supports_persona = False

    def is_available(self) -> bool:
        available, _ = _probe_hermes()
        return available

    def get_backend_name(self) -> str:
        return "Hermes"

    def health(self) -> Dict[str, Any]:
        available, version = _probe_hermes()
        if available:
            return {
                "status": "ok",
                "latency_ms": 0.0,
                "message": f"Hermes Agent {version or ''} is available.",
                "version": version,
            }
        return {
            "status": "error",
            "latency_ms": 0.0,
            "message": "Hermes Agent CLI not found on $PATH.",
        }

    def identity_projection(self) -> Dict[str, Any]:
        return {
            "name": "Hermes",
            "description": "Hermes Agent -- local execution engine",
            "avatar_state": "idle",
        }

    def capabilities(self) -> Dict[str, Any]:
        return {
            "chat": True,
            "tools": self.supports_tools,
            "persona": self.supports_persona,
            "hybrid": self.supports_hybrid,
            "voice": False,
            "embodiment": False,
        }

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 128000, "multimodal": True}

    def tools(self) -> List[Dict[str, Any]]:
        # Hermes exposes its own tools -- we don't enumerate them here.
        # The adapter reports tool support so the UI shows the capability.
        return [{"name": "hermes_tools", "description": "Full Hermes Agent tool suite (terminal, file, web, browser, etc.)", "parameters": {"type": "object", "properties": {}}}]

    def settings_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "title": "Model",
                    "description": "Hermes model name (default: qwen3.6:35b-mlx)",
                },
                "provider": {
                    "type": "string",
                    "title": "Provider",
                    "description": "Inference provider (default: ollama-cloud for local Ollama)",
                },
                "toolsets": {
                    "type": "string",
                    "title": "Toolsets",
                    "description": "Comma-separated toolsets to enable (e.g. terminal,file,web)",
                },
            },
        }

    def get_worker_target(self) -> tuple:
        """Return the Hermes streaming worker target.

        Hermes turns run through a dedicated streaming worker that spawns
        ``hermes chat -q`` as a subprocess and pipes output to the SSE channel.
        """
        from api.backends.hermes_streaming import run_hermes_streaming

        return run_hermes_streaming, False, False
    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute one Hermes turn by spawning ``hermes chat -q``.

        Returns a dict with keys: text, error, tool_activity, session_id.
        """
        cli = _hermes_cli()
        if not cli:
            return {"text": "", "error": "Hermes CLI not found.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model = _cfg_str(config, "model") or "qwen3.6:35b-mlx"
        provider = _cfg_str(config, "provider") or "ollama-cloud"
        toolsets = _cfg_str(config, "toolsets") or ""
        max_turns = _cfg_int(config, "max_turns") or 150
        timeout_sec = _cfg_int(config, "timeout_sec") or 300

        # Build the hermes command
        args = [cli, "chat", "-q", message, "-Q", "--yolo", "--source", "webui"]

        if model:
            args.extend(["-m", model])
        if provider:
            args.extend(["--provider", provider])
        if toolsets:
            args.extend(["-t", toolsets])
        if max_turns:
            args.extend(["--max-turns", str(max_turns)])

        # Resume session if we have a previous session ID
        prev_session_id = kwargs.get("prev_session_id")
        if prev_session_id:
            args.extend(["--resume", prev_session_id])

        # Determine working directory
        cwd = _cfg_str(config, "cwd") or os.path.expanduser("~")

        # Build environment
        env = dict(os.environ)
        # Propagate Hermes home
        hermes_home = os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes"))
        env["HERMES_HOME"] = hermes_home

        try:
            proc = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                cwd=cwd,
                env=env,
            )

            stdout = proc.stdout or ""
            stderr = proc.stderr or ""

            # Parse session ID
            parsed_session_id = None
            session_match = _SESSION_ID_RE.search(stdout)
            if session_match:
                parsed_session_id = session_match.group(1)
            else:
                legacy_match = _SESSION_ID_LEGACY_RE.search(stdout + "\n" + stderr)
                if legacy_match:
                    parsed_session_id = legacy_match.group(1)

            # Extract clean response text
            if parsed_session_id:
                # Response is everything before the session_id line
                session_line_idx = stdout.rfind("\nsession_id:")
                if session_line_idx > 0:
                    text = _clean_response(stdout[:session_line_idx])
                else:
                    text = _clean_response(stdout)
            else:
                text = _clean_response(stdout)

            # Check for errors in stderr
            error = None
            if proc.returncode != 0:
                error_lines = [
                    line for line in stderr.strip().split("\n")
                    if re.search(r"error|exception|traceback|failed", line, re.IGNORECASE)
                    and not re.search(r"INFO|DEBUG|warn", line, re.IGNORECASE)
                ]
                if error_lines:
                    error = "\n".join(error_lines[:5])

            return {
                "text": text,
                "error": error,
                "tool_activity": [],
                "session_id": parsed_session_id,
            }

        except subprocess.TimeoutExpired:
            return {"text": "", "error": f"Hermes turn timed out after {timeout_sec}s.", "tool_activity": []}
        except Exception as exc:
            logger.exception("Hermes turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        _, version = _probe_hermes()
        return {
            "available": available,
            "label": f"Hermes Agent {version or ''}".strip() if available else "Hermes Agent (not found)",
            "version": version,
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
            },
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None


def _cfg_int(config: dict, key: str) -> int | None:
    val = config.get(key)
    return int(val) if isinstance(val, (int, float)) else None