"""Let Hermes (and its MoA loop) borrow JROS's Companion over MCP.

Mirror of api.jros_hermes_mcp, in the other direction. JROS already ships an
MCP *server* for exactly this shape: ``jaeger_os/interfaces/mcp_server.py``,
run via ``jaeger mcp`` (see its own docstring). That server exposes a single
``chat`` tool that drives one full turn through the real JROS agent loop
(persona, memory, tools) plus ``agent_info``. It does NOT expose JROS's
individual tools (robotics, voice, etc.) as separate MCP tools, and that is
deliberate on the JROS side, not a gap here: routing individual tool calls
into JROS's body/voice from an external loop would let that loop drive JROS
without JROS's own reasoning in the path, which is the "silently fork a
competing persona" case ARES's own rules forbid. So what this module wires up
is "Hermes/MoA can consult the JROS Companion as one MCP tool," not granular
per-capability routing.

This module only merges a config entry into Hermes's own MCP client config
(``~/.hermes/config.yaml`` -> ``mcp_servers``, read/written through
``hermes_cli.config``). It does not touch JROS or Hermes source, and
preserves any other MCP servers already configured there.
"""
from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

JROS_MCP_SERVER_NAME = "jros"


def _jaeger_launcher_path():
    from api.jros_paths import jaeger_launcher

    try:
        launcher = jaeger_launcher()
    except Exception:
        return None
    return launcher if launcher and launcher.exists() else None


def jros_mcp_available() -> bool:
    """True when ARES can find both a local JROS install (to point Hermes's
    MCP client at) and a Hermes agent checkout (whose config we'd write)."""
    from api.config import _AGENT_DIR

    return _jaeger_launcher_path() is not None and _AGENT_DIR is not None


def sync_jros_mcp_server(*, enabled: bool = True) -> dict[str, Any]:
    """Merge (or remove) the 'jros' MCP server entry in Hermes's own
    mcp_servers config. Preserves every other configured server untouched."""
    from api.config import _AGENT_DIR

    if _AGENT_DIR is None:
        raise RuntimeError("No Hermes Agent checkout found — cannot configure its MCP client.")
    launcher = _jaeger_launcher_path()
    if enabled and launcher is None:
        raise RuntimeError("No local JROS install found — cannot expose it to Hermes over MCP.")

    from api.jros_gateway_chat import _jros_instance_name, local_jros_root
    from hermes_cli.config import load_config, save_config

    config = load_config()
    servers = dict(config.get("mcp_servers") or {})
    servers.pop(JROS_MCP_SERVER_NAME, None)

    if enabled:
        instance = _jros_instance_name()
        args = ["mcp"]
        if instance:
            args.append(instance)
        root = local_jros_root()
        entry: dict[str, Any] = {"command": str(launcher), "args": args}
        if root is not None:
            entry["cwd"] = str(root)
        servers[JROS_MCP_SERVER_NAME] = entry

    config["mcp_servers"] = servers
    save_config(config)
    return {"ok": True, "enabled": enabled, "server_count": len(servers)}


def set_jros_tools_enabled(enabled: bool) -> dict[str, Any]:
    """Flip the addition on/off: sync Hermes's mcp_servers entry AND persist
    hermes_jros_tools_enabled so ARES's own UI/status reflects it."""
    from api.config import _get_config_path, _load_yaml_config_file, _save_yaml_config_file, reload_config

    sync_result = sync_jros_mcp_server(enabled=enabled)

    config_path = _get_config_path()
    cfg = _load_yaml_config_file(config_path)
    cfg["hermes_jros_tools_enabled"] = bool(enabled)
    _save_yaml_config_file(config_path, cfg)
    reload_config()

    return {"ok": True, "enabled": bool(enabled), "mcp_sync": sync_result}
