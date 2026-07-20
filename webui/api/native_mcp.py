"""Runtime wiring for the native MCP helper bundled with the macOS app."""

from __future__ import annotations

import os
from pathlib import Path


SERVER_NAME = "ares_native"


def native_server_config() -> dict[str, dict]:
    """Return an ephemeral MCP config for the signed helper, if available."""

    raw = os.environ.get("ARES_NATIVE_MCP_COMMAND", "").strip()
    if not raw:
        return {}
    executable = Path(raw).expanduser()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        return {}
    return {
        SERVER_NAME: {
            "command": str(executable.resolve()),
            "args": [],
            "enabled": True,
            "connect_timeout": 15,
            "timeout": 120,
        }
    }


def register_native_mcp_tools() -> list[str]:
    """Connect the bundled helper to Hermes without altering user config."""

    servers = native_server_config()
    if not servers:
        return []
    from tools.mcp_tool import register_mcp_servers

    return register_mcp_servers(servers)
