# ARES — Artificial Reasoning Entity System

ARES is a persistent AI entity with its own drives, voice, face, and presence. Built in public as a YouTube series ("Building Ares"). The entity runs on a Mac Studio, talks through Hermes Agent's tool system, uses JROS for robotics/embodiment, and presents through a web UI.

**Not a chatbot. Not a Mac app. Not a web wrapper. An artificial person, built one brick at a time.**

## Repository Structure

```
ARES/
├── Package.swift          # Swift Package Manager manifest
├── Sources/               # Native macOS app (SwiftUI)
│   ├── ARES/              # Main app — Companion, Hub, voice, avatar
│   └── AresTaskCLI/       # CLI tool for task management
├── webui/                 # ARES Web UI (Python web server)
│   ├── api/               # Backend — server, streaming, auth, updates
│   ├── static/            # Frontend — HTML, JS, CSS, icons
│   ├── server.py          # Entry point
│   ├── requirements.txt   # Python dependencies
│   ├── .venv/             # Self-contained venv (not committed)
│   └── tests/             # Test suite
├── tools/                 # Standalone tools
│   └── mail-butler/       # IMAP mail cleaner with ARES classification rules
└── .gitignore
```

## Quick Start

### Web UI

```bash
cd webui

# Create venv (Python 3.11+)
python3.11 -m venv .venv
.venv/bin/pip install pyyaml cryptography edge-tts psutil
.venv/bin/pip install -e ~/.hermes/hermes-agent  # Hermes Agent (editable)

# Configure
cp .env.example .env
# Edit .env — set HERMES_WEBUI_PASSWORD

# Run
.venv/bin/python server.py
# → http://localhost:8787
```

### Native App

```bash
swift build
open .build/arm64-apple-macosx/debug/ARES.app
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│              ARES Web UI                         │
│         webui/ (self-contained)                  │
│                                                  │
│  ┌───────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Persona    │  │ Embodiment   │  │ Animated │ │
│  │ Picker     │  │ Picker       │  │ Eyes     │ │
│  │ (JROS YAML)│  │ (JROS caps)  │  │ (CSS/SVG)│ │
│  └─────┬─────┘  └──────┬───────┘  └────┬─────┘ │
│        │                │               │       │
│        ▼                ▼               ▼       │
│  ┌──────────────────────────────────────────┐  │
│  │     Hermes Agent Loop (in-process)       │  │
│  │  LLM: Ollama Cloud (GLM-5.2, xhigh)      │  │
│  │  Routing: Hermes provider routing        │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
         │                         │
         ▼                         ▼
   ┌──────────┐            ┌──────────────┐
   │ Ollama   │            │ JROS Daemon  │
   │ Cloud    │            │ (NDJSON      │
   │ (GLM-5.2)│            │  Unix socket) │
   └──────────┘            └──────────────┘
```

## Key Decisions

1. **LLM goes through Hermes Agent, not Ollama directly.** The agent loop (tool dispatch, sessions, memory, streaming, context compression, skills) IS the value.
2. **Web UI lives in `webui/`** — self-contained: own venv, own auth, own deps. One repo with the Swift app.
3. **JROS integration is additive.** JROS personas inject into the Hermes system prompt. JROS tools register into the Hermes tool registry. The agent loop stays Hermes's.
4. **ARES Swift app wraps the Web UI in WKWebView** for native window, voice, and the animated eyes avatar.

## Update Checking

The Web UI checks for updates on three repos:
- **ARES** — this repo (`shuwalker/ARES`)
- **Hermes** — the agent engine (`NousResearch/hermes-agent`)
- **JROS** — robotics/embodiment (`JenkinsRobotics/JROS`)

## Credits

The ARES Web UI (`webui/`) is forked from [hermes-webui](https://github.com/nesquena/hermes-webui) by the Hermes Web UI Contributors, originally licensed under MIT. See `LICENSE` for the full stacked license.

## Owner

Matthew Jenkins (shuwalker) · Jenkins Robotics · Built on Mac Studio (M1 Max, 32GB)