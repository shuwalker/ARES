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
  <a href="#native-app">Native App</a> ·
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
.venv/bin/pip install -e ~/.hermes/hermes-agent

# Configure
cp .env.example .env
# Edit .env — set HERMES_WEBUI_PASSWORD

# Run
.venv/bin/python server.py
# → http://localhost:8787
```

## Native App

The merged repo includes two Swift app surfaces:

- `ARES` — primary native macOS Mission Control app under `ARES-Desktop/Sources/`.
- `ARESLegacy` — earlier lightweight SwiftUI app under `Sources/ARES/`, kept for reference and migration.

```bash
# from repo root
swift build
swift test
swift run ARES
```

ARES uses a batteries-included/pro-extensions architecture:

- **Native interface:** SwiftUI Mission Control UI, dashboard, companion surfaces, terminal/files/kanban/skills/automation views.
- **Native capabilities:** local SQLite memory, Apple voice/perception hooks, local event bus, configured provider routing.
- **Framework adapters:** Hermes and JROS are peer full agentic frameworks ARES can use alone or together. ARES-native services, Ollama/local models, cloud providers, and workflow tools can also provide capabilities when detected/configured.
- **Graceful fallback:** optional services are detected/configured rather than hardcoded; ARES must still boot with whichever framework/backend set is available.

## Features

- **Persistent Entity** — ARES is not a chatbot. It is a continuous intelligence with identity, memory, drives, and presence across sessions.
- **Web UI** — Self-contained Python server with streaming, session management, hot-reload, password auth, and mobile/browser access.
- **Backend Selector** — Switch between Hermes, JROS, ARES-native, or hybrid runtime modes per conversation. Framework choice is separate from real model/provider choice.
- **Character Avatar Browser** — Visual character personas with card art, traits, lore, and active identity selection.
- **Native macOS App** — SwiftUI app for native windowing, voice, dashboard, files, terminal, and embodied companion UI.
- **Hot Reload** — Edit Python files → server auto-restarts in ~2s. Edit static files → browser auto-reloads.
- **Framework Integrations** — Hermes and JROS adapters expose full-framework capabilities: tools, terminal/file/web/code paths, MCP/skills/memory/scheduling, voice, event bus, robotics, delegation, and verification depending on runtime health.
- **Multi-Model Routing** — Cloud/local model routing through configured providers with local fallback where available.
- **Mail Butler** — IMAP-based mail cleaner/classifier without requiring Mail.app.
- **Windows Wrapper** — Tauri/Electron wrapper surfaces for Windows packaging and install testing.
- **Built in Public** — The build is documented as part of the “Building Ares” series.

## Character Avatar Browser

ARES exposes the persona system as a real product surface instead of a hidden dropdown. The character tab loads JROS `character/v1` YAML data, displays avatar card art, shows role/voice/trait/lore detail, and lets the user set the active ARES identity from the browser.

- **Visual roster:** built-in character cards are checked into `webui/static/persona-cards/` and `webui/static/characters/`.
- **Schema-backed:** the browser reads JROS character data through `webui/api/characters.py` and `/api/ares/characters`.
- **Runtime control:** selecting a character writes the active persona through the existing ARES persona API.

<p align="center">
  <img src="docs/assets/character-tab-showcase.png" alt="ARES character tab with avatar cards and trait detail">
</p>

## Architecture

```text
┌──────────────────────────────────────────────────┐
│                    ARES                          │
│ Human UX/product layer: natural language, UI,     │
│ automation, continuity, owner-aware defaults      │
├──────────────────────────────────────────────────┤
│ Native app / WebUI / Windows wrapper             │
├──────────────────────────────────────────────────┤
│ Peer full frameworks: Hermes, JROS, ARES-native   │
│ services, local/cloud providers, hybrid routing   │
├──────────────────────────────────────────────────┤
│ Local/cloud model providers, user data, devices   │
└──────────────────────────────────────────────────┘
```

Key rules:

1. **ARES owns the human experience.** Hermes and JROS are peer full agentic frameworks; neither one is the ARES identity.
2. **Natural language is the front door.** Users speak/type normally; ARES maps intent to framework/tool/model calls and presents the result.
3. **Hybrid is first-class.** ARES can use Hermes, JROS, ARES-native services, local models, cloud providers, or combinations per request.
4. **Framework selection and model/provider selection are separate.** Do not fake JROS as a model/provider; route to JROS as a runtime while preserving real model/provider settings.
5. **Native and WebUI surfaces share the same product identity.** Users should experience one ARES, not separate Hermes/JROS apps taped together.
6. **Public repo stays portable.** No private paths, secrets, OAuth tokens, local runtime DBs, or personal profile state.

## Repository Structure

```text
ARES/
├── Package.swift                 # Swift Package manifest
├── Sources/                      # Legacy/lightweight Swift app + CLI
│   ├── ARES/                     # ARESLegacy target
│   └── AresTaskCLI/              # Task CLI
├── ARES-Modules/                 # Local Swift module package
├── ARES-Desktop/                 # Primary native macOS app
│   ├── Sources/ARESCore/         # contracts, models, utilities
│   ├── Sources/ARES/             # app, providers, services, views
│   └── Tests/ARESTests/          # native tests
├── webui/                        # ARES Web UI (Python server/frontend)
│   ├── api/                      # server, streaming, auth, integrations
│   ├── static/                   # frontend assets, icons, character art
│   ├── server.py                 # entry point
│   ├── requirements.txt          # Python dependencies
│   └── tests/                    # WebUI test suite
├── src-tauri/                    # Tauri wrapper
├── windows-app/                  # Windows wrapper/installer work
├── tools/                        # Standalone utilities
└── docs/                         # public documentation/assets
```

## Update Checking

The Web UI checks for updates across the configured stack:

- **ARES** — this repo (`shuwalker/ARES`)
- **Hermes** — peer full agentic framework (`NousResearch/hermes-agent`)
- **JROS** — peer full agentic framework with robotics/embodiment strengths (`JenkinsRobotics/JROS`)

## Credits

The ARES Web UI (`webui/`) is forked from [hermes-webui](https://github.com/nesquena/hermes-webui) by the Hermes Web UI contributors, originally licensed under MIT. See `LICENSE` for ARES, `COMMERCIAL-LICENSE.md` for commercial licensing, and `webui/LICENSE` for the preserved upstream MIT notice.

## Owner

Built by Jenkins Robotics.

## Star History

<a href="https://www.star-history.com/?repos=shuwalker/ARES&type=date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=shuwalker/ARES&type=date" />
 </picture>
</a>
