"""ARES Tool Adapter — registers ARES tools into Hermes or JROS.

This module is the bridge that lets ARES-owned tools appear as native
tools in whichever backend is active. It produces the right format
for each backend:

  - Hermes: MCP-compatible tool schemas (inputSchema + handler)
  - JROS:  ToolDef-compatible dicts (name, description, args_model, fn)

The tool implementations themselves live in ares_tools.py. This
module only handles registration format translation.

ARES tools are backend-agnostic. They operate on the ARES continuity
DB, not on Hermes or JROS internals. The adapter just makes them
visible to whichever agent loop is running.
"""

from __future__ import annotations

import logging
from typing import Any

try:
    from api.ares_tools import ARES_TOOL_DEFS
except ImportError:
    ARES_TOOL_DEFS = []

logger = logging.getLogger(__name__)


def _build_mcp_schema(tool_def: dict[str, Any]) -> dict[str, Any]:
    """Convert an ARES tool definition to Hermes MCP format.

    Hermes MCP expects:
      - name: tool name
      - description: human-readable description
      - inputSchema: JSON Schema object for arguments
    """
    args_model = tool_def.get("args_model")
    schema = {}
    if args_model is not None:
        try:
            schema = args_model.model_json_schema()
        except Exception as exc:
            logger.warning("Failed to generate schema for %s: %s",
                           tool_def["name"], exc)
            schema = {"type": "object", "properties": {}}

    return {
        "name": tool_def["name"],
        "description": tool_def["description"],
        "inputSchema": schema,
        # The handler is carried separately — Hermes MCP registration
        # wires it up via the server's tool dispatch table.
        "_handler": tool_def["fn"],
    }


def _build_jros_tooldef(tool_def: dict[str, Any]) -> dict[str, Any]:
    """Convert an ARES tool definition to JROS ToolDef format.

    JROS ToolDef expects:
      - name: tool name
      - description: human-readable description
      - args_model: Pydantic BaseModel class
      - fn: callable handler
    """
    return {
        "name": tool_def["name"],
        "description": tool_def["description"],
        "args_model": tool_def.get("args_model"),
        "fn": tool_def["fn"],
        # JROS-specific flags — ARES tools are safe defaults
        "interactive": False,
        "dangerous": False,
        "beta": False,
        "side_effect": "write" if "create" in tool_def["name"] or "update" in tool_def["name"] else "read",
    }


def register_ares_tools(target: str = "hermes") -> list[dict[str, Any]]:
    """Register ARES tools into the specified backend format.

    Args:
        target: Backend target — 'hermes' for MCP format,
                'jros' for ToolDef format.

    Returns:
        List of tool definitions in the target backend's format.

    Raises:
        ValueError: If target is not 'hermes' or 'jros'.
    """
    if target == "hermes":
        return [_build_mcp_schema(td) for td in ARES_TOOL_DEFS]
    elif target == "jros":
        return [_build_jros_tooldef(td) for td in ARES_TOOL_DEFS]
    else:
        raise ValueError(
            f"Unknown target backend: {target!r}. "
            f"Expected 'hermes' or 'jros'."
        )


def get_ares_tool_names() -> list[str]:
    """Return the names of all ARES-owned tools."""
    return [td["name"] for td in ARES_TOOL_DEFS]


def get_ares_tool_by_name(name: str) -> dict[str, Any] | None:
    """Look up an ARES tool definition by name."""
    for td in ARES_TOOL_DEFS:
        if td["name"] == name:
            return td
    return None