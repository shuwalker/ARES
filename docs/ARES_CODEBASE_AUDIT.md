# ARES Codebase Audit
## What exists, what's reusable, what needs to be built

Generated after deep read of: `hermes-desktop`, `Open-LLM-VTuber`, `airi`

---

## 1. hermes-desktop (Swift, macOS)

**Role in ARES:** Dashboard mode shell. Already built — extend it, don't rewrite.

**Location:** `~/Documents/GitHub/hermes-desktop/`
**Build system:** Swift Package Manager, Swift 6, macOS 14+
**External deps:** SwiftTerm (local vendor), Foundation URLSession (GitHub update check only)

### What it already has

**App shell:**
- `HermesDesktopApp.swift` — `@main` entry point, single `AppState` state object
- `RootView.swift` — sidebar (160–220pt) + detail split, 10 sections, toolbar
- `HermesDesktopCommands.swift` — menu commands, keyboard shortcuts (⌘1–⌘0 sections)
- `HermesApplicationDelegate.swift` — NSApp setup, no window tabbing

**Transport (SSH only — needs HTTP added):**
- `SSHTransport.swift` — ALL data flows through `/usr/bin/ssh` as subprocess
  - `execute(on:remoteCommand:)` — raw SSH command
  - `executeJSON<T>(on:pythonScript:responseType:)` — runs Python via SSH stdin, returns JSON
  - Connection multiplexing via ControlMaster/ControlPersist/ControlPath
  - Error handling: maps SSH stderr to user-friendly messages
  - `FoundationSSHProcessRunner` — async Foundation.Process wrapper with NSLock
- **There is zero HTTP or WebSocket transport.** `URLSession` is used only for the GitHub release check.

**Service layer (all SSH-backed):**
- `RemoteHermesService` — discovery: reads ~/.hermes structure, returns `RemoteDiscovery`
- `SessionBrowserService` — list/detail/delete sessions (SQLite + JSONL fallback)
- `HermesChatService` — sends message by running `hermes chat --quiet` over SSH, 30-min timeout
- `KanbanBrowserService` — full CRUD for kanban (2,500 lines of embedded Python)
- `SkillBrowserService` — list/detail/create/edit/delete skills
- `CronBrowserService` — list/pause/resume/delete/create/run cron jobs
- `UsageBrowserService` — token usage aggregation from SQLite
- `FileEditorService` — read/write/browse remote files
- `UpdateCheckService` — GitHub Releases API via URLSession (only non-SSH call)

**Model layer (complete and well-structured):**
- `ConnectionProfile` — SSH host/alias/port/user, profile, custom home path
- `SessionSummary`, `SessionMessage`, `SessionMessageDisplay` — rich session models
- `SessionToolMessageSummary` — understands tool turn JSON, extracts title/status/preview
- `KanbanProject`, `KanbanBoard`, `KanbanTask`, `KanbanTaskDetail` — full kanban model
- `SkillSummary`, `SkillDetail`, `SkillDraft` — skill catalog model
- `CronJob`, `CronJobDraft`, `CronScheduleDraft`, `CronScheduleFormatter` — cron model
- `UsageSummary`, `UsageTopModel`, `UsageProfileBreakdown` — usage stats
- `RemoteDiscovery` — remote workspace structure discovery result
- `WorkflowPreset` — locally-persisted prompts + skill selections for quick launch

**Views (complete, functional):**
- `OverviewView` — three-column responsive dashboard (host, workspace, status, files, kanban)
- `SessionsView` + `SessionDetailView` — full transcript browser + composer
- `KanbanView` — board picker, task list, full task detail, CRUD operations
- `SkillsView` — catalog, SKILL.md viewer/editor
- `CronJobsView` — list, schedule picker, full editor
- `WorkflowsView` — saved workflow presets, terminal launch
- `FilesView` — remote file editor with conflict detection
- `UsageView` — charts (SwiftUI Charts), token stats, cost estimates
- `TerminalWorkspaceView` — multi-tab SSH terminal (SwiftTerm)

**Design system (`HermesUI.swift` — use this, don't replace):**
- `HermesTheme` — colors, corner radii
- `HermesPageContainer` — scroll + max-width wrapper
- `HermesCollapsibleHSplitView` — two-pane collapsible split (extend to three-pane)
- `HermesSurfacePanel`, `HermesPageHeader`, `HermesBadge`, `HermesWrappingFlowLayout`
- `HermesExpandableSearchField`, `HermesToolbarControlCluster`

**Persistence:**
- `ConnectionStore` — JSON files at `~/Library/Application Support/HermesDesktop/`
  Stores: connections, preferences, terminal theme, file bookmarks, pinned sessions, workflow presets
- `AppPaths` — SSH control socket paths derived from SHA256 of workspace fingerprint

**Terminal:**
- `TerminalSession` — wraps SwiftTerm `MacLocalTerminalView` as AppKit NSView
- `TerminalWorkspaceStore` — manages multiple terminal tabs
- `TerminalViewHost` — AppKit/SwiftUI bridge for SwiftTerm

### What's missing (must build)

**For local HTTP transport to Hermes port 8642:**
```swift
// New files needed:
HTTPTransport.swift         // URLSession HTTP client, mirrors SSHTransport API
WebSocketTransport.swift    // URLSessionWebSocketTask for streaming chat tokens
```
- `ConnectionProfile` needs `transportKind: TransportKind` (`.ssh` | `.local`)
- `.local` profiles need: `httpBaseURL: String`, `apiKey: String` (no SSH fields)
- All services need to accept either transport (protocol abstraction or dual implementation)
- `HermesChatService` needs complete rewrite for streaming — current version waits for
  full SSH process exit; WebSocket version streams token-by-token
- `AppState.init` hardcodes `SSHTransport` — needs factory or injection point

**For three-panel layout (Dashboard + Avatar panel + Tools panel):**
- `HermesThreeColumnSplitView` — doesn't exist, needs to be built
- Avatar panel view — no `AvatarView` or presence widget exists anywhere
- Tool panel container — no right-side tools panel exists
- `AppState` needs published properties for avatar status, quick-tool state, WebSocket push events

**For ARES branding:**
- App name, bundle ID, icon — all currently "HermesDesktop"
- `TerminalThemePreference` — 6 built-in themes (Graphite, Evergreen, Dusk, Paper, Aubergine, Porcelain) — add ARES-themed default

---

## 2. Open-LLM-VTuber (Python, avatar + voice)

**Role in ARES:** Presence mode engine. Already built — configure it, then extend.

**Location:** `~/Documents/GitHub/Open-LLM-VTuber/`
**Stack:** Python 3.11+, FastAPI, uvicorn, WebSocket, uv for deps
**Frontend:** Vue 3 SPA (compiled, in `frontend/` as git submodule)

### What it already has

**Server:**
- `server.py` — `WebSocketServer`, FastAPI app, static mounts, CORS
  - Mounts: `/cache`, `/live2d-models`, `/bg`, `/avatars`, `/web-tool`, `/` (SPA)
  - Routes: `/client-ws` (main WS), `/proxy-ws` (optional relay), `/live2d-models/info` (GET), `/asr` (POST), `/tts-ws` (WS)
- `routes.py` — endpoint registration
- `websocket_handler.py` — `WebSocketHandler`, `MessageType` enum, full message routing

**WebSocket protocol (complete, do not break):**

Server → Client:
- `full-text` — status/thinking text
- `set-model-and-conf` — initialize Live2D model + character on connect
- `control` — commands: `start-mic`, `conversation-chain-start`, `conversation-chain-end`, `interrupt`
- `audio` — audio payload (base64 WAV + volume array + display_text + actions.expressions)
- `user-input-transcription` — transcribed user speech text
- `backend-synth-complete` — all TTS generated, wait for playback
- `force-new-message` — force new chat bubble
- `group-update`, `history-list`, `history-data`, `tool_call_status`, `error`

Client → Server:
- `mic-audio-data` — float32 audio chunks (16kHz)
- `raw-audio-data` — float32 audio, goes through server-side VAD
- `mic-audio-end` — trigger conversation with buffered audio
- `text-input` — text conversation trigger
- `ai-speak-signal` — trigger proactive speak
- `interrupt-signal` — user interrupted, include heard text
- `frontend-playback-complete` — unblocks server after audio plays
- `fetch-history-list`, `fetch-and-set-history`, `create-new-history`, `delete-history`
- `fetch-configs`, `switch-config` — hot-switch character config
- `fetch-backgrounds`, `heartbeat`

**LLM plugin architecture:**

`StatelessLLMInterface` ABC (implement this to add a new LLM):
```python
async def chat_completion(
    self,
    messages: List[Dict],   # OpenAI message format
    system: str = None,     # system prompt
    tools: List[Dict] = None,  # OpenAI tool schemas
) -> AsyncIterator[str | List[ToolCallObject]]:
    # yield str tokens or List[ToolCallObject] when tools fire
    # yield "__API_NOT_SUPPORT_TOOLS__" to signal fallback to prompt mode
```

`AgentInterface` ABC (implement this for a custom agent):
```python
async def chat(self, input_data: BaseInput) -> AsyncIterator[BaseOutput]: ...
def handle_interrupt(self, heard_response: str) -> None: ...
def set_memory_from_history(self, conf_uid: str, history_uid: str) -> None: ...
```

**For Hermes — no new code needed.** Use `openai_compatible_llm` in `conf.yaml`:
```yaml
llm_configs:
  openai_compatible_llm:
    base_url: 'http://localhost:8642/v1'
    llm_api_key: '<API_SERVER_KEY>'
    model: 'hermes-3'
    temperature: 1.0
    interrupt_method: 'user'
```

**Voice pipeline (fully pluggable):**
- VAD: Silero (server-side) or client-side (browser ONNX)
- ASR: Whisper.cpp, faster-whisper, Azure, Groq Whisper, FunASR, sherpa-onnx
- TTS: GPT-SoVITS, Edge TTS, Azure, Bark, CosyVoice, ElevenLabs, OpenAI TTS, Kokoro, Piper, many more
- Translation: DeepLX or Tencent (optional post-ASR)
- All configured in `conf.yaml`, factory pattern

**Conversation pipeline:**
`agent.chat()` → `sentence_divider` → `actions_extractor` → `display_processor` → `tts_filter` → `SentenceOutput`

The `actions_extractor` decorator scans for `[emotion_keyword]` tokens in LLM output,
maps to expression index via `live2d_model.emotionMap`, populates `actions.expressions`.
The system prompt is auto-injected with the full emotion key list.

**Character config (`conf.yaml` structure):**
```yaml
system_config:
  host: '0.0.0.0'
  port: 12393

character_config:
  conf_name: 'ARES'
  conf_uid: 'ares-default'
  live2d_model_name: '<model name from model_dict.json>'
  character_name: 'ARES'
  human_name: 'Matthew'
  persona_prompt: '<system prompt / personality>'
  agent_config:
    conversation_agent_choice: 'basic_memory_agent'
    agent_settings:
      basic_memory_agent:
        llm_provider: 'openai_compatible_llm'
    llm_configs:
      openai_compatible_llm:
        base_url: 'http://localhost:8642/v1'
        llm_api_key: '<key>'
        model: 'hermes-3'
  asr_config:
    asr_model: 'whisper_cpp'
  tts_config:
    tts_model: 'gpt_sovits_tts'
  vad_config:
    vad_model: 'silero_vad'
```

**Chat history:** File-based at `chat_history/{conf_uid}/{history_uid}.json`

**MCP support:** `mcp_servers.json` in root, `ToolExecutor` handles OpenAI and Claude tool call formats

### What's missing / needs to be configured

1. **Hermes `conf.yaml`** — wire `openai_compatible_llm` to port 8642 (config change, no code)
2. **`characters/ares.yaml`** — ARES character config with persona from SOUL.md
3. **Live2D model** — choose a model, confirm its `emotionMap` matches emotion key list
4. **GPT-SoVITS TTS config** — configure voice, model path, API endpoint
5. **Wake word** — not built-in; needs separate wakeword process that sends `text-input` messages
6. **LaunchDaemon plist** — `com.ares.vtuber.plist` to auto-start at login

---

## 3. airi (TypeScript, character system + VRM/Live2D)

**Role in ARES:** Character card format, emotion system, optional VRM renderer in Electron

**Location:** `~/Documents/GitHub/airi/`
**Stack:** TypeScript/Vue 3, pnpm workspace + Turborepo, 48 packages, Electron desktop app

### What it already has

**Character system (portable, use this):**
- `@proj-airi/ccc` — CCC card spec v3 parser/exporter
  - Card fields: `name`, `personality`, `scenario`, `systemPrompt`, `greetings`,
    `messageExample` (few-shot), `tags`, `notes`, `extensions`
  - Export formats: PNG (metadata in tEXt chunk), APNG, JSON, Markdown
  - **Fully portable — pure TypeScript, no DOM dependency**

- `@proj-airi/core-agent` — `streamFrom()` LLM streaming runtime
  - Unified stream events: `text-delta`, `tool-call`, `tool-result`, `finish`, `error`
  - Auto-degrade: if model doesn't support tools, retries without; if model rejects content
    arrays, retries with plain strings
  - Uses xsAI (`@xsai/*`) — OpenAI-compatible, supports all major providers
  - **Fully portable — no DOM, works in Node**

- `@proj-airi/plugin-protocol` — typed WebSocket event bus (`ProtocolEvents`)
  - Key events: `input:text`, `output:gen-ai:chat:message`, `output:gen-ai:chat:complete`,
    `spark:notify` (episodic alerts), `spark:command` (character→agent instructions)
  - **Portable types — just TypeScript interfaces**

- `@proj-airi/server-sdk` — WebSocket client (`Client` class)
  - `module:authenticate` → `module:announced` handshake
  - Typed event send/receive, heartbeat, auto-reconnect
  - **Works in Node via crossws**

- `@proj-airi/server-runtime` — WebSocket server (`h3` + `crossws`)
  - Module registry, routing, heartbeat
  - **Node-compatible**

**VRM renderer (`stage-ui-three` — browser/Electron only):**
- Three.js + @pixiv/three-vrm v3.5.2
- `VRMModel.vue` — main component (Vue 3, not portable as-is)
- Emotion system: `useVRMEmote()` — `Happy`, `Sad`, `Angry`, `Surprised`, `Neutral`, `Think`
  Transitions use easeInOutCubic lerp, configurable `blendDuration`
  `setEmotionWithResetAfter(name, ms)` — auto-reset to neutral
- Lip sync: wLipSync WASM → phoneme weights → VRM blendshapes
- Eye tracking: camera / mouse / fixed modes, idle saccades
- Portable primitives: `loadVrm()`, `useVRMLoader()` — no Vue dependency, usable directly

**Live2D renderer (`stage-ui-live2d` — browser/Electron only):**
- PixiJS v6 + pixi-live2d-display (Cubism 4 SDK)
- Expression controller, motion manager, lip sync (wLipSync)
- Parameters: angleX/Y/Z, eyeOpen, eyebrowLR/Y, mouthOpen/Form, bodyAngle, breath
- **Browser/Electron only** — PixiJS requires WebGL DOM canvas

**Electron desktop app (`stage-tamagotchi`):**
- electron-vite, electron-builder, bundles server-runtime internally
- Multiple windows: main stage, settings, chat, desktop-overlay, widgets, dashboard
- Desktop-overlay: transparent frameless always-on-top avatar window
- Plugin host in main process, Godot stage support
- macOS/Windows/Linux

**Emotion constants (use these names for emotion-map alignment):**
```typescript
Emotion.Happy    → 'happy'     (VRM blendshape)
Emotion.Sad      → 'sad'
Emotion.Angry    → 'angry'
Emotion.Surprised → 'surprised'
Emotion.Neutral  → 'neutral'
Emotion.Think    → (no standard VRM, map to 'neutral' or custom)
Emotion.Curious  → 'surprised'
```

**Key file paths:**
- Character card types: `packages/ccc/src/define/card.ts`
- LLM runtime: `packages/core-agent/src/runtime/llm-service.ts`
- Protocol events: `packages/plugin-protocol/src/types/events.ts`
- WebSocket client: `packages/server-sdk/src/client.ts`
- VRM loader (portable): `packages/stage-ui-three/src/composables/vrm/loader.ts`
- VRM expression system: `packages/stage-ui-three/src/composables/vrm/expression.ts`
- Emotion constants: `packages/stage-ui-live2d/src/constants/emotions.ts`
- Tamagotchi desktop app: `apps/stage-tamagotchi/`

### What's portable vs. web-only

| Component | Portable | Notes |
|---|---|---|
| CCC card format (`ccc`) | Yes | Pure TS |
| `streamFrom()` LLM runtime | Yes | No DOM |
| xsAI provider SDK | Yes | No DOM |
| Protocol event types | Yes | Just TS types |
| WebSocket client (`server-sdk`) | Yes | Node-compatible |
| WebSocket server (`server-runtime`) | Yes | h3 + srvx |
| VRM loader primitives | Yes | Three.js, works with offscreen canvas in Electron |
| wLipSync WASM | Yes | Works in Node/Electron |
| `VRMModel.vue` component | No | Requires TresJS context, Vue lifecycle |
| Live2D components | No | PixiJS requires WebGL DOM canvas |
| Pinia stores | No | Depend on localStorage, BroadcastChannel, AudioContext |
| Audio pipeline | No | Requires AudioContext / AudioWorklet |
| MediaPipe tracking | No | Browser/webcam only |

---

## Integration Architecture

### How the three repos connect

```
Mac Studio
├── Hermes Agent daemon (port 8642 HTTP+WS, port 8644 WS)
│   └── ~/.hermes/ (config, memories, skills, cron)
│
├── Open-LLM-VTuber (port 12393)
│   ├── conf.yaml → LLM: http://localhost:8642/v1
│   ├── Voice pipeline: wakeword → Whisper ASR → Hermes → GPT-SoVITS TTS
│   ├── Live2D avatar in browser/Electron frontend
│   └── Desktop pet window (transparent, always-on-top)
│
└── ARES Dashboard (hermes-desktop extended)
    ├── Local mode: HTTPTransport → port 8642 directly
    ├── Remote mode: SSHTransport (existing, keep for MacBook→Mac Studio)
    ├── Chat with WebSocket streaming (port 8642 /ws)
    ├── Kanban, Skills, Cron, Sessions (existing views, working)
    └── Avatar panel (iframe into Open-LLM-VTuber frontend, or embedded WKWebView)

iPhone
└── ARES iOS (SwiftUI, Tailscale → port 8642)
    └── Shares model layer with dashboard
```

### Connection handshake (Open-LLM-VTuber ↔ Hermes)

1. Open-LLM-VTuber backend starts, loads `conf.yaml`
2. `AsyncLLM` (openai_compatible_llm) is instantiated with `base_url=http://localhost:8642/v1`
3. When user speaks: VAD → ASR → `BasicMemoryAgent.chat()` → `AsyncLLM.chat_completion()`
   → streams tokens from Hermes → `sentence_divider` → `actions_extractor` → TTS → WebSocket `audio` message
4. Frontend plays audio, triggers Live2D expressions from `actions.expressions`

### Expression system alignment

Open-LLM-VTuber uses `[emotion_keyword]` tokens in LLM output.
airi uses `Emotion` enum values.
Live2D model uses integer indices from `emotionMap`.

**Alignment process:**
1. Pick a Live2D model (confirm with Matthew)
2. Read its `emotionMap` from `model_dict.json`
3. Map airi `Emotion` enum values to those keys
4. Ensure Open-LLM-VTuber `live2d_expression_prompt` lists those same keys
5. Ensure Hermes system prompt (via persona) uses those same `[keyword]` format

---

## Key Risks and Gotchas

**hermes-desktop:**
- SSH transport is not behind a protocol. Services take `SSHTransport` directly.
  Adding HTTP means either protocol abstraction or parallel service implementations.
  **Recommendation:** Add a `TransportProtocol` with `execute` and `executeJSON` methods,
  make both transports conform, update services to accept the protocol.
- `HermesChatService` currently blocks for up to 30 minutes waiting for SSH process.
  WebSocket streaming requires a complete rewrite of this service.
- `AppState` creates `SSHTransport` in `init` — tightly coupled. Needs factory injection.

**Open-LLM-VTuber:**
- The frontend is a compiled Git submodule — source not present. Cannot modify frontend
  JS without cloning the frontend repo separately and rebuilding.
- Desktop pet mode is frontend-only — no backend config needed, but verify it works on
  macOS Sequoia before relying on it.
- Port 12393 may conflict if changed. If embedding the avatar in ARES Dashboard as an
  iframe/WKWebView, the port must be accessible from localhost.
- `frontend-playback-complete` message is required to unblock the server. If the frontend
  crashes or disconnects mid-conversation, the server hangs. Build reconnect handling.

**airi:**
- The VRM and Live2D Vue components are not directly reusable without the Vue 3 runtime.
  If embedding in the Swift dashboard app, the options are: WKWebView pointing at the
  running Open-LLM-VTuber frontend, or a separate Electron window.
- The airi channel server (port 6121) is optional — only needed if routing events between
  multiple modules. For a two-party system (Open-LLM-VTuber + Hermes), the airi channel
  server adds complexity without clear benefit. Skip it unless you need multi-module routing.
- pnpm monorepo requires pnpm — do not use npm or yarn with this repo.

**Hermes HTTP API:**
- Must be enabled explicitly: `API_SERVER_ENABLED=true` in `~/.hermes/.env`
- Auth: `API_SERVER_KEY` in `.env` → pass as `Authorization: Bearer <key>`
- Verify every endpoint against `~/Documents/GitHub/hermes-agent/docs/` before calling.
  Never assume endpoint paths. The API is not OpenAI-compatible by default unless Hermes
  explicitly implements that interface.
- WebSocket path for streaming: verify against gateway source, likely `/ws` on port 8642

---

## File Inventory Summary

### hermes-desktop — files to modify

| File | What to change |
|---|---|
| `App/AppState.swift` | Add transport factory, inject HTTPTransport for local profiles |
| `Models/ConnectionProfile.swift` | Add `transportKind`, `httpBaseURL`, `apiKey` fields |
| `Services/SSH/SSHTransport.swift` | Extract `TransportProtocol` — don't modify internals |
| `Services/HermesChatService.swift` | Rewrite for WebSocket streaming alongside SSH path |
| `Views/RootView.swift` | Add third column for avatar/tools panel |
| `Views/Shared/HermesUI.swift` | Add `HermesThreeColumnSplitView`, ARES theme colors |
| `App/HermesDesktopApp.swift` | Rename app, update bundle ID |

### hermes-desktop — files to create

| File | Purpose |
|---|---|
| `Services/HTTP/HTTPTransport.swift` | URLSession HTTP client for Hermes port 8642 |
| `Services/HTTP/WebSocketTransport.swift` | Streaming chat via WebSocket |
| `Views/Avatar/AvatarPanelView.swift` | WKWebView or iframe container for VTuber frontend |
| `Views/Tools/ToolsPanelView.swift` | Right-side domain tools container |

### Open-LLM-VTuber — files to create/modify

| File | What to change |
|---|---|
| `conf.yaml` | Point LLM to Hermes port 8642, configure TTS/ASR |
| `characters/ares.yaml` | ARES character config (persona, model name, emotion map) |
| `model_dict.json` | Add ARES avatar model entry |
| `com.ares.vtuber.plist` | LaunchDaemon for auto-start |

### No changes needed

| File | Why |
|---|---|
| All `hermes-desktop` service Python scripts | Logic is correct, stay SSH for remote |
| `Open-LLM-VTuber` agent/stateless_llm code | `openai_compatible_llm` handles Hermes |
| `Open-LLM-VTuber` VAD/ASR/TTS code | Plugin architecture handles this via config |
| All `airi` package internals | Use CCC format and emotion constants only |
| `~/.hermes/` anything | Never modify directly |
