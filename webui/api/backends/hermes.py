"""Hermes Agent Backend Adapter for ARES.

Spawns ``hermes chat -q "..." -Q`` as a subprocess, streams output,
and returns structured results. This is pure ARES-side routing --
Hermes Agent itself is never modified.

Availability: True when the ``hermes`` CLI is on $PATH and responds
to ``hermes --version`` within a 5-second timeout.
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import time
from typing import Any, Dict, List

from .base import AgenticBackend

logger = logging.getLogger(__name__)

_HERMES_AVAILABLE_CACHE: bool | None = None
_HERMES_AVAILABLE_TS: float = 0.0
_HERMES_CACHE_TTL = 10.0
_HERMES_VERSION_CACHE: str | None = None


def _available_message(version: str | None) -> str:
    label = str(version or "Hermes Agent").strip()
    if not label.lower().startswith("hermes agent"):
        label = f"Hermes Agent {label}"
    return f"{label} is available."

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


def resolve_hermes_defaults() -> tuple[str, str]:
    """Return (model, provider) from Hermes config, with safe fallbacks.

    Prefer the operator's ``~/.hermes/config.yaml`` (paperclip detect-model style)
    so ARES matches CLI defaults instead of stale hardcodes.
    """
    try:
        from api.backends.model_discovery import detect_hermes_model_config

        cfg = detect_hermes_model_config()
        model = str(cfg.get("model") or "").strip()
        provider = str(cfg.get("provider") or "").strip()
    except Exception:
        logger.debug("Could not read Hermes config defaults", exc_info=True)
        model, provider = "", ""
    if not model:
        model = "deepseek-v4-flash"
    if not provider:
        provider = "ollama-cloud"
    return model, provider


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
            lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
            version = next(
                (line for line in lines if line.lower().startswith("hermes agent")),
                lines[0] if lines else "unknown",
            )
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
                "message": _available_message(version),
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
        """Streaming Hermes CLI worker — pure backend, no Companion SI packaging.

        Chat is a developer console to Hermes itself (its models/tools/config).
        Companion-owned SI briefing is a separate product surface.
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
        default_model, default_provider = resolve_hermes_defaults()
        model = (
            _cfg_str(config, "model")
            or str(kwargs.get("model") or "").strip()
            or default_model
        )
        provider = (
            _cfg_str(config, "provider")
            or str(kwargs.get("model_provider") or "").strip()
            or default_provider
        )
        # ARES connection ids are not Hermes providers
        if provider in {
            "hermes_local", "jros_local", "claude_local", "codex_local",
            "gemini_local", "grok_local", "opencode_local", "cursor_local",
            "pi_local", "openai_cloud", "xai_cloud", "ollama_local",
        }:
            provider = default_provider
        toolsets = _cfg_str(config, "toolsets") or ""
        max_turns = _cfg_int(config, "max_turns") or 150
        timeout_sec = _cfg_int(config, "timeout_sec") or 300

        # Build the hermes command
        args = [cli, "chat", "-q", message, "-Q", "--yolo", "--source", "webui"]

        # When ARES SI owns the turn, strip Hermes SOUL/AGENTS/memory injection
        # so the Companion identity briefing is not overridden by worker branding.
        if kwargs.get("si_owned") or kwargs.get("ignore_worker_identity"):
            args.append("--ignore-rules")

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
            "inventory": self.inventory(),
        }

    def inventory(self) -> Dict[str, Any]:
        """Catalog Hermes providers, models (local installs + configured), transports, MCP.

        Discovery mirrors hermes-paperclip-adapter detect-model + expands with
        auth credential pool and local Ollama tags.
        """
        from api.backends.catalog import (
            finalize_inventory,
            gateway_entry,
            infer_model_location,
            mcp_entry,
            transport_entry,
        )
        from api.backends.model_discovery import discover_hermes_models

        available, version = _probe_hermes()
        cli = _hermes_cli()
        discovered = discover_hermes_models()
        models = list(discovered.get("models") or [])
        providers = list(discovered.get("providers") or [])
        default = discovered.get("default") or {}
        active_model = default.get("model")
        active_provider = default.get("provider")

        transports = [
            transport_entry(
                id="cli_chat",
                kind="cli",
                label="Hermes CLI chat",
                in_use=True,
                endpoint=cli or "hermes",
                notes="Active ARES path: subprocess `hermes chat -q … -Q --yolo --source webui`.",
            ),
            transport_entry(
                id="mcp_serve",
                kind="mcp",
                label="Hermes MCP server",
                in_use=False,
                endpoint="hermes mcp serve",
                notes="Often used by Claude Code / other MCP clients; not the ARES chat turn path today.",
            ),
        ]

        gateways = [
            gateway_entry(
                id="hermes_webui",
                kind="http_gateway",
                label="Hermes WebUI server (if running)",
                endpoint="http://127.0.0.1:* (hermes-webui/server.py)",
                in_use=False,
                protocol="hermes-webui",
                notes="Separate product surface; catalogued when present on the host.",
            ),
        ]

        mcp = [
            mcp_entry(
                id="hermes_mcp_serve",
                label="Hermes MCP serve",
                command="hermes",
                args=["mcp", "serve", "--accept-hooks"],
                in_use_by_ares=False,
                used_by=["claude_code", "external_mcp_clients"],
                notes="Tools exposed to MCP hosts; ARES /api/mcp/tools may still be empty.",
            ),
        ]

        return finalize_inventory(
            {
                "worker_id": self.name,
                "display_name": "Hermes Agent",
                "models": models,
                "providers": providers,
                "default": default,
                "transports": transports,
                "gateways": gateways,
                "mcp": mcp,
                "tools_summary": self.tools(),
                "active_execution": {
                    "available": available,
                    "version": version,
                    "transport": "cli_chat",
                    "model": active_model,
                    "provider": active_provider,
                    "model_location": infer_model_location(active_provider, active_model),
                    "cli_path": cli or None,
                },
                "notes": (
                    "Models = Hermes config defaults/fallbacks + installed local Ollama. "
                    "Providers = auth.json / credential_pool + config references. "
                    "Latency dominated by selected model/provider, not CLI transport alone."
                ),
            }
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None


def _cfg_int(config: dict, key: str) -> int | None:
    val = config.get(key)
    return int(val) if isinstance(val, (int, float)) else None
