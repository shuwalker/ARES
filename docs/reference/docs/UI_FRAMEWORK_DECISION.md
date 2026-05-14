# ARES UI Framework & Avatar Rendering Decision

## The Short Answer

**SwiftUI + Rive.** No contest for our use case.

## Why

We need to run on **4 Apple platforms**: macOS (primary), iOS, watchOS, visionOS. SwiftUI is the **only** framework that covers all four. Every other option requires a separate native Swift codebase for watchOS and visionOS anyway, so you'd end up writing Swift regardless — and then maintaining two codebases.

## Framework Comparison

| Framework | macOS | iOS | watchOS | visionOS | Native Feel | Avatar Support | Binary Size |
|-----------|-------|-----|---------|----------|-------------|----------------|-------------|
| **SwiftUI** | ✅ | ✅ | ✅ | ✅ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ~5-15MB |
| Tauri 2.0 | ✅ | ✅ | ❌ | ❌ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ~5-10MB |
| Electron | ✅ | ❌ | ❌ | ❌ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ~150-300MB |
| React Native | ✅ | ✅ | ❌ | ❌ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ~20-50MB |
| Flutter | ✅ | ✅ | ❌ | ❌ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ~15-40MB |

## Avatar/Animation Technology

### Rive (Primary Choice)

- Official SwiftUI runtime (not a hack, not community-maintained)
- State machines + data binding = drive expressions from LLM emotional output
- Audio playback built-in (lip sync potential)
- ~500KB runtime footprint
- Works across macOS, iOS, watchOS, visionOS

### Live2D (Upgrade Path)

- Best for anime-style 2D character art with detailed expressions
- Cubism SDK for Native supports Metal on Apple Silicon
- Requires C++ → ObjC → Swift bridging (more work, but documented)
- MotionSync plugin for real-time lip sync from audio

### Lottie (Not Recommended)

- After Effects export only — no interactivity, no state machines
- No watchOS/visionOS support
- Community-maintained macOS port
- Better for decorative animations than interactive avatars

## Architecture

```
Mac Studio (Brain)                          Thin Clients
┌──────────────────┐                         ┌──────────────┐
│  Hermes/ARES     │◄──WebSocket :9876─────►│  SwiftUI App  │
│  Python process   │    JSON + SSE           │  (macOS)      │
│                   │                         │  ┌──────────┐ │
│  ┌─────────────┐ │                         │  │ RiveView │ │
│  │ ZMQ Bus     │ │                         │  │ (avatar) │ │
│  │ voice/vision│ │                         │  └──────────┘ │
│  └─────────────┘ │                         │  ┌──────────┐ │
│                   │                         │  │ Chat UI  │ │
│  localhost:9876   │                         │  │(stream)  │ │
└──────────────────┘                         └──────────────┘
                                              ┌──────────────┐
                                              │ watchOS App  │
                                              │ (notifications│
                                              │  + voice in)  │
                                              └──────────────┘
                                              ┌──────────────┐
                                              │ visionOS App │
                                              │ (spatial      │
                                              │  avatar)      │
                                              └──────────────┘
```

## What We Already Have

The old ARES-App scaffold had the right architecture:
- `hermes_bridge.py` — HTTP boundary on :9876 (needs rewrite to WebSocket + ZMQ)
- `face_state.py` — 6 states with RGB/opacity/pulse/pupil (needs continuous interpolation)
- `identity.py` — Static identity (needs Lilith's 4-layer personality)

The SwiftUI app code (`ARESApp.swift`, `BlackFireSystem.swift`, `VoiceManager.swift`) is saved in `ares/reference/swift-ui/`.

## What Claude Code / SAM Contribute

- **Claude Code**: Async generator agent loop, two-tier compaction, hook system, stop hooks — these are *agent architecture* patterns, not UI. Applicable to the brain, not the face.
- **SAM**: SwiftUI-native Mac assistant with MessageBus, per-conversation SQLite, 2×2 continuation guidance, operation-based tool consolidation — good architecture, but their UI is standard chat, not an embodied avatar.

Neither changes the SwiftUI + Rive recommendation. Claude Code's patterns go into the Python brain. SAM's patterns go into the agent loop. The face is SwiftUI + Rive.

## Streaming Architecture

WebSocket (`URLSessionWebSocketTask`) for primary transport. Full-duplex, low latency, carries both text tokens and emotion/avatar control signals:

```
Hermes Python → WebSocket/SSE → SwiftUI App
    │                              │
    │  { type: "token",            │  AttributedString accumulator
    │    content: "...",            │  → Text view (streaming)
    │    emotion: "thinking" }     │
    │                              │  RiveViewModel → RiveView (avatar)
    │                              │  → State machine inputs
    │                              │
    │  { type: "face_state",       │
    │    state: "speaking",        │  AudioPlayer (voice output)
    │    expression: "happy" }      │
```

## Rive vs Live2D Decision

- Start with **Rive** — faster to prototype, interactive state machines, official Apple support, data binding from code
- Add **Live2D** later for anime/character art style if desired — requires C++ bridging but the SDK supports Metal on Apple Silicon natively
- Both can coexist: Rive for UI animations and lightweight avatar states, Live2D for high-fidelity character rendering when the user wants it

## Detailed Framework Notes

### SwiftUI (Winner)

- Only framework covering ALL 4 target platforms (macOS, iOS, watchOS, visionOS) with one language
- Native Metal/GPU access for avatar rendering
- `@Observable` + `AsyncStream` handles token streaming naturally
- Share Swift data models (`Package`) across all platforms
- Rive has first-class SwiftUI runtime with state machine support and data binding
- Live2D requires Metal/UIView bridging via `UIViewRepresentable` — more work but officially supported
- watchOS and visionOS are SwiftUI-first platforms — no other option reaches them

### Tauri 2.0 (Best Alternative for Web-First Teams)

- Rust + web frontend (React, Svelte, Vue)
- macOS + iOS + Android + Windows + Linux — but NO watchOS or visionOS
- Best avatar/animation ecosystem (WebGL, Live2D Web SDK, Rive web, Three.js, PixiJS)
- Tiny binary (~3-10MB vs ~150MB+ Electron)
- Would need separate native Swift apps for watchOS/visionOS anyway
- Two codebases: Tauri for primary, Swift for thin clients

### Electron (What ChatGPT/Claude Desktop Use)

- Proven at scale for desktop AI assistants
- Full web rendering — best avatar library support
- Heavy: ~150-300MB base, high RAM/CPU
- Desktop only — completely separate apps needed for iPhone/Watch/Vision Pro
- Doesn't feel native on macOS