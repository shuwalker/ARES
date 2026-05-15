# AIAvatarKit Audit Report

## Overview

AIAvatarKit is a Python/JS framework for building AI-powered avatar systems with:
- VRM 3D model loading via Three.js + @pixiv/three-vrm
- Live2D-style expression system
- Real-time lip sync (viseme mapping)
- Procedural idle animation (breathing, body sway, blinking)
- WebSocket-based bidirectional communication
- LLM integration with streaming responses
- STT/TTS pipeline with sentence-level chunking

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│   VRM Viewer    │ ◄──────────────► │   Python Server   │
│   (Three.js)    │     JSON msgs     │   (FastAPI)       │
│                 │                    │                   │
│ • vrm-idle.js   │                    │ • LLM Adapter     │
│ • lipsync.js    │                    │ • STT/TTS         │
│ • blink.js      │                    │ • Character Svc   │
│ • aiavatar.js   │                    │ • Memory/Tools    │
└─────────────────┘                    └──────────────────┘
```

## Key Patterns Worth Porting to ARES-Face

### 1. VRM Idle Animation System (vrm-idle.js)

**Source**: vrm-idle.js (446 lines)

The `VRMIdle` class provides:
- **Body sway**: fBm noise across spine bones with SmoothDamp
- **Breathing**: Sinusoidal chest expansion mapped to VRM Humanoid bones
- **Blinking**: Random interval (3-6s), smooth close/open with configurable speed
- **Expression mapping**: Direct blend shape weights per expression name
- **Viseme system**: 14 mouth shapes → blend shape weights with smoothing

**Swift Port**: Already ported to `AvatarAnimation.swift` — body sway, breathing, blink, expression, viseme systems all present.

### 2. Expression-Driven State Machine (binding.py)

The character binding maps internal states to avatar expressions:

```python
# Expression priority system:
# Speaking > Emotion > Idle
# Expressions blend with configurable weights and durations
```

**Swift Port Pattern**: Use `AvatarExpressionMap.expressionWeights` which maps ARES cognitive states to ARKit blend shapes. The priority system is already in our state machine (`.thinking` > `.speaking` > `.idle`).

### 3. VRM Model Loader (loader.py)

```python
class CharacterLoader:
    # Loads VRM files, resolves textures, extracts blend shapes
    # Maps VRM Humanoid bones to a standardized skeleton
    # Supports both VRM 0.x and VRM 1.x formats
```

**Swift Port**: Ported to `ModelAvatarLoader.swift` — uses RealityKit's `ModelEntity.loadModel()` for USDZ with skeleton + blend shapes. VRM requires conversion to USDZ (Python pipeline with VRM-to-GLB-to-USDZ).

### 4. WebSocket Protocol (adapter/websocket/server.py)

Bidirectional JSON messages:
- `{"type": "response_start"}` — LLM begins responding
- `{"type": "response_chunk", "text": "..."}` — streaming tokens
- `{"type": "response_end"}` — LLM done
- `{"type": "expression", "name": "happy", "weight": 0.8}` — set expression
- `{"type": "viseme", "name": "A", "weight": 0.5}` — lip sync
- `{"type": "motion", "clip": "wave"}` — play animation

**Swift Port**: Our `HermesAdapter` WebSocket already handles streaming tokens. We need to add expression/viseme/motion message types to the `ARESEvent` enum.

### 5. Lip Sync System (lipsync.js)

Viseme mapping with time-based interpolation:
- 14 viseme shapes (A, I, U, E, O, etc.)
- Mouth open amount → viseme blend weight
- Smooth interpolation between shapes (0.1s transition)

**Swift Port**: Our `VisemeSystem` struct in `AvatarAnimation.swift` already has this — `MOUTH_TO_VISEME` dictionary maps mouth positions to ARKit blend shapes.

### 6. Admin Dashboard (admin/static/index.html)

This is the closest to our Dashboard views — a web UI for:
- Character management (create, configure, switch)
- LLM provider settings
- TTS/STT configuration
- Live metrics
- Conversation logs

**Swift Port Pattern**: Already covered by our `SessionsView`, `SkillsView`, `CronView`, `ConfigView`, `PersonaSlidersView`.

## Patterns NOT Worth Porting

1. **VRChat OSC integration** (face/vrchat.py, animation/vrchat.py) — We're building a native Mac app, not a VRChat avatar
2. **PostgreSQL/SQLite character repository** — We use Hermes Dashboard API
3. **Python async FastAPI server** — We use SwiftUI + WebSocket directly
4. **Motion PNG tuber example** — Low-effort fallback, not relevant
5. **STT audio processor** — We use Apple's Speech framework natively

## Critical Files Mapping

| AIAvatarKit File | ARES-Face Equivalent | Status |
|---|---|---|
| vrm-idle.js | AvatarAnimation.swift | ✅ Ported |
| lipsync.js | AvatarAnimation.swift (VisemeSystem) | ✅ Ported |
| blink.js | AvatarAnimation.swift (BlinkSystem) | ✅ Ported |
| aiavatar.js | BrainConnection.swift | ✅ Equivalent |
| loader.py | ModelAvatarLoader.swift | ✅ Ported |
| binding.py | AvatarExpressionMap | ✅ Ported |
| service.py | HermesAdapter + BrainConnection | ✅ Equivalent |
| websocket/server.py | HermesAdapter WebSocket | ✅ Equivalent |

## Recommended Next Steps

1. **Add VRM → USDZ conversion pipeline** (Python script using VRM-to-GLB → RealityComposer → USDZ)
2. **Add expression/viseme WebSocket message types** to ARES protocol
3. **Implement animation clip system** — load USDZ animation clips alongside models
4. **Add sentence-level TTS chunking** — send visemes per-sentence, not per-token
