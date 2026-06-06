# ARES — Autonomous Reasoning & Execution System

**v0.0.0 — Baseline Release**

A native macOS/iOS app built with SwiftUI. ARES connects to the Hermes Agent Gateway to provide a full-featured AI companion — tools, memory, skills, and real-time streaming — the same engine that powers the Hermes TUI, now in a native Apple interface.

---

## What It Does

The ARES app has two main areas:

### Companion Tab
Real-time streaming chat with the Hermes agent. Not a raw LLM — a full agent with:
- **Tools** — terminal, file ops, web search, code execution
- **Memory** — persistent context across sessions
- **Skills** — specialized workflows loaded on demand
- **Session continuity** — conversation history persists via Gateway API

Messages stream token-by-token. Session history is loaded from `localhost:8642/api/sessions`.

### Hub Tab
System dashboard showing running agents, services, and infrastructure status.

---

## Architecture

```
┌─────────────┐     HTTP/SSE      ┌──────────────────┐
│  ARES App   │ ───────────────── │  Hermes Gateway   │
│  (SwiftUI)  │   localhost:8642  │  (localhost:8642)  │
└─────────────┘                   └────────┬─────────┘
                                          │
                                    ┌─────┴──────┐
                                    │  Agent Core │
                                    │  (tools,    │
                                    │   memory,   │
                                    │   skills)   │
                                    └────────────┘
```

- **ARES App** — native SwiftUI, targets macOS (ARESMac), iPad (ARESPad), iPhone (ARESPhone)
- **Hermes Gateway** — local HTTP API at `localhost:8642`; provides `/v1/chat/completions`, `/api/sessions`, `/v1/models`, `/v1/capabilities`
- **Agent Core** — the same Hermes agent engine that powers the TUI; handles tool calls, memory, skill loading, and multi-step reasoning

### Key Files

| Path | Purpose |
|------|---------|
| `Package.swift` | SPM manifest; defines ARESCore library + ARES executable |
| `ARES-Desktop/Sources/ARES/` | Main app source (App, Views, Services) |
| `ARES-Desktop/Sources/ARESCore/` | Shared core library |
| `ARES-Desktop/Sources/ARES/Services/Companion/` | Gateway client, streaming, config |
| `ARES-Desktop/Sources/ARES/Views/Companion/` | Chat UI, session history, model picker |
| `ARES-Desktop/Sources/ARES/Views/Hub/` | Dashboard, agent cards, service monitors |
| `Info.plist.template` | App bundle metadata (version, identifier) |
| `VERSION` | Current version number |

---

## Building & Running

```bash
# Prerequisites: Xcode 16+, macOS 15+ (Sequoia)

# Build (debug)
cd ~/GitHub/ARES
swift build

# Build (release)
swift build -c release

# Create app bundle (sets version from VERSION file)
python3 scripts/create_app_bundle.py

# Run the binary
.build/debug/ARES

# Or open in Xcode
open Package.swift
```

### Gateway Setup

The Companion requires the Hermes Gateway API running locally:

```bash
# Enable the api_server platform in Hermes config
hermes config set gateway.platforms.api_server.enabled true
hermes config set gateway.platforms.api_server.key YOUR_API_KEY

# Or add to ~/.hermes/.env:
echo "API_SERVER_KEY=your_api_key_here" >> ~/.hermes/.env

# Restart the gateway
hermes gateway restart
```

The app auto-detects the API key from `~/.hermes/.env` (`API_SERVER_KEY`).

---

## The Core Standard

Every decision about tooling and output format passes this test:

> *"Could a skilled freelance human pick up what ARES produced and continue the work — without special tools or instructions?"*

- Scripts → Markdown / standard formats (not custom)
- Video projects → DaVinci Resolve (`.drp`)
- Workflows → visible and editable
- Research → Markdown files
- Memory → plain TOML and JSONL

---

## Episode Roadmap

ARES is being built as a YouTube series: **"Building Ares"**

| Episode | Milestone | Status |
|---------|-----------|--------|
| 1 | Device adoption — ARES perceives hardware | ✅ |
| 2 | Companion chat — real-time streaming with agent | ✅ (v0.0.0) |
| 3 | Hub dashboard — agent/service monitoring | 🔄 Next |
| 4 | Voice interface | 📋 Planned |
| 5 | Vision — camera/screen perception | 📋 Planned |
| 6 | Memory — persistent context across sessions | 📋 Planned |
| 7 | Skills — specialized workflow engine | 📋 Planned |
| 8 | Autonomous operation — self-directed task execution | 📋 Planned |

See [SERIES_MASTER_PLAN.md](SERIES_MASTER_PLAN.md) for the full plan.

---

## Reusable Recipes

- [YouTube Playlist Research Pipeline](docs/recipes/youtube-playlist-research-pipeline.md)
- [Video Production Workflow](docs/recipes/video-production-workflow.md)

---

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Swift 6.1, SwiftUI |
| Agent Backend | Hermes Agent Gateway (localhost:8642) |
| Streaming | SSE over HTTP (OpenAI-compatible) |
| Session Storage | Hermes Gateway `/api/sessions` |
| Local Fallback | `hermes --yolo chat` CLI |
| macOS Target | 15.0 (Sequoia) |
| iOS Target | 17.0 |
| Architecture | ARESCore (shared) + ARES (platform-specific) |

---

## License

Private repo. All rights reserved.