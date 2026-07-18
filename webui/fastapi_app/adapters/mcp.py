"""MCP tool-capability adapter.

MCP is intentionally not an LLM adapter: it provides tools to runtimes selected
through ``BaseLLMAdapter``.  Inventory reads never start or probe MCP servers.
"""

from __future__ import annotations

from typing import Any

from .base import AdapterHealth, BaseToolAdapter
from ..request_context import profile_scope


class McpToolAdapter(BaseToolAdapter):
    adapter_id = "mcp"
    display_name = "MCP tools"

    @staticmethod
    def _runtime_status() -> dict[str, dict[str, Any]]:
        try:
            from tools.mcp_tool import get_mcp_status

            rows = get_mcp_status()
        except Exception:
            return {}
        if not isinstance(rows, list):
            return {}
        return {
            str(row.get("name")): row
            for row in rows
            if isinstance(row, dict) and row.get("name")
        }

    @staticmethod
    def _configured_servers() -> dict[str, dict[str, Any]]:
        from api.config import get_config

        servers = get_config().get("mcp_servers", {})
        return servers if isinstance(servers, dict) else {}

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        with profile_scope(profile):
            configured = self._configured_servers()
            runtime = self._runtime_status()
        enabled = [name for name, cfg in configured.items() if not isinstance(cfg, dict) or cfg.get("enabled", True)]
        connected = [name for name in enabled if bool((runtime.get(str(name)) or {}).get("connected"))]
        if connected:
            return AdapterHealth(
                "connected",
                True,
                f"{len(connected)} MCP server(s) connected.",
                {"configured": len(configured), "connected": len(connected)},
            )
        if enabled:
            return AdapterHealth(
                "needs_attention",
                False,
                "MCP servers are configured but none are currently connected.",
                {"configured": len(configured), "connected": 0},
            )
        return AdapterHealth("offline", False, "No MCP tool servers are configured.")

    def capabilities(self, *, profile: str | None) -> list[str]:
        del profile
        return ["tool.discovery", "tool.use"]

    def list_tools(self, *, profile: str | None) -> dict[str, Any]:
        from api.helpers import _redact_text

        with profile_scope(profile):
            configured = self._configured_servers()
            runtime = self._runtime_status()
            summaries: list[dict[str, Any]] = []
            for server_name, status in runtime.items():
                raw_tools = status.get("tools")
                if not isinstance(raw_tools, list):
                    raw_tools = status.get("tool_schemas")
                if not isinstance(raw_tools, list):
                    continue
                connected = bool(status.get("connected"))
                for raw in raw_tools:
                    if isinstance(raw, str):
                        name, description = raw, ""
                    elif isinstance(raw, dict):
                        name = str(raw.get("name") or "")
                        description = str(raw.get("description") or "")
                    else:
                        continue
                    if name:
                        summaries.append(
                            {
                                "name": name,
                                "server": server_name,
                                "description": _redact_text(description)[:360],
                                "active": connected,
                                "enabled": True,
                                "status": "active" if connected else "configured",
                                "schema_summary": [],
                            }
                        )
            if not summaries:
                try:
                    from tools.registry import registry

                    for name in registry.get_all_tool_names():
                        toolset = registry.get_toolset_for_tool(name)
                        if not isinstance(toolset, str) or not toolset.startswith("mcp-"):
                            continue
                        server_name = toolset.removeprefix("mcp-")
                        connected = bool((runtime.get(server_name) or {}).get("connected"))
                        summaries.append(
                            {
                                "name": str(name),
                                "server": server_name,
                                "description": "",
                                "active": connected,
                                "enabled": True,
                                "status": "active" if connected else "configured",
                                "schema_summary": [],
                            }
                        )
                except Exception:
                    pass
        summaries.sort(key=lambda row: (row["server"], row["name"]))
        unavailable = sorted(
            str(name)
            for name, cfg in configured.items()
            if (not isinstance(cfg, dict) or cfg.get("enabled", True))
            and not bool((runtime.get(str(name)) or {}).get("connected"))
        )
        return {
            "tools": summaries,
            "total": len(summaries),
            "source": "adapter_registry",
            "inventory_scope": "already_known_runtime_only",
            "unavailable_servers": unavailable,
        }
