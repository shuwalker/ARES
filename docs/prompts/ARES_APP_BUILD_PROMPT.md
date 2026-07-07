# ARES App — Claude Code Build Prompt

## Who You Are Building For

Matthew Jenkins — founder of Jenkins Robotics. Propulsion engineer. Building a consumer
personal AI OS product called ARES. Direct, no fluff. Ship the right thing the first time.
Do not do the easy thing. Do the right thing. Read context before acting. Verify after.

---

## What ARES Is

ARES is a personal AI operating system — always-on, multi-device — that gives Matthew a
persistent AI presence across every screen. The AI brain is **Hermes Agent**
(NousResearch/hermes-agent), running as a persistent daemon on a Mac Studio. ARES is the
client layer — the dashboard, the avatar, the domain tools — all talking to that brain.

ARES is NOT:
- A chatbot wrapper
- A standalone Electron app that runs its own LLM
- A fork of hermes-workspace
- Claude or any specific LLM (model is configurable, routes through Hermes)

ARES IS:
- A three-mode application: **Dashboard** (hermes-workspace style control panel) +
  **Presence** (animated VTuber-style avatar with voice) + **Tools** (domain panels)
- Built on two existing open-source repos: `hermes-desktop` (Swift, dashboard shell) and
  `Open-LLM-VTuber` (Python, avatar + voice pipeline), extended and integrated
- The avatar and voice layer is driven by `Open-LLM-VTuber` + `airi` (character system)
- The character persona system comes from `airi`'s CCC card format + expression pipeline
- The dashboard/control panel is `hermes-desktop` extended with an HTTP transport to Hermes
- iOS is a native SwiftUI companion app sharing the dashboard's model layer

---

## Repository Structure (~/Documents/GitHub/)

### Core ARES repos (primary work targets)

```
hermes-desktop/        ← Swift macOS dashboard shell (base for ARES dashboard mode)
Open-LLM-VTuber/       ← Python VTuber server (avatar + voice pipeline)
airi/                  ← TypeScript character system (persona cards, VRM/Live2D renderer)
ARES-Autonomous-Reasoning-Execution-System/  ← Existing ARES Python daemon (reference)
hermes-workspace/      ← Web dashboard reference (do not copy 1:1, use as reference)
hermes-agent/          ← Hermes source reference ONLY (do not run, do not modify)
```

### Supporting tools (already built, integrate as-needed)

```
GPT-SoVITS/      ← Voice cloning / TTS (use with Open-LLM-VTuber TTS pipeline)
ComfyUI/         ← Image generation (already at ~/Documents/ComfyUI)
Open-Sora/       ← AI video generation
n8n/             ← Workflow automation (YouTube pipeline orchestration)
obsidian-importer/ ← Second brain tooling
repomix/           ← Codebase bundling tool
```

### Hardware tools (leave alone)

```
OrcaSlicer-bambulab/  ← 3D printing
seestar-s50/          ← Telescope control
seestar_alp/          ← Telescope alt
GraXpert/             ← Astrophotography
```

### Reference only

```
os1/           ← OS1 AI companion reference (study patterns)
Agent-S/       ← Agent computer use reference
aiavatarkit/   ← Avatar animation kit reference
```

**Organize into:**

```
~/Documents/GitHub/
  ares/        ← hermes-desktop, Open-LLM-VTuber, airi, ARES-*
  generation/  ← GPT-SoVITS, ComfyUI, Open-Sora
  reference/   ← os1, Agent-S, aiavatarkit, hermes-agent, hermes-workspace
  hardware/    ← OrcaSlicer, seestar*, GraXpert
  tools/       ← n8n, repomix, obsidian-importer
  archive/     ← Everything else pending audit
```

---

## Hermes Agent — How It Works (CRITICAL — Read This)

**The live Hermes install is at `~/.hermes/` — do NOT touch this.**
**The GitHub clone at `~/Documents/GitHub/hermes-agent/` is reference source only.**

Hermes Agent runs as a gateway daemon. It exposes:
- **WebSocket gateway** on port 8644 (Discord/webhook messaging)
- **HTTP API** on port 8642 (requires `API_SERVER_ENABLED=true` in `~/.hermes/.env`)
- **OpenAI-compatible API** on port 8642 at `/v1` — use this for Open-LLM-VTuber
- **Dashboard** on port 9119
- **Config** at `~/.hermes/config.yaml`
- **Profiles** at `~/.hermes/profiles/<name>/config.yaml`

**Before calling any Hermes API endpoint, verify it exists in:**
`~/Documents/GitHub/hermes-agent/docs/` or by reading the gateway source.
Never hallucinate endpoint paths.

---

## The Three-Mode Architecture

ARES is one product with three modes. They coexist — switching modes doesn't close other
panels. Think of it like a desktop workspace, not a single-window app.

### Mode 1: Dashboard

The control panel. Based on `hermes-desktop` (Swift, macOS) extended with a local HTTP
transport to Hermes port 8642 alongside the existing SSH transport.

`hermes-desktop` already has (read the source before touching it):
- Full Swift app shell with sidebar + split-view layout
- 10 sections: Connections, Overview, Files, Sessions, Workflows, Cron Jobs, Kanban,
  Usage, Skills, Terminal
- SSH-based service layer (`SSHTransport`) that runs Python scripts on the remote host
- Complete model layer: Sessions, Messages, Kanban, Skills, CronJobs, Usage, FileEditor
- Internal design system (`HermesUI.swift` — `HermesTheme`, `HermesPageContainer`,
  `HermesCollapsibleHSplitView`, `HermesBadge`, etc.)
- macOS 14+, Swift 6, SwiftTerm embedded, SPM, no third-party UI dependencies

**What needs to be added to hermes-desktop:**
1. `HTTPTransport` class (parallel to `SSHTransport`) — talks to Hermes port 8642 directly
2. `TransportKind` enum on `ConnectionProfile` — `.ssh` for remote, `.local` for HTTP
3. `WebSocketTransport` for streaming chat responses (token-by-token via port 8642 `/ws`)
4. New `ConnectionProfile` fields: `httpBaseURL`, `wsBaseURL`, `apiKey` (from `~/.hermes/.env`)
5. Rebranding: replace "Hermes Desktop" identity with ARES identity throughout
6. Avatar panel placeholder in the split layout (three-column layout for: sidebar, dashboard
   content, avatar/tools panel) — `HermesThreeColumnSplitView` (does not exist yet)

**What NOT to change in hermes-desktop:**
- The SSH transport — keep it. MacBook → Mac Studio remote connection still uses SSH.
- The existing model layer — it's complete and well-structured.
- The existing views — they work. Extend, don't rewrite.
- The design system (`HermesUI.swift`) — extend it, don't replace it.

### Mode 2: Presence (Avatar)

The ambient AI face. Based on `Open-LLM-VTuber` with Hermes as the LLM backend.

`Open-LLM-VTuber` already has (read the source before touching it):
- Python FastAPI + WebSocket server (default port 12393, configurable)
- Full voice pipeline: VAD (Silero) → ASR (Whisper, many options) → LLM → TTS (many options)
- Live2D avatar rendering in a browser/Electron frontend (Vue 3 SPA)
- Desktop pet mode (transparent frameless always-on-top window)
- Pluggable LLM backend via `StatelessLLMInterface` + `AgentInterface` ABCs
- `openai_compatible_llm` provider already supports any OpenAI-compatible API via base_url
- Emotion/expression system: LLM emits `[emotion]` tokens → `actions_extractor` →
  expression index → `audio` WebSocket message → Live2D frontend drives expressions
- Full WebSocket protocol (see ARES_CODEBASE_AUDIT.md for complete message reference)
- Character config via `conf.yaml` (character name, persona prompt, model, ASR, TTS, VAD)
- Hot-switch between character configs at runtime (`switch-config` WebSocket message)
- MCP server support (`mcp_servers.json`)

**What needs to be configured in Open-LLM-VTuber to use Hermes:**

In `conf.yaml`:
```yaml
character_config:
  agent_config:
    conversation_agent_choice: 'basic_memory_agent'
    agent_settings:
      basic_memory_agent:
        llm_provider: 'openai_compatible_llm'
        faster_first_response: True
        segment_method: 'pysbd'
        use_mcpp: False
    llm_configs:
      openai_compatible_llm:
        base_url: 'http://localhost:8642/v1'
        llm_api_key: 'Bearer <API_SERVER_KEY from ~/.hermes/.env>'
        model: 'hermes-3'
        temperature: 1.0
        interrupt_method: 'user'
```

No code changes needed for the basic Hermes LLM integration — it's a config change only.

**What needs to be built on top of Open-LLM-VTuber:**
1. Character profiles for Hermes personas — create `characters/ares.yaml` and character
   YAML files for each personality (the emotion maps need to match the Live2D model's
   `emotionMap` in `model_dict.json`)
2. Wake word integration — `wakeword.py` (see Lilith-AI patterns) feeding `text-input`
   WebSocket messages
3. ARES-branded character config with Matthew's preferred TTS voice (GPT-SoVITS)
4. macOS LaunchDaemon plist for auto-start at login

**The avatar WebSocket protocol (critical — do not hallucinate):**

The frontend connects to `ws://localhost:12393/client-ws`. On connect the server sends:
`full-text` → `set-model-and-conf` → `group-update` → `control/start-mic`

Each conversation turn: `control/conversation-chain-start` → one or more `audio` messages
(base64 WAV + volume array + display_text + actions.expressions) → `backend-synth-complete`
→ frontend sends `frontend-playback-complete` → `force-new-message` → `control/conversation-chain-end`

Audio payload format:
```json
{
  "type": "audio",
  "audio": "<base64-wav>",
  "volumes": [0.1, 0.3, ...],
  "slice_length": 20,
  "display_text": {"text": "...", "name": "ARES", "avatar": "ares.png"},
  "actions": {"expressions": [3]},
  "forwarded": false
}
```

### Mode 3: Domain Tools

Custom panels spawned alongside Dashboard or Presence. These are first-class views,
not browser tabs. Each tool panel talks to Hermes skills directly via port 8642.

Initial tool panels to build:
- **Second Brain Explorer** — semantic search over LanceDB, results rendered as a graph
  or list, feeds context into the active Hermes session
- **Physics Simulation Panel** — TBD by Matthew (what tool/library drives this?)
- **YouTube Pipeline Queue** — approval UI for staged videos (script → thumbnail → audio)
- **Engineering Calculator** — propulsion-specific: thrust, ISP, propellant mass fraction

Tool panels are Electron or native SwiftUI panels, not embedded webviews.

---

## Character / Persona System

Persona system comes from `airi` (TypeScript monorepo, `~/Documents/GitHub/airi/`).

`airi` already has:
- **CCC card format** (`@proj-airi/ccc`) — Character Card Spec v3, stores persona in PNG
  metadata or JSON. Fields: `name`, `personality`, `scenario`, `systemPrompt`, `greetings`,
  `messageExample` (few-shot), `tags`, `extensions`
- **Emotion system** — `Emotion` enum with `Happy`, `Sad`, `Angry`, `Surprised`, `Neutral`,
  `Think`, `Curious`. Maps to VRM blendshape names or Live2D expression indices.
- **VRM renderer** (`stage-ui-three`) — Three.js + @pixiv/three-vrm, expression transitions
  with lerp blending, lip sync via wLipSync (WASM), eye tracking, idle animations
- **Live2D renderer** (`stage-ui-live2d`) — PixiJS + pixi-live2d-display, expression
  controller, motion manager, lip sync
- **`streamFrom()` LLM runtime** (`core-agent`) — OpenAI-compatible streaming, tool calling,
  auto-degrade for provider quirks — portable, no DOM dependency
- **WebSocket server protocol** (`server-runtime`) — typed event bus (`ProtocolEvents`) for
  inter-module communication; language-agnostic over WebSocket

**How to integrate airi's character system with Open-LLM-VTuber + Hermes:**

The character persona (CCC card) feeds the system prompt. The key integration is at the
emotion layer — both `airi` and Open-LLM-VTuber use inline `[emotion]` tokens in LLM
output to drive avatar expressions. The emotion key names just need to match the Live2D
model's `emotionMap` in `model_dict.json`.

For Hermes to output the right emotion tokens, the system prompt (from the CCC card) must
instruct the model to use those specific token names. The `live2d_expression_prompt` in
Open-LLM-VTuber does this automatically — it injects the full emotion key list.

**Character profiles to create first (port from Lilith-AI patterns):**
- `ares.yaml` — default: direct, technical, propulsion domain knowledge
- `visionary.yaml` — ruthless clarity, systems thinking, strategic
- `mentor.yaml` — behavioral science, coaching, warm but honest

The HEXACO/SPECIAL numeric slider system from Lilith-AI is the mechanism for making these
profiles feel distinct. Each profile sets numeric trait values that get injected into the
system prompt deterministically. Build this as a character config extension in conf.yaml.

---

## iOS App — Build Spec

Native SwiftUI. Connects to Mac Studio over Tailscale. Shares model layer with macOS.

```
AresIOS (SwiftUI, iOS 17+, iPadOS 17+)
├── Shared/
│   ├── HermesHTTPClient.swift    ← Port 8642 HTTP client (shared with macOS)
│   ├── HermesWSClient.swift      ← WebSocket streaming (shared with macOS)
│   ├── SessionModels.swift       ← Port from hermes-desktop model layer
│   ├── KanbanModels.swift        ← Port from hermes-desktop model layer
│   └── ChatView.swift            ← Conversation UI (shared)
├── iOS/
│   ├── TodayView.swift           ← Agenda + reminders + active tasks
│   ├── VoiceInputView.swift      ← Voice-first interface
│   ├── NotificationHandler.swift ← APNS push from Hermes
│   └── ConnectionManager.swift   ← Tailscale IP discovery
└── Widget/
    └── AresWidget.swift          ← Home screen widget (next task + agent status)
```

---

## Apple MCP Server — Build Spec

Swift LaunchDaemon on port 9515. Gives Hermes access to Apple apps.

```swift
// MCP tools to expose:
calendar_list_events(range: DateRange) -> [Event]
calendar_create_event(title: String, date: Date, ...) -> Event
reminders_list(list: String?) -> [Reminder]
reminders_create(title: String, due: Date?, list: String) -> Reminder
notes_list(folder: String?) -> [Note]
notes_create(title: String, body: String, folder: String) -> Note
notes_search(query: String) -> [Note]
mail_list_unread(account: String?, limit: Int) -> [Message]
mail_send(to: String, subject: String, body: String) -> Bool
messages_send(to: String, body: String) -> Bool
```

All via EventKit, CloudKit, and osascript where needed.
Add to `~/.hermes/config.yaml` under `mcp.servers` after building.

---

## YouTube Automation Pipeline — Build Spec

Hermes manages, n8n executes. Human approves before publish.

```
Hermes (orchestrator)
  → Generates script, title, description, tags
  → Creates n8n workflow via n8n API
  → n8n workflow:
      1. Trigger: new script approved in ~/Documents/YouTube/Intake/
      2. Run ComfyUI for thumbnail generation
      3. Run GPT-SoVITS for AI voiceover (or flag for Matthew's voice)
      4. Notify Matthew for final approval (ARES iOS push notification)
      5. Upload to YouTube via Data API v3
      6. Schedule + set metadata
  → Hermes monitors n8n for completion, logs to NAS
```

n8n runs at `localhost:5678`. Matthew approves via ARES iOS app notification.

---

## Second Brain Integration

LanceDB vector index at `~/.hermes/second_brain_lancedb/`
Embedding model: `nomic-embed-text` via local Ollama
8,600 files indexed across NAS volumes

```bash
# Every 6 hours — incremental reindex
python3 ~/.hermes/scripts/second_brain_indexer.py --incremental

# Every morning 6am — semantic search health check
python3 ~/.hermes/scripts/second_brain_indexer.py --query "active projects" --top 5
```

Hermes runs a semantic search before any task involving files, projects, or knowledge.
This is enforced in the `pre-task` hook.

---

## What To Build First (Priority Order)

### Phase 1 — Foundation

1. **Organize GitHub folder** per the structure above
2. **Enable Hermes HTTP API** — add `API_SERVER_ENABLED=true` to `~/.hermes/.env`,
   restart gateway. Verify port 8642 responds at `/v1/models` or equivalent.
3. **Wire LanceDB cron** — second brain indexer on 6-hour schedule via `hermes cron`
4. **Wire Open-LLM-VTuber to Hermes** — configure `conf.yaml` with Hermes as LLM backend,
   create `characters/ares.yaml`, verify avatar speaks through Hermes

### Phase 2 — Dashboard (hermes-desktop extensions)

5. **HTTPTransport.swift** — HTTP client for port 8642 (parallel to SSHTransport)
6. **WebSocketTransport.swift** — streaming chat via port 8642 `/ws`
7. **ConnectionProfile extensions** — `transportKind`, `httpBaseURL`, `apiKey`
8. **Local connection flow** — when transport is `.local`, skip SSH entirely
9. **ARES branding pass** — rename app, update design system colors, replace Hermes Desktop
   identity with ARES identity

### Phase 3 — Avatar Integration

10. **Character config files** — `characters/ares.yaml`, persona prompts, emotion map tuned
    to chosen Live2D model
11. **Wake word** — `hey ares` trigger feeding Open-LLM-VTuber `text-input` WebSocket
12. **GPT-SoVITS TTS** — configure as TTS engine in Open-LLM-VTuber
13. **Desktop pet mode** — verify always-on-top transparent window works on macOS Sequoia
14. **LaunchDaemon** — `com.ares.vtuber.plist` auto-starts Open-LLM-VTuber at login

### Phase 4 — Apple Integration

15. **Apple MCP server** — Swift daemon, EventKit + osascript, port 9515
16. **Add to Hermes config** — `mcp.servers.apple-native: {url: localhost:9515}`
17. **Calendar/Reminders in Dashboard** — Today view in hermes-desktop Overview section

### Phase 5 — iOS

18. **Shared Swift package** — extract HermesHTTPClient + core models
19. **ARES iOS app** — TodayView, chat, voice input, Tailscale connection
20. **Home screen widget** — next task + agent status

### Phase 6 — Domain Tools

21. **Second Brain Explorer panel** — LanceDB search UI embedded in Dashboard
22. **Physics simulation panel** — TBD (confirm tool/library with Matthew first)
23. **YouTube Pipeline Queue** — approval UI, triggers n8n workflow

### Phase 7 — YouTube Pipeline

24. **n8n instance** — configure, expose via Tailscale
25. **YouTube workflow** — script → thumbnail → voiceover → approval → publish

---

## Conventions and Standards

### hermes-desktop code conventions (match exactly)
- Swift 6, async/await everywhere, `@MainActor` for UI state, `@unchecked Sendable` for services
- Structured concurrency — actors for shared state
- SwiftUI throughout — no UIKit unless forced by system API
- No third-party UI dependencies — use Apple frameworks + the existing HermesUI design system
- All persistence via `ConnectionStore` pattern (JSON files at `~/Library/Application Support/`)
- SSH control socket path derived from SHA256 of workspace fingerprint — follow this pattern
- Python scripts embedded as strings in Swift via `RemotePythonScript.wrap()` — follow this pattern for any new SSH-based data fetching

### Open-LLM-VTuber code conventions (match exactly)
- Python 3.11+, async/await, loguru for logging
- Pydantic v2 models for all config (`config_manager/` pattern)
- Factory pattern for all pluggable components (ASR, TTS, VAD, agent, LLM)
- WebSocket handler routes by `message["type"]` string — add new routes in `websocket_handler.py`
- New LLM providers: implement `StatelessLLMInterface` or add to `LLMFactory`
- New agent types: implement `AgentInterface` and register in `AgentFactory`

### Hermes integration rules
- NEVER modify `~/.hermes/config.yaml` programmatically without reading it first
- NEVER write to `~/.hermes/memories/` — Hermes owns that
- ALWAYS use the HTTP API (port 8642) for app→Hermes communication
- WebSocket on port 8642 `/ws` for streaming responses
- Auth token from `~/.hermes/.env` → `API_SERVER_KEY`
- Open-LLM-VTuber connects to Hermes as `openai_compatible_llm` with `base_url: http://localhost:8642/v1`

### File naming
- Swift: PascalCase files, matching type name
- New skills: `~/.hermes/skills/<category>/<name>/SKILL.md` + supporting files
- Second brain files: Denote style `YYYY-MM-DD--slug--tag1_tag2.md`
- Character configs: `characters/<name>.yaml` in Open-LLM-VTuber root

---

## Context Files To Read Before Starting Any Task

```
~/.hermes/SOUL.md                    ← Hermes identity and behavioral rules
~/.hermes/AGENTS.md                  ← Operational rules
~/.hermes/memories/MEMORY.md         ← Current project state
~/.hermes/MASTER_TODO.md             ← Active task list
~/.hermes/NAS_STRUCTURE.md           ← Storage layout
~/Documents/ARES_CODEBASE_AUDIT.md   ← Full audit of all three repos (read this first)
~/Documents/GitHub/hermes-desktop/Sources/HermesDesktop/Services/SSH/SSHTransport.swift
~/Documents/GitHub/hermes-desktop/Sources/HermesDesktop/App/AppState.swift
~/Documents/GitHub/Open-LLM-VTuber/src/open_llm_vtuber/server.py
~/Documents/GitHub/Open-LLM-VTuber/src/open_llm_vtuber/websocket_handler.py
~/Documents/GitHub/Open-LLM-VTuber/src/open_llm_vtuber/agent/agents/agent_interface.py
~/Documents/GitHub/Open-LLM-VTuber/conf.yaml
~/Documents/GitHub/hermes-agent/docs/ (API reference — verify endpoints before calling)
```

---

## What You Are NOT Doing

- Do not fork or modify `hermes-agent` source — it auto-updates, treat it as a dependency
- Do not rewrite hermes-desktop from scratch — extend it, the foundation is solid
- Do not rewrite Open-LLM-VTuber from scratch — configure it, then extend
- Do not use React Native or Flutter — native Swift for iOS/macOS
- Do not build another full web dashboard — hermes-desktop is the dashboard shell
- Do not hardcode model names — all model config lives in `~/.hermes/config.yaml`
- Do not store secrets in code — all credentials in `~/.hermes/.env`
- Do not add domain tool panels before Dashboard + Presence modes work end-to-end
- Do not touch `~/.hermes/` directly — only read config files, never write to memories/
