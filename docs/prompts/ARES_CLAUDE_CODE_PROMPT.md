# ARES — Claude Code Session Prompt

Paste this at the start of every Claude Code session working on ARES.

---

You are building ARES — a personal AI operating system for Matthew Jenkins (founder,
Jenkins Robotics, propulsion engineer). This is a real product. Ship the right thing.
Do not do the easy thing. Read context before acting. Verify after every change.

---

## Read These First — Before Writing a Single Line of Code

```
~/Documents/ARES_CODEBASE_AUDIT.md        ← Ground truth. What exists, what's reusable, what to build.
~/Documents/ARES_APP_BUILD_PROMPT.md      ← Full architecture spec and build phases.
~/.hermes/SOUL.md                          ← Hermes identity and behavioral rules.
~/.hermes/AGENTS.md                        ← Hermes operational rules.
~/.hermes/memories/MEMORY.md               ← Current project state.
~/.hermes/MASTER_TODO.md                   ← Active task list.
~/Documents/GitHub/hermes-desktop/Sources/HermesDesktop/App/AppState.swift
~/Documents/GitHub/hermes-desktop/Sources/HermesDesktop/Services/SSH/SSHTransport.swift
~/Documents/GitHub/Open-LLM-VTuber/src/open_llm_vtuber/websocket_handler.py
~/Documents/GitHub/Open-LLM-VTuber/src/open_llm_vtuber/agent/agents/agent_interface.py
~/Documents/GitHub/Open-LLM-VTuber/conf.yaml
~/Documents/GitHub/hermes-agent/docs/     ← Verify every Hermes API endpoint here before calling it.
```

Do not skip this step. Every wrong assumption costs real time.

---

## What ARES Is

Three repos. One product. Three modes.

**Brain:** Hermes Agent daemon at `~/.hermes/` — HTTP API port 8642, WebSocket port 8642 `/ws`,
gateway WebSocket port 8644. OpenAI-compatible API at `http://localhost:8642/v1`.
Never modify `~/.hermes/` directly except config files. Never write to `~/.hermes/memories/`.

**Dashboard mode:** `hermes-desktop` (Swift, macOS 14+, SPM). Already has sessions, kanban,
skills, cron, file editor, SSH terminal, usage stats — all via SSH transport. Needs an
`HTTPTransport` added for local Hermes connection (port 8642 direct). Do not rewrite what
already works. Read the source, then extend it.

**Presence mode:** `Open-LLM-VTuber` (Python, FastAPI, WebSocket). Voice pipeline: VAD →
Whisper ASR → Hermes LLM → GPT-SoVITS TTS → Live2D avatar. LLM backend is
`openai_compatible_llm` pointed at `http://localhost:8642/v1` — this is a config change,
not a code change. Do not rewrite what already works. Configure it, then extend it.

**Character system:** `airi` (TypeScript monorepo). Use the CCC card format for persona
definition and the emotion constant names for expression alignment. The Vue/PixiJS renderer
is browser-only — don't try to port it to Swift. The portable pieces are: CCC card parser,
`streamFrom()` LLM runtime, protocol event types, WebSocket client/server.

---

## The Three Repos — What To Touch and What To Leave Alone

### hermes-desktop (Swift)

READ before touching:
- `AppState.swift` — central state, owns all services, hardcodes SSHTransport
- `SSHTransport.swift` — ALL current data flow, not behind a protocol
- `HermesUI.swift` — full design system, extend this don't replace it
- `ConnectionProfile.swift` — SSH-specific fields, needs transport discriminator

ADD (new files):
- `Services/HTTP/HTTPTransport.swift` — URLSession client for port 8642
- `Services/HTTP/WebSocketTransport.swift` — URLSessionWebSocketTask for streaming
- `Views/Avatar/AvatarPanelView.swift` — WKWebView into VTuber frontend
- `Views/Tools/ToolsPanelView.swift` — domain tool panel container

MODIFY (surgical changes only):
- `ConnectionProfile.swift` — add `transportKind: TransportKind` (`.ssh` | `.local`),
  `httpBaseURL`, `apiKey` for local profiles
- `AppState.swift` — add transport factory, inject correct transport per profile
- `HermesChatService.swift` — add WebSocket streaming path alongside existing SSH path
- `RootView.swift` — add third column for avatar + tools panel (right side)
- `HermesUI.swift` — add `HermesThreeColumnSplitView`, ARES theme colors

DO NOT TOUCH:
- Any existing SSH transport logic — it still works for remote (MacBook → Mac Studio)
- The Python scripts embedded in services — they're correct
- The model layer (sessions, kanban, skills, etc.) — complete and well-structured
- The existing views (OverviewView, KanbanView, etc.) — they work

### Open-LLM-VTuber (Python)

CONFIG CHANGES ONLY (no code):
- `conf.yaml` — point LLM at `http://localhost:8642/v1`, configure GPT-SoVITS TTS,
  Whisper ASR, Silero VAD
- `model_dict.json` — add ARES avatar model entry

CREATE:
- `characters/ares.yaml` — ARES character config with persona prompt, model name
- `com.ares.vtuber.plist` — LaunchDaemon for auto-start at login

CODE CHANGES (only if needed after config):
- If Hermes API is not OpenAI-compatible, implement `StatelessLLMInterface` in
  `src/open_llm_vtuber/agent/stateless_llm/hermes_llm.py`
- Add to `LLMFactory` and `StatelessLLMConfigs` if adding a named hermes provider

DO NOT TOUCH:
- WebSocket handler message routing — the protocol is correct and complete
- VAD/ASR/TTS implementations — use via config, don't modify
- The conversation pipeline decorators — they work correctly
- The frontend (compiled, git submodule) — cannot modify without separate clone

### airi (TypeScript)

USE ONLY:
- `packages/ccc/src/define/card.ts` — character card type definitions
- `packages/stage-ui-live2d/src/constants/emotions.ts` — emotion constant names
- `packages/stage-ui-three/src/composables/vrm/loader.ts` — VRM loader primitives
- `packages/stage-ui-three/src/composables/vrm/expression.ts` — expression system
- `packages/plugin-protocol/src/types/events.ts` — protocol event types

DO NOT TOUCH:
- Vue components — not portable to Swift
- Pinia stores — browser-dependent
- The Electron app — run it separately if needed, don't modify for ARES

---

## Build Order — Do This, Not That

### Phase 1: Get the brain talking to the face (do this first)

1. Verify Hermes HTTP API is live:
   - Check `~/.hermes/.env` for `API_SERVER_ENABLED=true`
   - If missing, add it, restart gateway
   - Test: `curl http://localhost:8642/v1/models` (or check hermes-agent/docs for correct path)

2. Wire Open-LLM-VTuber to Hermes:
   - Edit `conf.yaml` — set `openai_compatible_llm.base_url: http://localhost:8642/v1`
   - Set `llm_api_key` from `~/.hermes/.env` `API_SERVER_KEY`
   - Create `characters/ares.yaml` with ARES persona (pull system prompt from SOUL.md)
   - Run: `uv run run_server.py` — verify avatar speaks through Hermes

3. Confirm emotion tokens work:
   - Check `model_dict.json` for the active model's `emotionMap`
   - Verify Hermes/LLM output includes `[emotion]` tokens from that map
   - Watch avatar expressions fire — if not, check `live2d_expression_prompt` in `conf.yaml`

### Phase 2: Dashboard HTTP transport

4. Add `TransportProtocol` to hermes-desktop:
   - Extract interface from `SSHTransport` (execute, executeJSON, shellArguments)
   - Make `SSHTransport` conform
   - Add `TransportKind` enum to `ConnectionProfile`

5. Build `HTTPTransport`:
   - Mirrors `SSHTransport` API exactly
   - Uses URLSession for HTTP GET/POST to `http://localhost:8642`
   - Reads API key from `ConnectionProfile.apiKey`
   - Maps Hermes JSON responses to same types as SSH service layer

6. Build `WebSocketTransport`:
   - `URLSessionWebSocketTask` to `ws://localhost:8642/ws`
   - Streaming chat: yields token strings as they arrive
   - Rewrite `HermesChatService` to use this for `.local` profiles

7. Update `AppState` to inject correct transport per profile transport kind

8. ARES branding pass (app name, bundle ID, icon, theme colors in HermesUI)

### Phase 3: Avatar panel in Dashboard

9. Build `AvatarPanelView` — WKWebView loading `http://localhost:12393`
   (the Open-LLM-VTuber frontend)
10. Build `HermesThreeColumnSplitView` — sidebar + content + avatar panel
11. Update `RootView` to use three-column layout
12. Add Desktop pet mode toggle (shows/hides the VTuber window as floating overlay)

### Phase 4: Apple integration

13. Build Apple MCP server — Swift LaunchDaemon, EventKit + osascript, port 9515
14. Add to Hermes config under `mcp.servers`
15. Wire Calendar/Reminders into Dashboard Overview section

### Phase 5: iOS

16. Extract shared Swift package — HermesHTTPClient, core models, ChatView
17. Build ARES iOS app — TodayView, voice input, Tailscale, APNS, home screen widget

### Phase 6: Domain tools

18. Second Brain Explorer — LanceDB search panel in Dashboard
19. YouTube Pipeline Queue — approval UI for staged videos
20. Physics simulation panel (confirm tool with Matthew before building)

---

## Hard Rules

**Hermes API:**
- NEVER call an endpoint without verifying it in `~/Documents/GitHub/hermes-agent/docs/`
- Auth header: `Authorization: Bearer <API_SERVER_KEY>` (key from `~/.hermes/.env`)
- NEVER write to `~/.hermes/memories/` — Hermes owns that
- NEVER modify `~/.hermes/config.yaml` without reading it first and making a backup

**hermes-desktop code style (match exactly):**
- Swift 6, `@MainActor` for UI state, `@unchecked Sendable` for services
- Async/await everywhere — no completion handlers, no callbacks
- Structured concurrency — actors for shared mutable state
- SwiftUI only — no UIKit unless a system API forces it
- No third-party UI deps — use Apple frameworks + `HermesUI.swift`

**Open-LLM-VTuber code style (match exactly):**
- Python 3.11+, loguru for logging, Pydantic v2 for config models
- Factory pattern for all pluggable components
- `uv` for dependency management — `uv sync`, not `pip install`
- New LLM providers: implement `StatelessLLMInterface`, register in `LLMFactory`
- New agents: implement `AgentInterface`, register in `AgentFactory`

**General:**
- Read the file before editing it — always
- Verify the change compiles/runs before declaring it done
- When you don't know if a Hermes endpoint exists, check the docs — don't guess
- If a task is ambiguous, stop and ask Matthew — don't fill in assumptions

---

## Key Ports and Paths

```
~/.hermes/                            ← Live Hermes install (careful)
~/.hermes/.env                        ← API keys, API_SERVER_ENABLED, API_SERVER_KEY
~/.hermes/config.yaml                 ← Hermes config (read before writing)
~/.hermes/memories/MEMORY.md          ← Read only
~/.hermes/MASTER_TODO.md              ← Current task list

Port 8642   ← Hermes HTTP API + WebSocket (/ws)
Port 8644   ← Hermes gateway WebSocket (Discord/webhooks)
Port 9119   ← Hermes dashboard
Port 12393  ← Open-LLM-VTuber (default, configurable)
Port 9515   ← Apple MCP server (to be built)
Port 5678   ← n8n workflow automation

~/Documents/GitHub/hermes-desktop/          ← Dashboard shell (Swift)
~/Documents/GitHub/Open-LLM-VTuber/        ← Avatar + voice (Python)
~/Documents/GitHub/airi/                    ← Character system (TypeScript)
~/Documents/GitHub/hermes-agent/docs/       ← Hermes API reference (verify here)
~/Documents/ARES_CODEBASE_AUDIT.md          ← Full audit of all three repos
~/Documents/ARES_APP_BUILD_PROMPT.md        ← Full architecture spec
```

---

## What This Is Not

- Not a chatbot — it's an operating system for a person's life
- Not a rewrite of hermes-workspace — that's a reference, not the product
- Not a new LLM — Hermes routes to GLM-5.1 / DeepSeek / Gemma4 per config
- Not a web app — Dashboard is native Swift, Avatar runs in its own process
- Not Electron for the dashboard — hermes-desktop is native macOS
- Not from scratch — three solid repos already exist, extend them
