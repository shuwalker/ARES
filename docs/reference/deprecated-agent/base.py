"""ARES Tool Base – plugin interface for tool actions.

Every tool in ARES declares capabilities, required permissions, and
resource metadata. The orchestrator loads and invokes them dynamically.
"""
from __future__ import annotations

import abc
import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class RiskLevel(str, Enum):
    """Risk classification for tool operations."""

    SAFE = "safe"  # Read-only, no side effects
    MODERATE = "moderate"  # File writes, network requests
    DANGEROUS = "dangerous"  # System commands, browser control, destructive ops


@dataclass
class ToolCapability:
    """Describes a single action a tool can perform."""

    name: str
    description: str
    parameters: dict[str, Any]  # JSON Schema-style parameter definitions
    risk_level: RiskLevel = RiskLevel.SAFE
    examples: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Validate capability configuration."""
        if not self.name:
            raise ValueError("Capability name cannot be empty")
        if not self.description:
            raise ValueError("Capability description cannot be empty")
        if not isinstance(self.parameters, dict):
            raise ValueError("Parameters must be a dictionary")


@dataclass
class ToolResult:
    """Standardized result from tool execution."""

    success: bool
    data: Any = None
    error: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def __repr__(self) -> str:
        if self.success:
            return f"ToolResult(success=True, data={self.data!r})"
        return f"ToolResult(success=False, error={self.error!r})"


class BaseTool(abc.ABC):
    """Abstract base class for all ARES tool satellites."""

    def __init__(self) -> None:
        self.logger = logging.getLogger(f"ares.tools.{self.name}")
        self._initialized = False

    @property
    @abc.abstractmethod
    def name(self) -> str:
        """Unique identifier for this tool.

        Must be lowercase alphanumeric with underscores.
        Examples: "shell", "computer", "file_reader"
        """
        ...

    @property
    @abc.abstractmethod
    def description(self) -> str:
        """Human-readable description of what this tool does."""
        ...

    @property
    @abc.abstractmethod
    def capabilities(self) -> list[ToolCapability]:
        """List of actions this tool can perform.

        Returns:
            Non-empty list of ToolCapability objects.
        """
        ...

    @property
    def version(self) -> str:
        """Tool version string. Override to customize."""
        return "0.1.0"

    @property
    def is_initialized(self) -> bool:
        """Returns True if the tool has been initialized."""
        return self._initialized

    async def initialize(self, config: dict[str, Any] | None = None) -> None:
        """Called once when the tool is loaded. Override for setup logic.

        Args:
            config: Optional configuration dictionary passed from orchestrator.

        Raises:
            Exception: Subclasses may raise if initialization fails.
        """
        self._initialized = True
        self.logger.info(f"Tool '{self.name}' initialized (satellite in orbit)")

    async def shutdown(self) -> None:
        """Called when ARES shuts down. Override for cleanup.

        Should gracefully close connections, flush buffers, etc.
        """
        self._initialized = False
        self.logger.info(f"Tool '{self.name}' shut down (satellite deorbited)")

    @abc.abstractmethod
    async def execute(self, action: str, **kwargs: Any) -> ToolResult:
        """Execute an action. Must be implemented by all tools.

        Args:
            action: Name of the action to execute (must match a capability name).
            **kwargs: Action-specific parameters.

        Returns:
            ToolResult indicating success/failure and containing the result data.

        Raises:
            ValueError: If action is not supported or parameters are invalid.
        """
        ...

    async def health_check(self) -> bool:
        """Returns True if the tool is operational and ready to execute.

        Override in subclasses to perform more sophisticated health checks
        (e.g., testing database connections, WebSocket availability).

        Returns:
            True if healthy, False otherwise.
        """
        return self._initialized

    def get_schema(self) -> list[dict[str, Any]]:
        """Returns bare function schemas for LLM tool calling.

        Returns inner function definitions without provider-specific wrapping.
        The LLM provider layer handles wrapping for OpenAI or Anthropic format.

        Returns:
            List of function schema dictionaries.
        """
        functions = []
        for cap in self.capabilities:
            functions.append(
                {
                    "name": f"{self.name}.{cap.name}",
                    "description": cap.description,
                    "parameters": {
                        "type": "object",
                        "properties": cap.parameters,
                    },
                }
            )
        return functions

    def __repr__(self) -> str:
        status = "orbiting" if self._initialized else "grounded"
        return f"<Tool:{self.name} v{self.version} [{status}]>"
