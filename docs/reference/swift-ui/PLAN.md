# ARES App — Architecture & Implementation Plan

**Status:** Phase 1 shipped; Phase 2 partially shipped. A cross-cutting
"Cognitive OS" track (Phase 0–4) landed in PR #2 — see
[`ares/reference/docs/COGNITIVE_OS.md`](../docs/COGNITIVE_OS.md) for
the architecture-of-record. This document is the long-arc plan; phase
status is now tracked inline below.
**Date:** 2026-05-14

---

## Vision

One multiplatform Apple app. iOS, macOS, watchOS, visionOS. ARES exists as a **layer above the screen** — not a window you switch to, but a persistent overlay presence. Communication via text, voice, video. Content generation capability. Hermes is the cognitive foundation (MCP backend). The app is the interface and body. Quality bar: Apple would ship this.

## Architecture

### Three layers, one app

```
┌──────────────────────────────────────────────┐
│ ARES.app — multiplatform SwiftUI              │
│                                                │
│  ┌────────────┐  ┌──────────┐  ┌────────────┐ │
│  │ ARESKit    │  │ Hermes   │  │ Apple       │ │
│  │ Avatar +   │  │ Client   │  │ Services    │ │
│  │ Presence   │  │ MCP comm │  │ osascript   │ │
│  └────────────┘  └──────────┘  └────────────┘ │
│                                                │
│  Communication modes: text / voice / video     │
│                                                │
│               Hermes (:9876)                   │
│               ↓                               │
│  MCP servers: perception :9512                │
│               voice :9513                      │
│               avatar :9514                     │
│               apple :9515 (future)             │
└──────────────────────────────────────────────┘
```

### Targets

| Target | Type | Purpose |
|---|---|---|
| `ARES` | executable | The app entry point — iOS/macOS/watchOS/visionOS |
| `ARESKit` | library | Shared: avatar rendering, presence system, UI components, Apple services |
| `HermesClient` | library | HTTP client to Hermes cognition bridge (:9876), MCP server proxy |
| `ARESTests` | test | Unit + integration tests across all targets |

### Device-specific presence modes

| Device | Presence Mode |
|---|---|
| **macOS** | Overlay panel floating above desktop. Summon/dismiss with hotkey. Optional persistent companion mode |
| **iOS** | Dynamic Island integration. Compact overlay. Full-screen for deep interaction |
| **watchOS** | Complications + quick text/voice. Minimal presence, maximum availability |
| **visionOS** | Volumetric 3D entity in your space. Full immersion capable |

### Communication modes (all devices)

| Mode | Input | Output | Tech |
|---|---|---|---|
| **Text** | Keyboard / scribble | Chat bubbles | SwiftUI Text |
| **Voice** | Mic → NSSpeechRecognizer | AVSpeechSynthesizer / Piper TTS | VoiceFramework |
| **Video** | Camera | Avatar visual response + generated content | ARESKit + Metal/RealityKit |

---

## Phase 1 — Scaffold & Build  ✅ SHIPPED

**Goal:** A multiplatform app that compiles and launches on macOS. SwiftUI shell with basic architecture in place.

### As Shipped

Ended up as a single SPM target under `ARES-Face/` rather than the
4-target `ARES / ARESKit / HermesClient / ARESTests` split below. The
practical reasons: the Hermes-client surface is small (one
`BrainConnection.swift` file talking WebSocket + REST to `:7860`), and
splitting tiny modules into separate targets added build complexity
with no payoff yet. The 4-target split is still the right idea once
multi-device targets land (Phase 7).

### Deliverables (original)
- [x] `Package.swift` — SPM manifest (single target; macOS 15+, multi-device TBD)
- [x] `App/ARESApp.swift` + `App/ARESRootView.swift` — entry + root layout
- [x] `Networking/BrainConnection.swift` — WebSocket `:7860/ws` + REST `/api/*` (replaces the planned `HermesClient` separate target)
- [ ] `Sources/HermesClient/MCPProxy.swift` — deferred; not needed yet
- [x] Library surface — folded into `ARES-Face` target
- [ ] `Makefile` — not present (Xcode build via `build_app.sh`)
- [x] Bundle metadata via `Info.plist.template` + `build_app.sh`
- [x] `swift build` succeeds; app launches

### HermesClient API Contract

```swift
// Sources/HermesClient/HermesClient.swift
public actor HermesClient {
    public init(baseURL: URL = URL(string: "http://localhost:9876")!)
    
    public func health() async throws -> HealthStatus
    public func think(text: String, sessionId: String) async throws -> ThinkResponse
    public func avatar() async throws -> AvatarState
    
    // MCP proxy — direct calls to MCP servers
    public func mcpCall(server: MCPServer, tool: String, args: [String: Any]) async throws -> MCPResult
}

public struct ThinkResponse: Codable, Sendable {
    public let response: String
    public let state: String
    public let expression: String
}

public enum MCPServer: String, Sendable {
    case perception = "http://localhost:9512"
    case voice = "http://localhost:9513"
    case avatar = "http://localhost:9514"
}
```

---

## Phase 2 — Overlay Presence (macOS)  ◐ PARTIAL

**Goal:** ARES summoned via hotkey/menu bar. Compact overlay panel appears. Type or speak. Response delivered. Dismisses.

### Status

Main-window text chat shipped (`Views/ChatStream.swift` +
`Views/CommandBar.swift` + `Views/MenuBarView.swift`). Hotkey-summoned
floating overlay is **not yet built** — the app currently runs as a
standard `WindowGroup` window plus `MenuBarExtra`.

The Hermes-side text→think() pipe also still needs the bridge wiring
(stub `cognition_query()` in `ares/runtime/hermes_bridge.py`).

### Deliverables
- [ ] `ARESKit/Overlay/OverlayWindow.swift` — borderless, floating, non-activating panel
- [ ] `ARESKit/Overlay/HotkeyManager.swift` — global hotkey registration
- [x] `ARESKit/Overlay/StatusBarController.swift` — `MenuBarView.swift` provides menu bar presence
- [x] `ARESKit/Chat/ChatView.swift` — `Views/ChatStream.swift` + `Views/CommandBar.swift`
- [x] `ARESKit/Chat/ConversationManager.swift` — `BrainConnection.messages` + `sendMessage`
- [◐] HermesClient integration — REST `POST /api/chat` is wired; Hermes-side `/think` is a stub awaiting sibling PR

### Behavior (target)
```
Press Ctrl+Space → overlay slides in from top-right
Type question → sent to Hermes :9876 → response appears
Voice button → NSSpeechRecognizer activates → transcription → Hermes
Press Escape → overlay dismisses
Menu bar icon always present — click to summon
```

---

## Phase 2.5 — Cognitive OS  ✅ SHIPPED (out-of-band, PR #2)

Not on the original phase map but ended up landing between Phase 2 and
Phase 3. Made the Homunculus visibly *think* before the voice loop was
ready, which felt more important than another I/O modality on top of an
opaque brain.

Five sub-phases, all shipped:

| # | Deliverable |
|---|---|
| 0 | Versioned `CognitiveSnapshot` schema, WebSocket push on phase transitions, heartbeat pill in `ImmersionBar`, expanded `CognitiveActivityPanel`, sidebar mounted in root |
| 1 | Tiered memory: volatile `SessionStore`, episodic SQLite + swappable `VectorStore`/`Embedder` protocols (in-memory + Ollama variants), semantic triple store, Memory Inspector sidebar tab |
| 2 | Per-cycle reasoning DAG with `ThoughtNodeRecord` + `emit_thought_node()`; force-directed Mission Control panel (SwiftUI Canvas + Verlet integrator, ~60 fps); per-cycle DAG persisted into episodic metadata |
| 3 | Idle reflexion: `consolidate_episodics` + `dedupe_facts` + `surface_open_questions` + `/api/idle/run` orchestrator |
| 4 | Declarative `CognitiveBindings.evaluate(snapshot, time)` table → 4 new `SurfaceCustomUniforms` fields (`noiseScale`, `emissivePulse`, `vertexJitter`, `glitchAmplitude`); `BlackFireSurface.metal` reacts |

Reference: [`ares/reference/docs/COGNITIVE_OS.md`](../docs/COGNITIVE_OS.md).

## Phase 3 — Voice

**Goal:** Speak to ARES naturally. ARES speaks back. Works in overlay mode and full-screen.

### Deliverables
- [ ] `ARESKit/Voice/SpeechRecognizer.swift` — NSSpeechRecognizer wrapper, VAD
- [ ] `ARESKit/Voice/TextToSpeech.swift` — AVSpeechSynthesizer for output
- [ ] Voice server integration (:9513) — Piper TTS as premium voice option
- [ ] Wake word: "ARES" — triggers listening
- [ ] Voice visual feedback — avatar reacts to listening/speaking states

---

## Phase 4 — 3D Avatar

**Goal:** ARES has a visual presence. Not a chat bubble. A 3D entity that reacts to conversation state and emotion.

### Avatar Options (Matthew to choose)

| Option | What It Is | Effort | Visual Quality |
|---|---|---|---|
| **A — Procedural energy form** | Metal particles + RealityKit. Violet/black energy that shifts with emotion. Dynamic, abstract, beautiful | Medium | High |
| **B — VRM anime character** | Import VRM model → RealityKit. Expressive face, eye tracking, gestures | High | Very High |
| **C — Hybrid** | Start with energy form (A), add character body later (B) | Medium → High | Highest long-term |

### Deliverables
- [ ] `ARESKit/Avatar/AvatarEntity.swift` — RealityKit Entity setup
- [ ] `ARESKit/Avatar/FaceStateMachine.swift` — idle/awakened/listening/thinking/speaking/sleeping
- [ ] `ARESKit/Avatar/ExpressionMapper.swift` — Hermes response expression → avatar visual state
- [ ] `ARESKit/Avatar/EyeTracking.swift` — camera → person position → avatar gaze follows
- [ ] Lip sync on speech output

---

## Phase 5 — Apple Services

**Goal:** ARES reads and manages your Apple life. Calendar, Reminders, Notes, Mail, Messages. All through osascript. No third-party CLIs.

### Deliverables
- [ ] `ARESKit/Services/CalendarService.swift` — today's events, create, search
- [ ] `ARESKit/Services/RemindersService.swift` — list, read, create, complete
- [ ] `ARESKit/Services/NotesService.swift` — search, read, create
- [ ] `ARESKit/Services/MailService.swift` — unread count, subject scan
- [ ] `ARESKit/Services/MessagesService.swift` — send iMessage/SMS
- [ ] `ARESKit/Services/AppleServiceProtocol.swift` — unified service interface
- [ ] Morning brief generation: calendar + reminders + mail → formatted response
- [ ] Security: filter to project-relevant lists by default, never surface personal data unsolicited

---

## Phase 6 — Content Generation

**Goal:** ARES generates content — scripts, thumbnails, video concepts. Pulls from knowledge base. Produces usable output.

### Deliverables
- [ ] Thumbnail generation pipeline integration (ComfyUI / Hermes)
- [ ] Script generation from KB prompts + trending topics
- [ ] Video concept proposals: 3 options, structured format
- [ ] Export to Obsidian vault
- [ ] Publish approval workflow (draft → Matthew review → YouTube)

---

## Phase 7 — Multi-Device

**Goal:** Same ARES on your phone, watch, and Vision Pro. Shared brain, adapted presence.

### Deliverables
- [ ] iOS overlay mode — Dynamic Island / compact card
- [ ] watchOS complication — quick text/voice, minimal
- [ ] visionOS volumetric — 3D avatar in immersive space
- [ ] iCloud sync for preferences, conversation history, service access

---

## Phase 8 — Polish & Ship

**Goal:** Apple-quality finish. App icon, code signing, sandbox, versioning, auto-update.

### Deliverables
- [ ] `ARES.icns` / `ARES.imageset` — app icon family
- [ ] Code signing identity
- [ ] Sandbox entitlements
- [ ] Sparkle auto-update framework (macOS)
- [ ] App Store submission prep
- [ ] Onboarding flow — first launch, permissions, voice calibration

---

## Execution Principles

1. **All code is macOS-first.** iOS/watchOS/visionOS targets compile from same sources with platform conditionals.
2. **Hermes is always the brain.** The app doesn't do reasoning — Hermes does. App handles presence, perception, I/O.
3. **osascript over third-party.** Every Apple integration uses `osascript` via `Process`. No `brew install` dependencies.
4. **Each phase delivers a buildable app.** No "foundation work" that doesn't ship user-visible behavior.
5. **Matthew sees progress in real output.** A video. A screenshot. A working feature. Not a code diff.

---

## File Map (Phase 1)

```
ARES-App/
├── Package.swift                    # SPM manifest
├── Makefile                         # Build automation
├── README.md                        # Project overview
├── PLAN.md                          # This file
├── Sources/
│   ├── ARES/
│   │   ├── main.swift               # Entry point
│   │   └── App.swift                # SwiftUI App, multiplatform
│   ├── ARESKit/
│   │   └── ARESKit.swift            # Library surface (Phase 1 minimal)
│   ├── HermesClient/
│   │   ├── HermesClient.swift       # HTTP client to :9876
│   │   ├── MCPProxy.swift           # MCP server proxy
│   │   └── Models.swift             # ThinkResponse, HealthStatus, etc.
│   └── Resources/
│       └── Info.plist               # Bundle metadata
└── Tests/
    └── ARESTests/
        ├── HermesClientTests.swift
        └── ARESKitTests.swift
```

---

## Next Action

Two parallel tracks open:

1. **Sibling PR — Hermes wiring.** Replace
   `ares/runtime/hermes_bridge.py::cognition_query()` stub with a real
   Hermes invocation. The `memory_recall` field already pushed in the
   `cognitive_snapshot` payload is the contract for context injection;
   the persona prompt is already returned in `ChatResponse`. This
   unblocks the rest of Phase 2 (and gives the chat path a real brain).
2. **Phase 2 polish — overlay + hotkey.** Add `OverlayWindow` +
   `HotkeyManager` so ARES can be summoned without alt-tabbing.

After that:
- Phase 3 (voice loop) — VAD + STT + TTS on top of the working text
  pipeline.
- Phase 4 (Apple services) — Calendar/Reminders/Notes via osascript.
- Concrete `VectorStore` substrate (sqlite-vss / lancedb / chromadb).

The original "Matthew reviews this plan" gate is closed. Execution is
underway and visible on PR #2.
