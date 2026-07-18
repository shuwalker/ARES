"""Pydantic wire contracts for the first FastAPI endpoint tranche."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class ExtensibleResponse(BaseModel):
    """Validate stable fields without discarding established response metadata."""

    model_config = ConfigDict(extra="allow")


class HealthResponse(ExtensibleResponse):
    status: str
    sessions: int = 0
    active_streams: int = 0
    uptime_seconds: float = 0


class AgentHealthResponse(ExtensibleResponse):
    alive: bool | None


class SettingsResponse(ExtensibleResponse):
    bot_name: str
    auth_enabled: bool
    webui_version: str | None = None


class SettingsUpdate(BaseModel):
    """Known Local Profile controls plus forward-compatible presentation keys."""

    model_config = ConfigDict(extra="allow", strict=True, populate_by_name=True)

    bot_name: str | None = Field(default=None, max_length=80)
    set_password: str | None = Field(default=None, alias="_set_password", max_length=4096)
    current_password: str | None = Field(default=None, alias="_current_password", max_length=4096)
    clear_password: bool | None = Field(default=None, alias="_clear_password")
    passwordless: bool | None = Field(default=None, alias="_passwordless")
    auth_disabled_acknowledged: bool | None = Field(
        default=None,
        alias="_auth_disabled_acknowledged",
    )
    max_tokens: int | None = Field(default=None, ge=1)
    context_store_enabled: bool | None = Field(default=None)

    @model_validator(mode="before")
    @classmethod
    def reject_server_owned_fields(cls, value):
        if isinstance(value, dict) and "password_hash" in value:
            raise ValueError("password_hash is server-owned")
        return value

    @field_validator("bot_name")
    @classmethod
    def normalize_bot_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or "Ares"


class SessionRecord(ExtensibleResponse):
    session_id: str
    title: str = "Untitled"
    workspace: str = ""
    messages: list[dict[str, Any]] | None = None


class SessionsResponse(ExtensibleResponse):
    sessions: list[SessionRecord]


class SessionResponse(BaseModel):
    session: SessionRecord


class SessionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    workspace: str | None = Field(default=None, max_length=4096)
    profile: str | None = Field(default=None, max_length=80)
    prev_session_id: str | None = Field(default=None, max_length=256)
    model: str | None = Field(default=None, max_length=512)
    model_provider: str | None = Field(default=None, max_length=128)
    project_id: str | None = Field(default=None, max_length=256)
    enabled_toolsets: list[str] | None = None
    worktree: bool = False


class SessionMutation(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)


class SessionYoloUpdate(SessionMutation):
    enabled: bool = True


class SessionCompression(SessionMutation):
    # Legacy compression clients receive a domain-level 400 for a missing id;
    # keep that contract instead of converting it to FastAPI's generic 422.
    session_id: str = Field(default="", max_length=256)
    focus_topic: str | None = Field(default=None, max_length=500)
    topic: str | None = Field(default=None, max_length=500)


class SessionCliImport(SessionMutation):
    profile: str | None = Field(default=None, max_length=64)
    all_profiles: Any = False


class SessionHandoffSummary(SessionMutation):
    session_id: str = Field(default="", max_length=256)
    since: Any = None


class SessionAnchorScene(SessionMutation):
    session_id: str = Field(default="", max_length=256)
    scene: dict[str, Any] | None = None
    message_index: Any = None
    message_offset: Any = None
    message_window_index: Any = None
    message_ref: str = Field(default="", max_length=4096)
    stream_id: str = Field(default="", max_length=256)


class SessionDraftUpdate(SessionMutation):
    text: Any = None
    files: Any = None


class SessionToolsetsUpdate(SessionMutation):
    toolsets: list[str] | None = None


class SessionTruncate(SessionMutation):
    keep_count: Any


class SessionBranch(SessionMutation):
    keep_count: Any = None
    title: str | None = Field(default=None, max_length=80)


class SessionRename(SessionMutation):
    title: str = Field(max_length=10_000)


class SessionWorktreeRemove(SessionMutation):
    force: bool = False


class SessionPin(SessionMutation):
    pinned: bool = True


class SessionArchive(SessionMutation):
    archived: bool = True


class SessionMove(SessionMutation):
    project_id: str | None = Field(default=None, max_length=256)


class SessionConversationRounds(SessionMutation):
    since: Any = None


class SessionTitleRegenerate(SessionMutation):
    prefer_latest: bool = False


class SessionImportPayload(BaseModel):
    model_config = ConfigDict(extra="allow", strict=True)

    messages: Any = None
    title: Any = "Imported session"
    workspace: Any = None
    model: Any = None
    tool_calls: Any = None
    pinned: Any = False


class SessionUpdate(SessionMutation):
    workspace: str | None = Field(default=None, max_length=4096)
    model: str | None = Field(default=None, max_length=512)
    model_provider: str | None = Field(default=None, max_length=256)


class ProjectCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    name: str = Field(min_length=1, max_length=128)
    color: str | None = Field(default=None, max_length=9)
    profile: str | None = Field(default=None, max_length=64)


class ProjectRename(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    project_id: str = Field(min_length=1, max_length=256)
    name: str = Field(min_length=1, max_length=128)
    color: str | None = Field(default=None, max_length=9)


class ProjectDelete(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    project_id: str = Field(min_length=1, max_length=256)


class FileMutation(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)
    path: str = Field(min_length=1, max_length=4096)


class FileDelete(FileMutation):
    recursive: bool = False


class FileSave(FileMutation):
    content: Any = ""


class FileCreate(FileMutation):
    content: Any = ""


class FileRename(FileMutation):
    new_name: str = Field(min_length=1, max_length=512)


class FileMove(FileMutation):
    dest_dir: str = Field(default=".", max_length=4096)


class McpServerUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    url: str | None = Field(default=None, max_length=4096)
    headers: dict[str, Any] | None = None
    command: str | None = Field(default=None, max_length=4096)
    args: list[str] | str | None = None
    env: dict[str, Any] | None = None
    timeout: int | str | None = None
    connect_timeout: int | str | None = None
    enabled: bool | None = None


class McpServerToggle(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    enabled: bool


class ClarifyResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    # Kept optional at schema level to preserve the established HTTP 400
    # contract; the router provides the field-specific validation message.
    session_id: str = Field(default="", max_length=256)
    clarify_id: str = Field(default="", max_length=256)
    response: str | None = Field(default=None, max_length=100_000)
    answer: str | None = Field(default=None, max_length=100_000)
    choice: str | None = Field(default=None, max_length=100_000)


class ApprovalResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(default="", max_length=256)
    approval_id: str = Field(default="", max_length=256)
    choice: str = Field(default="deny", max_length=32)


class SavedPromptCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    text: str = Field(min_length=1, max_length=8_000)
    label: str = Field(default="", max_length=8_000)


class SavedPromptDelete(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    id: str = Field(min_length=1, max_length=256)


class MemoryWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    section: str = Field(min_length=1, max_length=32)
    content: str = Field(max_length=2_000_000)


class WorkspaceRecord(ExtensibleResponse):
    path: str
    name: str | None = None


class WorkspacesResponse(ExtensibleResponse):
    workspaces: list[WorkspaceRecord | str]
    last: str = ""
    terminal_remote_backend: bool = False


class WorkspaceEntriesResponse(ExtensibleResponse):
    entries: list[dict[str, Any]]
    path: str
    signature: str | None = None


class ChatStart(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)
    message: str = Field(min_length=1, max_length=1_000_000)
    model: str | None = Field(default=None, max_length=512)
    model_provider: str | None = Field(default=None, max_length=128)
    workspace: str | None = Field(default=None, max_length=4096)
    profile: str | None = Field(default=None, max_length=80)

    @field_validator("message")
    @classmethod
    def normalize_message(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("message must not be blank")
        return normalized


class ChatStartResponse(ExtensibleResponse):
    stream_id: str
    session_id: str


class ChatStatusResponse(ExtensibleResponse):
    active: bool
    stream_id: str
    replay_available: bool


class TerminalStart(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)
    rows: int = Field(default=24, ge=8, le=80)
    cols: int = Field(default=80, ge=20, le=240)
    restart: bool = False


class TerminalInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)
    data: str = Field(max_length=8192)


class TerminalClose(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)


class TerminalResize(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    session_id: str = Field(min_length=1, max_length=256)
    rows: int = Field(ge=8, le=80)
    cols: int = Field(ge=20, le=240)


class AdapterHealthRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    state: str
    available: bool
    message: str
    details: dict[str, Any] = Field(default_factory=dict)


class ConnectionRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    kind: str
    selected: bool
    health: AdapterHealthRecord
    capabilities: list[str]


class ConnectionsResponse(BaseModel):
    selected: str
    connections: list[ConnectionRecord]


class ModelRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    label: str
    provider: str | None = None
    connection_id: str | None = None


class ConnectionModelsResponse(BaseModel):
    connection_id: str
    models: list[ModelRecord]


class McpToolsResponse(ExtensibleResponse):
    tools: list[dict[str, Any]]
    total: int
    unavailable_servers: list[str]
