# ARES Worker Adapter Contract

## ReasoningProvider Protocol

All workers must be accessed through a common interface. No provider-specific code outside the adapter.

```python
from typing import Protocol, Any

class ReasoningProvider(Protocol):
    """The contract every worker adapter must implement."""
    
    # Identity
    worker_id: str          # e.g. "claude-code", "ollama-llama3"
    provider: str           # e.g. "anthropic", "local"
    capabilities: list[str] # e.g. ["code_generation", "reasoning", "research"]
    data_location: str      # "local" | "cloud"
    privacy_class: str      # "local_only" | "external_provider" | "approved_provider"
    context_limit: int | None  # max tokens, None = unlimited
    
    # Execution
    async def generate(self, briefing: ContextBriefing, message: str) -> WorkerResult:
        """Execute a task with the given briefing and user message."""
        ...
    
    # Capability declaration
    def supports_streaming(self) -> bool: ...
    def supports_files(self) -> bool: ...
    def supports_images(self) -> bool: ...
    def supports_tools(self, tool_ids: list[str]) -> bool: ...
    
    # Health
    async def check_availability(self) -> AvailabilityStatus: ...
    def estimated_cost(self, tokens: int) -> CostEstimate: ...
    def estimated_latency(self) -> LatencyProfile: ...
```

## ContextBriefing (what the SI sends to workers)

```python
@dataclass
class ContextBriefing:
    """The filtered, budgeted context that the SI sends to a worker."""
    
    si_identity: SIIdentity          # Who the SI is (name, principles)
    user_context: list[ContextItem]  # Relevant user preferences (filtered)
    project_context: list[ContextItem]  # Relevant project info (filtered)
    recent_conversation: list[Message]  # Recent turns (filtered, budgeted)
    relevant_memories: list[MemoryItem]  # Journal search results (filtered)
    constraints: list[Constraint]    # What the worker must/must not do
    privacy_policy: PrivacyPolicy   # What data the worker may retain
    tools: list[ToolDescription]    # Available tools for this task
    output_requirements: OutputSpec # Format, length, style requirements
    context_manifest: list[ManifestEntry]  # What was included/excluded/redacted
```

## WorkerResult (what workers return)

```python
@dataclass
class WorkerResult:
    """Structured result from a worker."""
    
    worker_id: str
    content: str                    # The response text/code
    artifacts: list[Artifact]       # Files, images, data produced
    tool_calls: list[ToolCall]      # Tools the worker wants to invoke
    confidence: float | None        # Worker's self-assessed confidence (0-1)
    cost: CostReport                # Tokens used, estimated cost
    metadata: dict[str, Any]        # Worker-specific metadata
    verification_evidence: list[str]  # Evidence the worker provides for verification
```

## CostEstimate

```python
@dataclass
class CostEstimate:
    input_cost_per_1k: float      # USD per 1K input tokens
    output_cost_per_1k: float     # USD per 1K output tokens
    flat_cost: float              # Any flat per-request cost
    currency: str = "USD"
```

## LatencyProfile

```python
@dataclass
class LatencyProfile:
    average_response_ms: int      # Typical response time
    first_token_ms: int          # Time to first token (streaming)
    p95_response_ms: int         # 95th percentile response time
```

## Adapter Registration

```python
# In the worker registry
ADAPTERS: dict[str, ReasoningProvider] = {
    "hermes_local": HermesAdapter(),
    "claude_local": ClaudeAdapter(),
    "codex_local": CodexAdapter(),
    "gemini_local": GeminiAdapter(),
    "grok_local": GrokAdapter(),
    "ollama_local": OllamaAdapter(),
    # Future adapters register here
}
```

## Inventory catalog (models · transports · gateways · MCP)

Adapters must **catalog** everything the framework can expose — not only the
path ARES uses today. Latency and quality depend on the **LLM configuration
inside the worker** (local vs cloud model, load, tools), not only the socket
ARES opens.

```python
def inventory(self) -> dict:
    """schema_version 1 — see api/backends/catalog.py"""
    return {
        "worker_id": "hermes_local",
        "display_name": "Hermes Agent",
        "models": [
            # location: local | cloud | unknown; in_use marks active config
            {"id": "…", "location": "cloud", "provider": "ollama-cloud", "in_use": True},
            {"id": "…", "location": "local", "provider": "ollama", "in_use": False},
        ],
        "transports": [
            # kind: cli | http_gateway | mcp | subprocess | other
            {"id": "cli_chat", "kind": "cli", "in_use": True},
            {"id": "mcp_serve", "kind": "mcp", "in_use": False},
        ],
        "gateways": [
            {"id": "…", "kind": "openai_compatible", "endpoint": "http://…", "in_use": False},
        ],
        "mcp": [
            # Declare MCP servers/tools even when ARES is not the MCP client
            {"id": "hermes_mcp_serve", "in_use_by_ares": False, "used_by": ["claude_code"]},
        ],
        "latency": {
            "depends_on": ["selected_model", "provider_location", "transport", "tool_use"],
            "note": "Wall time dominated by model/provider, not transport alone.",
        },
        "active_execution": {"transport": "cli_chat", "model": "…", "provider": "…"},
    }
```

| Framework (today) | Active ARES transport | Also catalogued |
|-------------------|----------------------|-----------------|
| Hermes | CLI `hermes chat -q` | MCP serve, hermes-webui gateway, multi providers |
| JaegerAI / JROS | HTTP gateway `:8643` | Local checkout fallback, native app, optional MCP |

Exposed on `GET /api/backends` as `inventory` per backend.

## Current State vs Target

| Aspect | Current | Target |
|--------|---------|--------|
| Backend interface | Each backend is a standalone module (`hermes.py`, `jros.py`, etc.) | Common `ReasoningProvider` protocol |
| Adapter registration | Hardcoded in `ai_framework_discovery.py` | Data-driven registry with capabilities |
| Context sent to worker | Full conversation history + identity prompt | `ContextBriefing` with manifest and privacy policy |
| Worker result | Raw streamed text | `WorkerResult` with confidence, cost, evidence |
| Provider switching | User manually picks from model picker | SI routes based on capability + privacy + cost |
| Capability catalog | Hermes/JROS inventory on `/api/backends` | All adapters fill inventory; SI routes on it |