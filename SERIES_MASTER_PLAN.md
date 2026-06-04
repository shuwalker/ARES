# ARES — Series Master Plan

## The Product

Ares is the **native Mac shell that unifies your AI tools** — not another chat app, not another Electron wrapper. One SwiftUI window that connects to the backends you already run and makes them feel like one app.

**The problem:** Every AI user has 15 tabs and 8 apps for different AI tools. None of them talk to each other. Every new GitHub repo = another localhost port, another login, another disconnected experience.

**The solution:** Ares speaks to existing backends via their REST APIs and renders native macOS interfaces. Same engines. One window. No rewriting required.

---

## Architecture: The Unifier

```
┌─────────────────────────────────────────────┐
│            Ares Native Shell (SwiftUI)       │
│         One window. Every AI tool.           │
├─────────────────────────────────────────────┤
│           Adapter Protocol Layer             │
│   "Any repo with an API → native UI"        │
├────────┬──────────┬──────────┬───────────────┤
│ SAM    │ Odysseus │ Hermes   │ ComfyUI │ ... │
│ Chat   │ Notes    │ Ops      │ Images  │     │
│ Engine │ Research │ Cron     │ Gen     │     │
│ Voice  │ Cookbook │ Skills   │         │     │
│ MCP    │ Compare  │ Memory   │         │     │
├────────┴──────────┴──────────┴───────────────┤
│         Existing Backends (already running)  │
│   localhost:8642   localhost:7000   :8188    │
└─────────────────────────────────────────────┘
```

### Adapter Protocol

The core moat. Each adapter is ~200 lines of Swift that:

1. **Discovers** — checks if a backend is running (health endpoint)
2. **Translates** — maps REST API responses to native SwiftUI models
3. **Renders** — native views for the top 80% of features
4. **Falls back** — embedded web view for deep features that need the full web UI
5. **Self-heals** — Ares AI monitors API drift, alerts, and patches adapters

**Ares manages the cons:**

| Con | How Ares AI Handles It |
|---|---|
| API drift (backends change) | Ares monitors adapter health, detects breakage, patches or alerts automatically |
| Backends not running | Ares auto-discovers + auto-launches (already does this for Hermes gateway) |
| Shallow features vs deep | Native UI for daily workflow, one-click web fallback for deep sessions |
| "Jack of all trades" perception | Positioned as mission control, not replacement — you CAN still open the full web UI |
| Adapter maintenance | Open source the protocol → community writes adapters for their favorite repos |

---

## Episode Structure

Episodes defined by **achieved capability**, not a fixed cap. Each episode is a complete story arc with a working deliverable.

### Ep 1 — "Ares Comes Online"
**Deliverable:** Working native Mac app that connects to real backends
- Fix app launch (SwiftUI lifecycle, WindowGroup)
- Companion tab: SAM chat engine → Hermes gateway (already works, fix the shell)
- Hub tab: Live dashboard showing real backend status (Hermes, Ollama, SearXNG)
- Office tab: Agent cards + backend discovery
- Settings: SAM preferences + Ares backend configuration
- Bootstrap flow: dependency scan → one-click install
- **Story:** From dead app to live dashboard. First boot. The lights come on.

### Ep 2 — "Ares Gets Eyes"
**Deliverable:** Vision and real-time system awareness
- Computer use integration (desktop screenshots, mouse/keyboard through Ares)
- Hub shows live system state: model status, VRAM usage, running processes
- Hardware scan: Odysseus cookbook adapter → native hardware report
- Vision model integration for screen understanding
- **Story:** Ares can see your screen, your system, your hardware. Not just chat — perception.

### Ep 3 — "Ares Picks a Brain"
**Deliverable:** Intelligent model routing + benchmarking
- Model picker with real benchmarks (not just names)
- Cookbook-style model recommendation: "for your hardware, run X"
- One-click model pull/serve from within Ares
- Smart routing: Ares picks the right model for the task
- Budget tracking: local vs cloud cost visibility
- **Story:** Ares knows which brain to use for which job. And tells you why.

### Ep 4 — "Ares Creates"
**Deliverable:** Content creation pipeline inside Ares
- ComfyUI adapter: native image generation UI → ComfyUI API
- Document editor (Dodo file editor wired to real files)
- Research adapter: Odysseus deep research → native UI
- Compare adapter: side-by-side model comparison
- Gallery for outputs
- **Story:** Ares doesn't just think — it makes things. Images, documents, research.

### Ep 5 — "Ares Runs Itself"
**Deliverable:** Autonomous personal OS
- Office tab: task execution with approval loop
- Cron jobs visible + manageable in native UI (Dodo kanban)
- Skill launcher: browse + run Hermes skills from native UI
- Session browser: live session management
- Terminal: embedded SwiftTerm for direct control
- **Story:** Ares schedules, runs tasks, manages itself. You approve, it executes.

### Ep 6 — "Ares Remembers"
**Deliverable:** Knowledge base + persistent memory
- Memory adapter: Hermes memory → native searchable UI
- Notes adapter: Odysseus notes → native sidebar
- Knowledge base: research ingest → `/Volumes/Jenkins_Robotics/03_Knowledge`
- Vector search: find anything across conversations, notes, docs
- Skill authoring: create/edit skills from native UI
- **Story:** Nothing is forgotten. Everything is searchable. Ares builds its own library.

### Ep 7+ — "Ares Meets [X]"  (ongoing)
**Deliverable:** Each new integration is its own mini-episode
- "Ares Meets Open Interpreter" → adapter
- "Ares Meets OpenAI Codex" → adapter
- "Ares Meets [Your Repo]" → community adapters
- **Story:** Infinite fuel. Every new integration is content. Community driven.

---

## What Already Exists (No Rebuild Needed)

| Component | Files | Status | Role in Ares |
|---|---|---|---|
| SAM (vendored) | 247 Swift files | Working | Chat engine, voice, MCP, MLX on-device inference |
| Dodo (embedded) | 67 Swift files | Working UI | Session browser, terminal, skills, kanban, file editor |
| SwiftTerm (vendored) | Working | Terminal emulator for Office tab |
| Ares Python daemon | ~15 Python files | Running | ZeroMQ IPC, telemetry, CLI |
| Odysseus | 226K lines (clone) | Working | Backend API for notes, research, cookbook, compare, models |

## What's Broken (Patch, Don't Rebuild)

- App launch — SwiftUI WindowGroup lifecycle
- Office tab — empty, needs Dodo views wired in
- Hub tab — static, needs real API calls
- Bootstrap — rough UX
- Roadmap + README — outdated, describe v1-v4 feature model

## File Architecture

| Zone | Path | Purpose | Privacy |
|---|---|---|---|
| Public repo | `~/GitHub/ARES/` | Shareable code, adapters, docs, viewer-installable assets | Public |
| Private runtime | `~/.ares/config/` | Ares runtime config (ares.toml) | Never commit |
| Hermes config | `~/.hermes/` | SOUL.md, skills, config.yaml | Never commit |
| Practice zone | `~/Desktop` | Craft, episode work, scratch | Private |
| Release archive | `/Volumes/Jenkins_Robotics/` | Finished episode folders + knowledge base | Private |

---

## Adapter Development Guide

Each adapter follows this pattern:

```swift
protocol AresAdapter {
    var id: String { get }                    // "odysseus", "comfyui", etc.
    var name: String { get }                  // Display name
    var healthEndpoint: String { get }        // "/api/health"
    var baseURL: String { get }              // "http://localhost:7000"
    
    func isRunning() async -> Bool            // Health check
    func discover() async -> [AresFeature]    // What features are available
    func view(for feature: AresFeature) -> AnyView  // Native SwiftUI view
    func webViewURL(for feature: AresFeature) -> URL?  // Web fallback
}
```

Ares AI monitors adapters at runtime:
- Health checks every 30s
- If an adapter fails → alert + attempt auto-restart
- If API response schema changes → log drift + notify
- Community can submit adapters as PRs

---

## YouTube Narrative Arc

| Episode | Hook | Visual Payoff |
|---|---|---|
| Ep 1 | "I built a Mac app that talks to 5 AI tools at once" | App launching, tabs populating with real data |
| Ep 2 | "Now it can see your screen" | Desktop capture, system stats, vision demo |
| Ep 3 | "It knows which AI to use" | Model benchmark chart, one-click serve |
| Ep 4 | "It creates things" | Image gen, document, research — all from one window |
| Ep 5 | "It runs itself" | Cron jobs firing, tasks executing, terminal working |
| Ep 6 | "It remembers everything" | Search across all conversations, notes, docs |
| Ep 7+ | "Ares meets [X]" | New integration = new episode = infinite content |