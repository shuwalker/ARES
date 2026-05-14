"""ARES Pydantic models — structured data contracts for the entire system.

Every piece of structured data that flows through ARES gets a model here.
MCP tool parameters, project states, engineering specs, memory entries —
all validated, typed, and versioned.
"""

from .project import (
    Project,
    ProjectState,
    ProjectPriority,
    ProjectStatus,
)
from .engineering import (
    ThrusterSpec,
    CatalystParams,
    TestResult,
    ComponentSpec,
    MaterialSpec,
)
from .system import (
    AresConfig,
    HermesConnection,
    MCPServerConfig,
    EmotionState,
    PerceptionFrame,
)

__all__ = [
    "Project",
    "ProjectState",
    "ProjectPriority",
    "ProjectStatus",
    "ThrusterSpec",
    "CatalystParams",
    "TestResult",
    "ComponentSpec",
    "MaterialSpec",
    "AresConfig",
    "HermesConnection",
    "MCPServerConfig",
    "EmotionState",
    "PerceptionFrame",
]
