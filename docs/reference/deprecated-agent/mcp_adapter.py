"""MCP (Model Context Protocol) Tool Adapter.

Allows ARES to use external MCP servers as tools, and exposes ARES tools
as an MCP server that other agents can consume.

MCP is the emerging standard for agent-to-tool communication. Instead of
hard-coding tool implementations, tools are served over HTTP/WebSocket as
MCP servers. This gives us:
  - Hot-swappable tools without restarting ARES
  - Tools shared across multiple agents (nanobot, OpenClaw, etc.)
  - Standard discovery via tools/list endpoint
  - Loose coupling: tool lives in its own process

Usage:
    # Connect an external MCP server as a tool
    from ares.modules.tools.mcp_adapter import MCPToolAdapter
    adapter = MCPToolAdapter(name="web_browser", url="http://localhost:3001")
    await adapter.initialize()
    tool_registry.register(adapter)

    # Discover all tools from an MCP server
    from ares.modules.tools.mcp_adapter import MCPDiscovery
    tools = await MCPDiscovery.discover("http://localhost:3001")
    for tool in tools:
        tool_registry.register(tool)
"""
from __future__ import annotations

import json
import logging
import uuid
from typing import Any, Optional

import httpx

from .base import BaseTool, RiskLevel, ToolCapability, ToolResult

logger = logging.getLogger("ares.tools.mcp_adapter")


class MCPToolAdapter(BaseTool):
    """Wraps an external MCP server endpoint as an ARES tool.

    Follows the MCP specification:
      POST /tools/call  → execute a tool
      GET  /tools/list  → discover capabilities

    Each MCPToolAdapter represents one named tool from the MCP server.
    Use MCPDiscovery.discover() to auto-create adapters for all available tools.
    """

    def __init__(
        self,
        tool_name: str,
        server_url: str,
        description: str = "",
        input_schema: Optional[dict[str, Any]] = None,
        timeout: float = 60.0,
    ) -> None:
        """Initialize MCP tool adapter.

        Args:
            tool_name: Name of the tool as reported by the MCP server.
            server_url: Base URL of the MCP server (e.g. "http://localhost:3001").
            description: Human-readable description of the tool.
            input_schema: JSON Schema for the tool's input parameters.
            timeout: Request timeout in seconds.
        """
        self._tool_name = tool_name
        super().__init__()
        self.server_url = server_url.rstrip("/")
        self._description = description
        self._input_schema = input_schema or {}
        self.timeout = timeout
        self._client: Optional[httpx.AsyncClient] = None

    @property
    def name(self) -> str:
        # Sanitise: MCP names can have slashes, ARES uses underscores
        return self._tool_name.replace("/", "_").replace("-", "_")

    @property
    def description(self) -> str:
        return self._description or f"MCP tool: {self._tool_name}"

    @property
    def capabilities(self) -> list[ToolCapability]:
        """Derive capabilities from the input schema."""
        return [
            ToolCapability(
                name="call",
                description=self.description,
                parameters=self._input_schema,
                risk_level=RiskLevel.MODERATE,
            )
        ]

    @property
    def version(self) -> str:
        return "mcp-1.0"

    async def initialize(self, config: Optional[dict[str, Any]] = None) -> None:
        """Create HTTP client."""
        self._client = httpx.AsyncClient(timeout=self.timeout)
        self._initialized = True
        logger.info(f"MCPToolAdapter '{self.name}' connected to {self.server_url}")

    async def shutdown(self) -> None:
        """Close HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None

    async def health_check(self) -> bool:
        """Ping the MCP server."""
        try:
            client = self._client or httpx.AsyncClient(timeout=5.0)
            resp = await client.get(f"{self.server_url}/health")
            return resp.status_code == 200
        except Exception:
            return False

    async def execute(self, action: str, **kwargs: Any) -> ToolResult:
        """Call the MCP tool.

        Args:
            action: Ignored for MCP tools (always 'call'). Present for interface compatibility.
            **kwargs: Arguments forwarded as the tool's input.

        Returns:
            ToolResult with MCP server's response.
        """
        if not self._client:
            return ToolResult(success=False, error="MCPToolAdapter not initialized")

        request_id = str(uuid.uuid4())
        payload = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "tools/call",
            "params": {
                "name": self._tool_name,
                "arguments": kwargs,
            },
        }

        try:
            resp = await self._client.post(
                f"{self.server_url}/",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            data = resp.json()

            if "error" in data:
                return ToolResult(
                    success=False,
                    error=f"MCP error: {data['error'].get('message', str(data['error']))}",
                )

            result = data.get("result", {})
            # MCP returns content as a list of content blocks
            content = result.get("content", [])
            if isinstance(content, list) and content:
                text_parts = [
                    c.get("text", "") for c in content if c.get("type") == "text"
                ]
                result_text = "\n".join(text_parts) or json.dumps(result)
            else:
                result_text = json.dumps(result)

            return ToolResult(
                success=True,
                data=result_text,
                metadata={"mcp_server": self.server_url, "tool": self._tool_name},
            )

        except httpx.ConnectError as e:
            logger.warning(f"MCP server {self.server_url} unreachable: {e}")
            return ToolResult(success=False, error=f"MCP server unreachable: {e}")
        except Exception as e:
            logger.error(f"MCP call failed: {e}")
            return ToolResult(success=False, error=str(e))


class MCPDiscovery:
    """Discovers all tools from an MCP server and creates adapters."""

    @staticmethod
    async def discover(
        server_url: str,
        timeout: float = 10.0,
    ) -> list[MCPToolAdapter]:
        """Query an MCP server's tools/list endpoint and return adapters.

        Args:
            server_url: Base URL of the MCP server.
            timeout: Request timeout in seconds.

        Returns:
            List of MCPToolAdapter instances, one per tool.
        """
        server_url = server_url.rstrip("/")
        payload = {
            "jsonrpc": "2.0",
            "id": str(uuid.uuid4()),
            "method": "tools/list",
            "params": {},
        }

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.post(
                    f"{server_url}/",
                    json=payload,
                    headers={"Content-Type": "application/json"},
                )
                resp.raise_for_status()
                data = resp.json()

            tools_list = data.get("result", {}).get("tools", [])
            adapters = []
            for tool_def in tools_list:
                adapter = MCPToolAdapter(
                    tool_name=tool_def.get("name", "unknown"),
                    server_url=server_url,
                    description=tool_def.get("description", ""),
                    input_schema=tool_def.get("inputSchema", {}),
                )
                await adapter.initialize()
                adapters.append(adapter)
                logger.info(f"Discovered MCP tool: {adapter.name} from {server_url}")

            return adapters

        except Exception as e:
            logger.error(f"MCP discovery failed for {server_url}: {e}")
            return []
