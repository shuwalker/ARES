# ARES-Face Architecture Comparison: OS1 vs AIRI vs Lilith

## The Three Approaches

### OS1 (Hermes Desktop App) — "Enterprise Control Panel"
- **Platform:** SwiftUI macOS
- **State:** Single 2,600-line `AppState` god object (`@ObservableObject`), injected via `@EnvironmentObject`
- **Nav:** `NavigationSplitView` with sidebar enum → giant switch in `RootView`
- **Networking:** Pluggable `RemoteTransport` protocol (SSH-based Python scripts baked into Swift strings)
- **Mode:** One mode — operator dashboard. "Immersive" is just a VNC overlay, not a companion
- **Persona:** None. No avatar, no personality system, no face
- **Voice:** Realtime voice panel as overlay, not core UX

### AIRI (Stage-Tamagotchi) — "Avatar-First Companion"
- **Platform:** Vue 3 + Electron + Pinia (monorepo with shared packages)
- **State:** Pinia stores sliced by domain (chat, character, speech, Live2D, VRM, settings)
- **Nav:** File-based routing (`/pages`) — stage, chat, desktop-overlay, widgets, settings/*
- **Rendering:** Dual engine (Live2D Cubism 4 via PixiJS, VRM via TresJS/Three.js) with shared `AvatarProps` interface
- **Mode:** Avatar-first — face is always visible, chat is an overlay. Desktop overlay is transparent always-on-top Electron window
- **Persona:** Character card system with reactions, notebook, spark notification
- **Voice:** Intent-based speech queue with priority (normal/high/critical) and behavior (queue/interrupt)
- **Chat:** `InteractiveArea` with streaming, attachments, toolset selection

### Lilith-AI — "Local Daemon with Personality"
- **Platform:** PyQt6 tray app + Python daemon
- **State:** Frozen dataclasses (Identity, Persona) + mutable SQLite (Memory) + event bus (`LilithSessionBus`)
- **Nav:** None — tray menu spawns separate windows (Chat, Persona Studio, Settings). Each window is show/hide, no router
- **Networking:** Local-first LLM (MLX or llama.cpp on localhost). Hermes as tool executor via MCP stdio servers
- **Mode:** Two modes — Chat window (compact) and Studio window (personality editor). Tray icon for quick actions
- **Persona:** **4-layer system** — HEXACO, SPECIAL, Expression, Domains — each 0.0-1.0 sliders. Neutral band (0.40-0.60) = no prompt effect
- **Voice:** `VoiceOrchestrator` with explicit `VoiceState` FSM (duck-typed, not protocol)
- **Chat:** `FastPathSession` with `<chat>/<tool>/<ignore>` gate — skips tool prompt for simple turns

---

## Side-by-Side Comparison

| Aspect | OS1 | AIRI | Lilith | Our Approach |
|--------|-----|------|--------|---------------|
| **State management** | God object (2,600 lines) | Pinia stores per domain | Frozen dataclasses + event bus | `BrainConnection` (245 lines) + `VoiceManager` (57 lines) — lean but growing |
| **Navigation** | Sidebar enum switch | File-based routes | Separate windows, no router | Sidebar enum switch (same as OS1) — works for Manual mode |
| **Avatar rendering** | None | Live2D / VRM dual engine | Radar chart (data viz) | SceneKit/Metal (own renderer) — closest to AIRI |
| **Chat overlay** | None (full page) | Floating panel on avatar stage | Window-based | Floating `ChatStream` on avatar stage — AIRI pattern ✓ |
| **Voice** | Overlay panel | Intent queue + priority + behavior | VoiceState FSM | `VoiceManager` toggle — needs queue and FSM |
| **Persona** | None | Character cards + reactions | 4-layer sliders (HEXACO/SPECIAL/Expression/Domains) | None yet — need this |
| **Mode switching** | VNC overlay (not companion) | Stage vs Chat page | Chat vs Studio windows | 2-position slider (Manual / Avatar Twin) ✓ |
| **Settings** | In-app pages | Monorepo shared pages | PyQt dialogs | Need to build |
| **Desktop presence** | Standard window | Transparent overlay window | System tray icon | Need to decide |

---

## Problems I See

### OS1 Problems
1. **God state object** — 2,600-line AppState means any property change can trigger broad re-renders. Our `BrainConnection` is 245 lines — we need to keep it that way
2. **`@ObservableObject` instead of `@Observable`** — SwiftUI's new Observation framework is cleaner. We should use `@Observable`
3. **Python scripts inside Swift strings** — Tight coupling to remote execution contract. We already do this cleaner with WebSocket
4. **`AnyView` type erasure** — Performance hit at root level. We're using `@ViewBuilder` switch — good
5. **No companion mode** — It's a tool, not a presence. This is why we built the immersion slider
6. **No persona** — It's a terminal with a chat pane. Zero personality

### AIRI Problems
1. **Massive page components** — `index.vue` is 22KB/500+ lines. Our `ARESRootView` is 180 lines after rewrite — much cleaner
2. **Duplicate store architectures** — Live2D and VRM have near-identical stores. We should use a unified `AvatarRenderer` protocol
3. **Deep guard nesting** — `if !vrmStore.model { return }` everywhere. Use Optionals properly
4. **Hot-reload hacks** — `window.location.reload()` on HMR. dev UX pain
5. **Polling mic activity** — Should use AudioWorklet events

### Lilith Problems
1. **Giant `__main__.py`** — 23KB entry point handling everything. We have clean `ARESApp.swift` entry
2. **No formal state machine for main bus** — Only VoiceOrchestrator has `VoiceState` enum. Main conversation flow is if/else
3. **Tight Hermes coupling** —launcher reads Hermes internals, writes its config
4. **JSON-array tag storage in SQLite** — `LIKE '%"foo"%'` is brittle
5. **Duck-typed STT/TTS** — `_safe_call` with `getattr` instead of protocol

---

## What's Better: OS1 or Lilith?

**Neither wins outright. They solve different problems.**

**OS1 is better for:**
- Multi-section dashboard apps (sessions, skills, cron, logs, config, analytics)
- Production-grade networking with pluggable transports
- Complex workspace flows (terminal, file editors, desktop VNC)

**Lilith is better for:**
- Personality and persona (4-layer system is genuinely good)
- Local-first LLM runtime (autodetect MLX vs llama.cpp)
- Event-driven architecture (bus decouples UI from pipeline)
- Fast-path chat routing (skip tool prompt for simple turns)

**For ARES, we want:**
- **AIRI's avatar stage pattern** — face always visible, chat as overlay ✓ (implemented)
- **Lilith's persona system** — 4-layer personality sliders (need to build)
- **Lilith's event bus** — decouple voice/speech/tts from UI (need to build)
- **Lilith's fast-path routing** — `<chat>/<tool>/<ignore>` for simple responses
- **OS1's dashboard pages** — sessions, skills, cron, logs, config (stubbed)
- **Our own clean state** — keep BrainConnection lean, add domain stores as needed
- **Our own dual-mode** — two positions, not three, not modeless ✓ (implemented)

---

## Recommended Changes to Our Architecture

### 1. Split BrainConnection into Domain Stores
**Now:** 1 monolith (245 lines, growing)
**Target:** Domain stores like AIRI's Pinia pattern

```
BrainConnection    → WebSocket, connection state, message routing (keep lean)
ChatStore          → messages, inputText, streaming state
AvatarStore        → expression, intensity, speaking state, style
VoiceStore         → isListening, transcript, VAD level, speech queue
PersonaStore       → 4-layer sliders (HEXACO, SPECIAL, Expression, Domains)
CognitiveStore     → cognitive snapshots, heartbeat data
```

### 2. Add Event Bus (Lilith Pattern)
**Now:** BrainConnection.parseMessage() mutates state directly
**Target:** Messages come in via WebSocket → published to typed bus → stores subscribe

```swift
// Topics: pipeline/stt/output, pipeline/llm/stream, pipeline/llm/output,
//          event/persona/changed, event/llm/error, face/state
struct ARESBus {
    static let shared = ARESBus()
    func publish(_ topic: String, payload: Any)
    func subscribe(_ topic: String, handler: (Any) -> Void)
}
```

### 3. Add Speech Intent Queue (AIRI Pattern)
**Now:** isSpeaking boolean
**Target:** Priority-based queue

```swift
enum SpeechPriority { case normal, high, critical }
enum SpeechBehavior { case queue, interrupt }

struct SpeechIntent {
    let text: String
    let priority: SpeechPriority
    let behavior: SpeechBehavior
}
```

### 4. Add Fast-Path Chat Gate (Lilith Pattern)
**Now:** Every message goes through full WebSocket roundtrip
**Target:** Buffer first 30 chars → classify as chat/tool/ignore → skip tool prompt for simple replies

```swift
enum FastPath { case chat, tool, ignore }
func classify(_ prefix: String) -> FastPath
```

### 5. Add Persona Sliders (Lilith Pattern)
4-layer system with neutral band:

```swift
struct PersonaLayer: Codable {
    var traits: [String: Double]  // 0.0-1.0
    static let neutralBand = 0.40...0.60
    func promptLines() -> [String]  // only emit prose for out-of-band values
}
```

### 6. Desktop Presence Mode (AIRI Pattern)
Add transparent always-on-top overlay option for Avatar Twin mode — face floats on desktop with click-through, like AIRI's `desktop-overlay.vue`.

---

## Priority Order
1. **Speech intent queue** — Critical for not stepping on user's voice
2. **Domain store split** — BrainConnection is manageable now, will become OS1's god object within weeks
3. **Fast-path chat** — Big UX win, simple to implement
4. **Event bus** — Enables voice/speech/avatar coordination
5. **Persona sliders** — Needed for Avatar Twin mode to feel like a person
6. **Desktop overlay** — Polish, not blocker