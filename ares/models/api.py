"""ARES API request/response models — Pydantic data contracts for the REST+WS API.

All request and response Pydantic models used by ares.api live here
so the route handler module stays focused on logic, not data declarations.
"""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------


class PersonalityUpdateRequest(BaseModel):
    layer: str = Field(..., description="hexaco, special, expression, or domains")
    trait: str = Field(..., description="Trait name within the layer")
    value: float = Field(..., ge=0.0, le=1.0, description="Value 0.0-1.0")


class FaceStateRequest(BaseModel):
    state: Optional[str] = Field(
        None, description="Face state: idle, awakened, listening, thinking, speaking, sleeping"
    )
    emotion: Optional[str] = Field(None, description="Emotion: happy, sad, curious, surprised, angry, neutral")


class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class MemoryStoreRequest(BaseModel):
    content: str
    tags: Optional[str] = None
    source: str = "api"


class MemorySearchRequest(BaseModel):
    query: str
    tag: Optional[str] = None
    limit: int = 10


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------


class PersonalityUpdateResponse(BaseModel):
    updated: bool
    layer: str
    trait: str
    value: float


class ChatResponse(BaseModel):
    response: str
    face_state: str
    personality_prompt: Optional[str] = None


class StatusResponse(BaseModel):
    name: str
    version: str
    face_state: str
    bus: dict[str, Any] = Field(default_factory=dict, description="Open-shape bus status snapshot")
    websocket_clients: int
    uptime: float


class ServiceHealth(BaseModel):
    model_config = ConfigDict(extra="allow")  # health_response and similar passthrough fields
    name: str
    port: int
    kind: str
    running: bool
    pid: int | None = None
    uptime: int = 0
    reachable: bool = False


class ServicesResponse(BaseModel):
    status: str
    timestamp: float
    total: int
    healthy: int
    services: list[ServiceHealth]


class IdentityResponse(BaseModel):
    name: str
    role: str
    voice: str
    self_model: str


class FaceConfigBlock(BaseModel):
    color: list[float]
    opacity: float
    pulse_speed: float
    pulse_amount: float
    pupil_offset: list[float]


class FaceStateResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    state: Optional[str] = None
    emotion: Optional[str] = None
    current_state: Optional[str] = None
    config: Optional[dict[str, Any]] = None


class FaceStateEntry(BaseModel):
    name: str
    config: FaceConfigBlock


class FaceStatesResponse(BaseModel):
    states: list[FaceStateEntry]


class MemoryStoreResponse(BaseModel):
    model_config = ConfigDict(extra="allow")
    stored: bool | None = None
    id: int | str | None = None


class MemorySearchResponse(BaseModel):
    count: int
    results: list[dict[str, Any]]


class CognitiveStartResponse(BaseModel):
    status: str
    goal: Optional[str] = None
    max_cycles: Optional[int] = None


class CognitiveStopResponse(BaseModel):
    status: str


class CognitiveStatusResponse(BaseModel):
    running: bool
    status: Optional[str] = None
    cycle: Optional[int] = None
    phase: Optional[str] = None
    urgency: Optional[str] = None
    budget_remaining: Optional[float] = None
    face_state: Optional[str] = None
    errors: Optional[list[Any]] = None


class PersonalityPromptResponse(BaseModel):
    prompt: str