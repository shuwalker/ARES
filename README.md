<p align="center">
  <img src="docs/assets/ares-wordmark.png" alt="ARES" width="180">
</p>

<p align="center">
  An open-source embodied AI operating system.<br>
  Deploy a persistent intelligence to orchestrate your local stack, automate complex workflows, and interact through a native AI avatar.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#features">Features</a> ·
  <a href="#character-avatar-browser">Characters</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="webui/FORK_CHANGES.md">Changelog</a> ·
  <a href="#credits">Credits</a>
</p>

<p align="center">
  <a href="https://github.com/shuwalker/ARES/releases"><img src="https://img.shields.io/badge/status-beta-orange" alt="Status: Beta"></a>
  <a href="https://github.com/shuwalker/ARES/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License: AGPL-3.0"></a>
  <a href="https://github.com/NousResearch/hermes-agent"><img src="https://img.shields.io/badge/powered%20by-Hermes%20Agent-purple" alt="Powered by Hermes Agent"></a>
  <a href="https://github.com/JenkinsRobotics/JROS"><img src="https://img.shields.io/badge/robotics-JROS-cyan" alt="JROS Robotics"></a>
</p>

<p align="center">
  <img src="docs/assets/webui-screenshot.png" alt="ARES Web UI">
</p>

<p align="center">
  <img src="docs/assets/character-tab-showcase.png" alt="ARES character avatar browser">
</p>

---

## Quick Start

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES/webui

# Create venv (Python 3.11-3.13)
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Optional voice and system-health support
.venv/bin/pip install edge-tts psutil

# Install Hermes Agent (dependency)
mkdir -p ~/.hermes
git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent
.venv/bin/pip install -e ~/.hermes/hermes-agent  # Hermes Agent (editable)

# Configure
cp .env.example .env
# Edit .env — set HERMES_WEBUI_PASSWORD

# Run
.venv/bin/python server.py
# → http://localhost:8787
```

### Native macOS App

```bash
swift run ARES
```

## Features

- **Persistent Entity** — ARES is not a chatbot. It's a continuous intelligence with memory, drives, and presence across sessions.
- **Web UI** — Self-contained Python server with streaming, session management, hot-reload, and password auth. Works on any device over Tailscale.
- **Backend Selector** — Switch between Hermes, JROS, or Hybrid mode per-conversation. JROS personas inject into the agent loop.
- **Character Avatar Browser** — 14 visual character personas (HAL 9000, GLaDOS, Jarvis, TARS, Bender, Helldiver, and more) with card art, traits, lore, and active identity selection.
- **Native macOS App** — SwiftUI app wraps the Web UI in WKWebView with native window, voice (edge-tts), and animated 3D avatar eyes.
- **Hot Reload** — Edit Python files → server auto-restarts in ~2s. Edit static files → browser auto-reloads. Zero downtime for static, ~2s blip for Python.
- **Hermes Agent Integration** — Full tool system: terminal, file ops, web search, code execution, MCP, skills, memory, delegation, cron jobs.
- **Multi-Model Routing** — Cloud-first (GLM-5.2, DeepSeek V4, Qwen 3.5) with local fallback (Gemma4). Reasoning effort configurable per-session.
- **Mail Butler** — IMAP-based mail cleaner with 321 classification rules. Server-side, no Mail.app dependency.
- **Built in Public** — Every episode of the build is documented as part of the "Building Ares" YouTube series.

## Character Avatar Browser

ARES now exposes the persona system as a real product surface instead of a hidden dropdown. The character tab loads JROS `character/v1` YAML data, displays avatar card art, shows role/voice/trait/lore detail, and lets the user set the active ARES identity from the browser.

- **Visual roster:** 14 built-in character cards are checked into `webui/static/persona-cards/` and `webui/static/characters/`.
- **Schema-backed:** The browser reads JROS character data through `webui/api/characters.py` and `/api/ares/characters`.
- **Runtime control:** Selecting a character writes the active persona through the existing ARES persona API.

<p align="center">
  <img src="docs/assets/character-tab-showcase.png" alt="ARES character tab with avatar cards and trait detail">
</p>

## Architecture

```
┌──────────────────────────────────────────────────┐
│              ARES Web UI                         │
│         webui/ (self-contained)                  │
│                                                  │
│  ┌───────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Character  │  │ Backend      │  │ Animated │ │
│  │ Browser    │  │ Selector     │  │ Eyes     │ │
│  │ (JROS YAML)│  │ (Hermes/JROS)│  │ (CSS/SVG)│ │
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

## Repository Structure

```
ARES/
├── Package.swift          # Swift Package Manager manifest
├── Sources/               # Native macOS app (SwiftUI)
│   ├── ARES/              # Main app — Companion, Hub, voice, avatar
│   └── AresTaskCLI/       # CLI tool for task management
├── webui/                 # ARES Web UI (Python web server)
│   ├── api/               # Backend — server, streaming, auth, hot-reload
│   ├── static/            # Frontend — HTML, JS, CSS, icons, character art
│   ├── server.py          # Entry point
│   ├── requirements.txt   # Python dependencies
│   └── tests/             # Test suite
├── tools/                 # Standalone tools
│   ├── email_ai_assistant/ # Native Mail.app AI assistant (classify, draft, auto-clean)
│   ├── mcp-bootstrap/     # Local vs remote/server MCP setup and verification
│   └── safari-mcp-bootstrap/ # Safari MCP setup/doctor for macOS automation
└── docs/assets/           # README images and branding
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

The ARES Web UI (`webui/`) is forked from [hermes-webui](https://github.com/nesquena/hermes-webui) by the Hermes Web UI Contributors, originally licensed under MIT. See `LICENSE` for ARES, `COMMERCIAL-LICENSE.md` for commercial licensing, and `webui/LICENSE` for the preserved upstream MIT notice.

## Owner

Matthew Jenkins (shuwalker) · Jenkins Robotics

## Star History

<a href="https://www.star-history.com/?repos=shuwalker/ARES&type=date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date" />
 </picture>
</a>
