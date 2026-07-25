"""Let a JROS-primary Companion borrow Ares's tools over MCP.

Ares already ships a production MCP server built for exactly this shape —
an external agent loop that wants Ares's tool surface without adopting its
whole runtime: ``agent/transports/ares_tools_mcp_server.py`` (web_search,
browser automation, vision, image-gen, skills, TTS, kanban — see its own
docstring for the exact curated set and why the stateful tools are excluded).

This module only merges a config entry into JROS's own MCP client config
(``jaeger_os/plugins/mcp/mcp_config.json``) pointing at that server. It does
not touch Ares source, and preserves any other MCP servers already
configured there. The companion piece — actually booting JROS with MCP
enabled — is ``with_mcp=`` on ``boot_for_tui`` (JROS) / the
``jros_ares_tools_enabled`` config flag this module's caller checks.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

ARES_TOOLS_SERVER_NAME = "ares-tools"


def _jros_mcp_config_path() -> Path | None:
    from api.jros_gateway_chat import local_jros_root

    root = local_jros_root()
    if root is None:
        return None
    return root / "jaeger_os" / "plugins" / "mcp" / "mcp_config.json"


def ares_mcp_available() -> bool:
    """True when ARES can find both a local JROS install and a Ares
    agent checkout to point JROS's MCP client at."""
    from api.config import _AGENT_DIR

    return _jros_mcp_config_path() is not None and _AGENT_DIR is not None


def sync_ares_mcp_server(*, enabled: bool = True) -> dict[str, Any]:
    """Merge (or remove) the 'ares-tools' MCP server entry in JROS's
    mcp_config.json. Preserves every other configured server untouched."""
    from api.config import _AGENT_DIR, PYTHON_EXE

    config_path = _jros_mcp_config_path()
    if config_path is None:
        raise RuntimeError("No local JROS install found — cannot configure its MCP client.")
    if enabled and _AGENT_DIR is None:
        raise RuntimeError("No Ares Agent checkout found — cannot expose its tools over MCP.")

    data: dict[str, Any] = {"servers": []}
    if config_path.exists():
        try:
            data = json.loads(config_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            logger.warning("Could not parse existing %s; starting fresh", config_path)
    servers = [s for s in data.get("servers", []) if s.get("name") != ARES_TOOLS_SERVER_NAME]

    if enabled:
        servers.append({
            "name": ARES_TOOLS_SERVER_NAME,
            "enabled": True,
            "command": PYTHON_EXE,
            "args": ["-m", "agent.transports.ares_tools_mcp_server"],
            "cwd": str(_AGENT_DIR),
        })

    data["servers"] = servers
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return {"ok": True, "path": str(config_path), "enabled": enabled, "server_count": len(servers)}


def set_ares_tools_enabled(enabled: bool) -> dict[str, Any]:
    """Flip the addition on/off: sync JROS's mcp_config.json entry AND
    persist jros_ares_tools_enabled so the next Companion boot picks it
    up (see api.jros_gateway_chat._jros_ares_tools_enabled)."""
    from api.config import _get_config_path, _load_yaml_config_file, _save_yaml_config_file, reload_config

    sync_result = sync_ares_mcp_server(enabled=enabled)

    config_path = _get_config_path()
    cfg = _load_yaml_config_file(config_path)
    cfg["jros_ares_tools_enabled"] = bool(enabled)
    _save_yaml_config_file(config_path, cfg)
    reload_config()

    from api.jros_gateway_chat import reset_jros_boot

    reset_jros_boot()

    return {"ok": True, "enabled": bool(enabled), "mcp_sync": sync_result}
