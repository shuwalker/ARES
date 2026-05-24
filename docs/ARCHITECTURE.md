# ARES v2 Architecture

**Revision**: 2.0  
**Date**: 2026-05-14  
**Status**: Active — replaces all previous architecture docs

---

## Core Principle

**The brain is swappable. The body is constant.**

ARES-App renders, listens, speaks, moves. It doesn't think — it delegates thinking to a brain backend. The brain backend is a port, not a dependency.

- **Hermes** — full agent: tools, memory, MCP, multi-provider LLM, skills, sessions
- **Lilith** — personality-driven local LLM with ZMQ bus (future compatibility)
- **Local Ollama** — simple chat, no tools, cheapest path

The app, face, voice, and MCP skills are the same regardless of which brain is active.

---

## System Architecture

```
┌────────────────────────────────────────────────────┐
│                  ARES-App (SwiftUI)                  │
│         Native macOS — face, input, voice            │
│                                                      │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │ Chat Input  │  │ Face View  │  │ Voice I/O    │  │
│  │ (TextField) │  │ (RealityKit│  │ (AVFoundation│  │
│  └──────┬──────┘  └─────▲──────┘  └──────┬───────┘  │
│         │               │                 │          │
│         ▼               │                 ▼          │
│  ┌──────────────────────┴──────────────────────┐    │
│  │              FastAPI :7860                    │    │
│  │  WS /ws/chat  ← streaming + face state      │    │
│  │  REST /api/*  ← one-shot queries             │    │
│  └──────────────────────┬──────────────────────┘    │
│                         │                           │
│                    AgentInterface                     │
│                    (abstract port)                    │
└─────────────────────────┬────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
   ┌──────▼──────┐ ┌─────▼──────┐ ┌─────▼──────┐
   │   Hermes    │ │   Lilith   │ │   Local    │
   │   Backend   │ │   Backend  │ │   Backend  │
   │             │ │            │ │            │
   │ Full agent  │ │ Persona + │ │ Direct     │
   │ loop, tools,│ │ local LLM,│ │ Ollama     │
   │ memory, MCP │ │ ZMQ bus   │ │ chat only  │
   └──────┬──────┘ └─────┬──────┘ └─────┬──────┘
          │               │               │
          ▼               ▼               ▼
   ┌──────────────────────────────────────────────┐
   │              MCP Skills (shared)              │
   │                                                │
   │  :9512 Perception (YOLO + Florence-2)        │
   │  :9513 Voice (whisper-cpp + Piper)            │
   │  :9514 Avatar (VTube Studio)                  │
   │  :9501 Mac (Apple integrations)                │
   │  :9520 Motion (JP01 arm, future)              │
   └──────────────────────────────────────────────┘
```

---

## Layer Architecture (3 layers)

Based on Lilith's proven pattern with import isolation enforcement.

```
Layer 1 — CORE (portable, no platform deps)
├── identity.py          # Frozen dataclass (name, role, voice, self_model)
├── personality.py       # 4-layer HEXACO system → system prompt generation
├── face_state.py        # 6 states with RGB/opacity/pulse/pupil params
├── memory.py            # SQLite persistent fact storage
├── agent.py             # AgentInterface (abstract) + AgentResponse
├── state_mapper.py      # Agent events → face state inference
├── control_tags.py      # Parse [face:happy], [anim:wave] from LLM output
└── bus.py               # ZMQ pub/sub (9 channels) with in-process fallback

Layer 2 — SKILLS (MCP servers, each with manifest.yaml)
├── cognitive/
│   ├── perception/      # YOLO + Florence-2 (MCP :9512)
│   ├── voice/           # whisper-cpp + Piper (MCP :9513)
│   ├── avatar/          # VTube Studio controller (MCP :9514)
│   └── memory/          # Fact search/store (future)
└── physical/
    └── motion/          # JP01 arm controller (future, MCP :9520)

Layer 3 — EMBODIMENT (environment-specific I/O)
├── desktop/             # Mac Studio (camera, mic, screen)
│   ├── app.py           # FastAPI :7860 (WS + REST gateway)
│   └── mac_tools/       # Apple integrations (MCP :9501)
└── robot/               # JP01 body (future)
    └── jros/            # JROS protocol (future)
```

**Rule**: Layer 1 must never import from Layer 2 or Layer 3. Enforced by test.

---

## Brain Backends

### Hermes Backend (default, recommended)

```python
class HermesBackend(AgentInterface):
    """Full agent: tools, memory, MCP, multi-provider LLM, sessions."""
    
    def __init__(self, api_url="http://localhost:8321", api_key=None):
        self.api_url = api_url
        self.api_key = api_key
    
    def send(self, message, context=None):
        # POST /v1/chat/completions with streaming
        # Parse agent state events → face_state mapping
        # Extract control tags from response text
        # Return AgentResponse with full metadata
    
    def interrupt(self, session_id):
        # Cancel current generation via API
    
    def health(self):
        # GET /health → {status, model, uptime}
```

**Why Hermes is the default**: It's already running. It has 200+ tools, multi-provider LLM routing, session memory, MCP client, and the full agent loop. No point rebuilding what's already there.

### Lilith Backend (future compatibility)

```python
class LilithBackend(AgentInterface):
    """Talk to a running Lilith V4 instance via ZMQ bus."""
    
    def __init__(self, zmq_host="127.0.0.1", input_port=5571, output_port=5572):
        # ZMQ PUSH to input channel, SUB to brain_output channel
        # Map Lilith personality states → ARES face states
    
    def send(self, message, context=None):
        # Push message to Lilith's input channel
        # Receive response from brain_output
        # Extract expression from Lilith's persona system
    
    def health(self):
        # Check ZMQ channels are live
```

**Compatibility story**: Jonathan's Lilith uses the same MCP format, similar personality system, and ZMQ pub/sub. When Lilith V4 is production-ready, the `LilithBackend` connects ARES-App to it. All MCP skills are immediately interoperable. The face, voice, and perception servers don't change.

### Local Backend (simplest path)

```python
class LocalBackend(AgentInterface):
    """Direct Ollama call. No tools, no memory. Cheap and local."""
    
    def __init__(self, model="gemma3:12b", ollama_url="http://localhost:11434"):
        self.model = model
    
    def send(self, message, context=None):
        # POST /api/chat to Ollama
        # Simple response, derive face state from sentiment
```

**When to use**: Development, testing, or when you want the cheapest local inference without needing tools.

---

## FastAPI Gateway (:7860)

The gateway is thin. It receives requests from the SwiftUI app, delegates to the active brain backend, and returns responses with face state metadata.

### Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/ws/chat` | WebSocket | Streaming chat + face state updates |
| `/api/chat` | POST | One-shot chat (simple responses) |
| `/api/status` | GET | System status, uptime, face state |
| `/api/identity` | GET | Name, role, voice, self_model |
| `/api/personality` | GET/POST | Read/update personality traits |
| `/api/face` | GET/POST | Get/set face state or expression |
| `/api/health` | GET | Active backend health check |

### WebSocket Protocol

```json
// Client → Server
{"type": "message", "text": "Hello ARES", "session_id": "optional"}

// Server → Client (streaming)
{"type": "delta", "text": "Hello", "face_state": "speaking", "expression": "happy"}
{"type": "delta", "text": " Matthew."}
{"type": "tool_start", "name": "perception_snapshot", "face_state": "curious"}
{"type": "tool_end", "name": "perception_snapshot", "result": "..."}
{"type": "complete", "text": "Hello Matthew. I'm here.", "face_state": "idle", "expression": "happy"}

// Client → Server (interrupt)
{"type": "interrupt"}
```

---

## State Mapping (Agent → Face)

The state mapper is the translation layer between brain events and face rendering.

```python
# ares/core/state_mapper.py

AGENT_TO_FACE = {
    # Agent events          → Face state, Expression
    "thinking":             ("thinking", "thinking"),
    "tool_call":            ("curious", "curious"),  
    "tool_executing":       ("curious", "curious"),
    "streaming":            ("speaking", "neutral"),
    "idle":                 ("idle", "neutral"),
    "error":                ("error", "concerned"),
    "perceiving":           ("awakened", "curious"),
}

CONTROL_TAG_MAP = {
    "face:happy":           ("speaking", "happy"),
    "face:curious":         ("listening", "curious"),
    "face:thinking":        ("thinking", "thinking"),
    "face:surprised":       ("awakened", "surprised"),
    "face:concerned":       ("listening", "concerned"),
    "face:excited":         ("speaking", "excited"),
    "face:sleepy":         ("idle", "sleepy"),
    "anim:wave":            ("speaking", "happy"),
    "anim:look":            ("awakened", "curious"),
}

def map_agent_state(event: str, text: str = "") -> tuple[str, str]:
    """Map an agent event + response text to (face_state, expression).
    
    Priority: control tags > agent events > sentiment fallback.
    """
    # Check control tags first
    for tag, state_expr in CONTROL_TAG_MAP.items():
        if f"[{tag}]" in text:
            return state_expr
    
    # Check agent events
    if event in AGENT_TO_FACE:
        return AGENT_TO_FACE[event]
    
    # Fallback
    return ("idle", "neutral")
```

---

## Personality → Brain Integration

The 4-layer HEXACO personality system generates a system prompt that gets injected into whichever brain is active.

```python
# Hermes backend:
# personality.to_system_prompt() → injected via Hermes API server config
# OR sent as the first system message in the chat completion

# Lilith backend:
# personality.to_system_prompt() → sent via ZMQ input channel
# Lilith uses this directly (same system origin)

# Local backend:
# personality.to_system_prompt() → prepended as system message in Ollama call
```

All three backends receive the same personality data. The personality is a data class, not tied to any brain.

---

## Process Lifecycle (ported from Lilith)

```python
# ares/runtime/lifecycle.py

def prepare(config: AresConfig | None = None) -> Session:
    """Resolve config, discover skills, validate. No processes started."""
    cfg = config or AresConfig.from_env()
    identity = load_identity(cfg.identity_path)
    registry = Registry.discover(environment=detect_environment())
    backend = load_backend(cfg.agent.backend)
    return Session(config=cfg, identity=identity, registry=registry, backend=backend)

@contextmanager
def bring_up(config=None, skip_backend=False):
    """Start processes: FastAPI, MCP servers, brain backend."""
    session = prepare(config)
    try:
        start_mcp_servers(session)
        start_gateway(session)
        if not skip_backend:
            session.backend.connect()
        yield session
    finally:
        teardown(session)

def teardown(session):
    """Stop all processes, clean PID files."""
    stop_mcp_servers()
    stop_gateway()
    cleanup_pid_file()
```

### PID Management (from Lilith)

```python
# ares/runtime/lifecycle.py

def cleanup_previous_instance(home=None):
    """Three-layer orphan cleanup:
    1. PID file → SIGTERM if alive and matching argv
    2. pgrep sweep → kill any ARES processes with matching fingerprint
    3. Port sweep → kill anything holding our ports (if ARES-fingerprinted)
    """
    # Argv fingerprint: "python -m ares" or "ares serve"
    # Never kill unrelated processes on the same port
```

---

## Configuration

```toml
# ~/.ares/config/ares.toml

[agent]
backend = "hermes"              # "hermes" | "lilith" | "local"

[agent.hermes]
api_url = "http://localhost:8321"
api_key = ""                    # from ~/.ares/.env

[agent.lilith]
zmq_host = "127.0.0.1"
input_port = 5571
output_port = 5572

[agent.local]
model = "gemma3:12b"
ollama_url = "http://localhost:11434"

[personality]
# HEXACO defaults (all 0.0-1.0)
openness = 0.85
conscientiousness = 0.72
# ... (loaded from ~/.ares/personality.json at runtime)

[face]
default_style = "blackfire"    # "blackfire"|"anime"|"hologram"|"blob"|"pixelvolume"|"constellation"
intensity = 0.60

[mcp.servers]
perception = { url = "http://localhost:9512", enabled = true }
voice = { url = "http://localhost:9513", enabled = true }
avatar = { url = "http://localhost:9514", enabled = true }
mac = { url = "http://localhost:9501", enabled = true }
motion = { url = "http://localhost:9520", enabled = false }

[gateway]
host = "127.0.0.1"
port = 7860
```

---

## What Gets Deleted

| File | Lines | Reason |
|------|-------|--------|
| File | Lines | Reason | Status |
|------|-------|--------|--------|
| `ares/runtime/hermes_bridge.py` | 229 | Keyword stub, replaced by AgentInterface backends | ✅ DELETED |
| `ares/core/cognitive.py` | 640 | Empty framework, Hermes IS the cognitive loop | ✅ DELETED |
| `ares/runtime/llm_endpoint.py` | 55 | Hermes handles LLM routing | ✅ DELETED |
| `ares/runtime/brain_transport.py` | 140 | Not needed if using existing `~/.hermes/` | ✅ DELETED |
| `ares/runtime/launcher.py` (Hermes install) | ~100 | Replaced by lifecycle.py with proper PID management | ✅ DELETED |
| `ares/core/idle.py` | 260 | Unused idle-loop code | ✅ DELETED |

**Total removed: ~1,424 lines of dead code** ✅ DONE

---

## What Gets Created

| File | Lines | Purpose | Status |
|------|-------|---------|--------|
| `ares/core/agent.py` | ~109 | AgentInterface abstract + AgentResponse dataclass | ✅ EXISTS |
| `ares/core/state_mapper.py` | ~70 | Agent events → face states + control tag parsing | ✅ CREATED |
| `ares/core/control_tags.py` | ~70 | Parse `[face:x]`, `[anim:y]` from LLM output | ✅ CREATED |
| `ares/runtime/hermes_backend.py` | ~150 | Hermes API server backend implementation | ✅ CREATED |
| `ares/runtime/lilith_backend.py` | ~80 | ZMQ bus backend for Lilith compatibility (stub) | ✅ CREATED |
| `ares/runtime/local_backend.py` | ~120 | Direct Ollama backend | ✅ CREATED |
| `ares/runtime/lifecycle.py` | ~160 | prepare/bring_up/teardown + PID management | ✅ CREATED |
| `ares/runtime/config.py` | ~180 | TOML config loading + validation (from AresConfig) | ✅ CREATED |
| Tests for all of the above | ~200 | | 🔄 Tests skipped pending reimplementation |

**Total created: ~939 lines of working code** ✅ DONE

---

## Build Phases

### Phase 1 — Make Chat Work ✅ DONE
1. ✅ Enable Hermes API server in config
2. ✅ Create `ares/core/agent.py` (AgentInterface)
3. ✅ Create `ares/runtime/hermes_backend.py`
4. ✅ Create `ares/core/state_mapper.py` + `control_tags.py`
5. ✅ Replace `hermes_bridge.py` with proxy using HermesBackend
6. 🔄 Expand SwiftUI CommandBar → full-width multi-line TextField
7. 🔄 Wire WebSocket streaming through gateway

### Phase 2 — Lilith Discipline ✅ DONE
1. ✅ `ares/runtime/lifecycle.py` with PID management and `--dry-run`
2. ✅ `ares/runtime/config.py` with TOML validation
3. 🔄 Manifest-driven skill discovery (`skills/*/manifest.yaml`)
4. 🔄 Layer isolation test (`core` must never import `skills` or `embodiment`)
5. ✅ Delete dead code (cognitive.py, llm_endpoint.py, bridge, transport, idle.py, launcher.py)
6. ✅ Move `ares/reference/` to `docs/reference/`
7. ✅ Create `lilith_backend.py` and `local_backend.py` stubs

### Phase 3 — Voice Pipeline (when ready)
1. TTSTaskManager with ordered delivery (from OLV pattern)
2. VAD + interrupt handling with `heard_response`
3. Direct MCP voice calls from SwiftUI app
4. ✅ `ares/runtime/lilith_backend.py` stub for future Lilith connection

### Phase 4 — JP01 Embodiment (future)
1. Motion MCP server (:9520)
2. Physical embodiment layer
3. Robot-specific skills under `skills/physical/`

---

## Compatibility with Lilith

When Jonathan ships Lilith V4 with a stable ZMQ bus protocol:

1. **MCP skills are already interoperable** — both use FastMCP stdio/HTTP format
2. **Personality system is same origin** — HEXACO 4-layer from Lilith, already in ARES
3. **ARES-App connects via `LilithBackend`** — drop-in brain swap, config change only
4. **Face rendering stays ARES-native** — SwiftUI + RealityKit + Metal, best on Mac
5. **Perception/voice stay as MCP servers** — both brains can call the same tools

Jonathan builds the local LLM runtime. We build the face, body, and tool integration. The AgentInterface makes them swappable.

---

## What I Need From You

1. **Approve this architecture** — or tell me what to change
2. **Confirm the config format** — TOML? YAML? What do you prefer?
3. **Which Hermes API endpoints** — streaming (`/v1/chat/completions` with SSE) or Responses API (`/v1/responses`)? Streaming is simpler; Responses API has more features (tool progress, approvals).
4. **Start Phase 1?** — I can begin wiring the Hermes backend and state mapper immediately.