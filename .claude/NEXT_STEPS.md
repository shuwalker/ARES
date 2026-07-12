# ARES — Next Steps (Phase 2)

**Current Status:** v0.1.0 modular framework complete, vision validated  
**Build:** Clean (1.09s), tests passing (9/9)  
**Branch:** `feature/companion-parity`

---

## What's Done ✅

**Framework:**
- 14 contracts + 14 dummies in ARESCore
- Production safety (rejects dummies with WiringError)
- Fast build, contract tests passing

**Functional:**
- 5 UI widgets (Avatar, Chat, History, BackendPicker, Perception)
- 2 gateway providers (Ollama, Hermes)
- Dashboard with configurable layout (JSON persistence)
- Clean file organization (64 files removed)

**Documentation:**
- ARCHITECTURE.md (definitive structure)
- VISION_VALIDATION.md (proof of alignment)
- README.md (updated for v0.1.0)

---

## What's NOT Done (Deferred to Phase 2)

### 1. Embodiment Integration (Avatar Animation)
**What it is:** Real 3D avatar, animates based on perception + emotion  
**Current state:** AvatarWidget renders static face with emotion states  
**Blocker:** HyperFrames/HyperDirector integration not complete  

**To implement:**
```
HyperFrames (HTML→MP4 renderer)
        ↓
HyperDirector (Hermes skill for video production)
        ↓
Perception → EventBus → Mimicry → Avatar animation
```

**Files to create:**
- `ARES/Services/HyperFramesClient.swift` — HTTP client to ~/hyperframes
- `ARES/Views/RealAvatarView.swift` — renders MP4 stream from HyperFrames
- Integration with EventBus (subscribe to perception, publish animation frames)

**Estimated effort:** 3-4 hours (HyperFrames API is well-defined)

---

### 2. Voice Engine Integration
**What it is:** Text-to-speech (TTS) + speech-to-text (STT)  
**Current state:** VoiceEngine contract defined, DummyVoiceEngine logs calls  
**Blocker:** Kokoro TTS not integrated, Whisper STT not hooked up  

**To implement:**
```
Perceiver → Whisper STT → transcript
User input (text)
        ↓
CompanionChatService → response text
        ↓
Kokoro TTS → audio → speaker
```

**Files to modify:**
- `ARES/Services/VoiceService.swift` (new) — wraps Kokoro + Whisper
- `ARES/Views/CompanionView.swift` — add audio input/output controls

**Dependencies:**
- Kokoro (local TTS, already available in ~/.hermes/)
- Whisper (local STT, via MCP server or direct)

**Estimated effort:** 2-3 hours

---

### 3. Memory Browser UI
**What it is:** User can view, edit, delete memory entries  
**Current state:** MemoryStore + SQLiteMemoryStore contracts complete, no UI  

**To implement:**
```
MemoryBrowserView
├── Memory list (searchable, filterable)
├── Memory detail (editable)
└── Add/delete UI
```

**Files to create:**
- `ARES/Views/MemoryBrowserView.swift` — grid of memory entries
- `ARES/Views/MemoryDetailView.swift` — edit form

**Data flow:**
```
CompanionChatService.memory.query()  → [MemoryEntry]
                     .update()       ← user edits
                     .delete()       ← user deletes
```

**Estimated effort:** 2 hours

---

### 4. Learned Routing Policies
**What it is:** Gateway router picks best backend based on capability, speed, cost  
**Current state:** Manual routing via BackendPickerWidget (user chooses)  

**To implement:**
```
enum RoutingPolicy {
    case manual           // user picks (current)
    case fastest          // latency check, pick fastest
    case capabilityMatch  // need vision? route to qwen3-vl
    case learned          // past interactions shape future routing
}
```

**Logic:**
- Store latency measurements in MemoryStore
- Store capability usage patterns (when vision was needed, when tools were used)
- Train simple decision tree from patterns
- Route future requests based on learned patterns

**Files to create:**
- `ARES/Services/GatewayRouter.swift` — routing logic + policies

**Estimated effort:** 4-5 hours

---

### 5. Persona Adaptation
**What it is:** ARES learns from interactions and changes its communication style  
**Current state:** PersonaProvider contract complete, DummyPersonaProvider is no-op  

**To implement:**
```
Each interaction → PersonaProvider.learn(interaction)
Periodic → PersonaProvider.reflect() → update traits
Emit → PersonaProvider.describe() → changed system prompt
```

**Logic:**
- Track user preferences (technical depth, formality, humor)
- Adjust communication style based on feedback
- Reflect weekly (via Scheduler)
- Persist learned traits to Identity

**Files to modify:**
- `ARESCore/Dummies/DummyPersonaProvider.swift` → real implementation
- `ARES/Services/PersonaService.swift` (new)

**Estimated effort:** 3-4 hours

---

### 6. Real Perception (Continuous Sensing)
**What it is:** Camera/screen/audio always on, feeds perception pipeline  
**Current state:** PerceptionWidget shows camera preview, can capture frames  

**To implement:**
```
AVCaptureSession (camera)
        ↓
Perceiver.observe() → [Perception]
        ↓
EventBus.publish(perceiver_frame)
        ↓
Subscribers:
  - Mimicry (animate face)
  - MemoryStore (episodic memories)
  - WorldModel (update scene)
```

**Privacy & performance:**
- User opt-in per sensor
- Configurable sampling (continuous vs on-demand)
- Processing on-device (no cloud)

**Files to create:**
- `ARES/Services/ContinuousPerceptionService.swift` — manages sensors
- `ARES/Views/PerceptionSettings.swift` — privacy controls

**Estimated effort:** 3-4 hours

---

## Recommended Order (Priority)

1. **Memory Browser UI** (2 hours) — enables user to inspect/edit their memory
2. **Voice Engine Integration** (2-3 hours) — enable talking to ARES
3. **Embodiment Integration** (3-4 hours) — make avatar animate (blocking presence)
4. **Learned Routing** (4-5 hours) — smart backend selection
5. **Persona Adaptation** (3-4 hours) — ARES becomes more like the user
6. **Real Perception** (3-4 hours) — continuous sensing

**Rationale:** Start with UI (memory browser), then voice (core interaction), then body (presence), then smarts (routing & persona).

---

## Long-Term Vision (v0.2-1.0)

**v0.2.0 — Embodiment:**
- Real 3D avatar (HyperFrames)
- Voice I/O (Kokoro + Whisper)
- Perception → Animation pipeline
- Memory browser UI
- Latency < 200ms (avatar → response → speech)

**v0.3.0 — Self-Improvement:**
- Persona adaptation (learns communication style)
- Learned routing (picks best backend by capability)
- Reflection workflows (weekly self-model updates)
- Episodic memory visualization
- Identity evolution

**v1.0.0 — Embodiment Swap:**
- iOS target (watch-friendly)
- iPad target (big screen)
- Robot target (JP01, when ready)
- Single codebase, swappable body
- iCloud sync (optional, not default)

---

## What NOT to Do (Out of Scope)

❌ Hermes parity — use Hermes via GatewayProvider, don't embed it  
❌ Multi-user — personal companion per device  
❌ Cloud sync by default — local-first, iCloud sync only  
❌ 18 themes — single design language  
❌ Tool discovery UI — tools are declared, not browsed  

---

## Getting Started

```bash
# Current state
git log --oneline -5
# 0519d29 docs: add VISION_VALIDATION.md
# 94bbd9c docs: add definitive ARCHITECTURE.md
# 75f8a0c chore: major cleanup
# d918c77 clarify: BackendPickerWidget

# Verify build is clean
swift build
swift test

# Pick a task from "Recommended Order" above
# Create a feature branch
git checkout -b feature/memory-browser-ui
```

---

## Reference

- **Framework docs:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Vision alignment:** [VISION_VALIDATION.md](VISION_VALIDATION.md)
- **Build system:** [README.md](README.md)
- **Development guide:** [CLAUDE.md](CLAUDE.md)

---

**Ready to ship v0.1.0.** Framework is solid, tests pass, build is fast. Next step: make it sing (embodiment + voice).
