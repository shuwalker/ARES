"""System models — ARES configuration, connection state, and runtime data.

These models define ARES's own configuration (how to connect to Hermes,
MCP servers, etc.) and runtime state (emotion, perception frames).
They're the glue between the PydanticAI framework and the running system.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# ARES configuration
# ---------------------------------------------------------------------------

class HermesConnection(BaseModel):
    """How ARES connects to the Hermes agent subsystem."""

    hermes_home: str = Field("~/.ares/.hermes", description="HERMES_HOME path")
    hermes_source: str = Field("~/.ares/hermes-agent", description="Where Hermes source lives")
    bridge_port: int = Field(9876, description="HTTP bridge port for SwiftUI app")
    auto_start: bool = Field(True, description="Start Hermes automatically with ARES")

    model: str = Field("glm-5.1:cloud", description="Default model")
    provider: str = Field("ollama-cloud", description="Default provider")
    base_url: str = Field("https://ollama.com/v1", description="LLM endpoint")


class MCPServerConfig(BaseModel):
    """Configuration for an MCP server managed by ARES."""

    name: str = Field(..., description="Server name, e.g. 'perception'")
    port: int = Field(..., description="Port to run on")
    module: str = Field(..., description="Python module path, e.g. 'ares.skills.cognitive.perception_server'")
    enabled: bool = Field(True, description="Whether to start this server")
    auto_restart: bool = Field(True, description="Restart on crash")


class AresConfig(BaseModel):
    """Top-level ARES configuration. Persisted to ~/.ares/config/ares.toml."""

    version: int = Field(2, description="Config schema version")
    name: str = Field("ARES", description="System name")
    environment: str = Field("desktop", description="desktop | robot")

    # Hermes connection
    hermes: HermesConnection = Field(default_factory=HermesConnection)

    # MCP servers
    mcp_servers: dict[str, MCPServerConfig] = Field(default_factory=lambda: {
        "perception": MCPServerConfig(name="perception", port=9512, module="ares.skills.cognitive.perception_server"),
        "voice": MCPServerConfig(name="voice", port=9513, module="ares.skills.cognitive.voice_server"),
        "avatar": MCPServerConfig(name="avatar", port=9514, module="ares.skills.cognitive.avatar_server"),
        "mac_tools": MCPServerConfig(name="mac_tools", port=9515, module="ares.skills.cognitive.mac_tools_server"),
    })

    # Memory
    memory_db: str = Field("~/.ares/memory.db", description="SQLite database path")
    workspace: str = Field("~/.ares/workspace", description="Workspace directory")

    # Sync
    icloud_sync: bool = Field(False, description="Enable iCloud sync for continuity")

    updated_at: datetime = Field(default_factory=datetime.now)


# ---------------------------------------------------------------------------
# Runtime state models (used by hermes_bridge and the app)
# ---------------------------------------------------------------------------

class EmotionState(str, Enum):
    idle = "idle"
    awakened = "awakened"
    listening = "listening"
    thinking = "thinking"
    speaking = "speaking"
    sleeping = "sleeping"
    error = "error"


class ExpressionState(str, Enum):
    neutral = "neutral"
    happy = "happy"
    curious = "curious"
    thinking = "thinking"
    surprised = "surprised"
    concerned = "concerned"
    excited = "excited"
    sleepy = "sleepy"


class PerceptionFrame(BaseModel):
    """A single frame from the perception pipeline (YOLOv8n + Florence-2)."""

    timestamp: datetime = Field(default_factory=datetime.now)
    objects: list[dict] = Field(default_factory=list, description="Detected objects from YOLOv8n")
    caption: str = Field("", description="Scene description from Florence-2")
    person_present: bool = Field(False, description="Whether a person was detected")
    person_count: int = Field(0, description="Number of people detected")
    confidence: float = Field(0.0, description="Overall confidence of the frame analysis")