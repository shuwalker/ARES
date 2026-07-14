<p align="center">
  <strong style="font-size: 2em;">ARES</strong><br>
  <em>Artificial Reasoning & Execution System</em>
</p>

<p align="center">
  A Mac-first presentation and integration layer for a user-facing AI assistant.<br>
  Connect JROS, Hermes, OpenAI-compatible providers, tools, voice, avatars, and future robotic bodies through one client experience.
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
  <a href="https://github.com/JenkinsRobotics/JaegerAI"><img src="https://img.shields.io/badge/robotics-JaegerAI-cyan" alt="JaegerAI Robotics"></a>
</p>

---

## Quick Start

### Install

One command — works whether or not you have the repo yet:

```bash
curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/install.sh | bash
```

Or clone first if you prefer:

```bash
git clone https://github.com/shuwalker/ARES && cd ARES && bash install.sh
```

The installer handles everything:
- Detects your OS and checks prerequisites
- Prompts for machine role: **Primary** (always-on Mac) or **Client** (MacBook that falls back to local model when primary is unreachable)
- Detects or installs JaegerAI (required Companion runtime)
- Detects or installs Tailscale via Homebrew (macOS — for iPhone and cross-device access)
- Creates `~/Desktop/ARES/companion/` — your Companion profile, synced across Macs via iCloud Desktop
- Sets up the Python virtual environment and dependencies
- Registers a launchd service so the server starts at login (macOS)
- Launches the ARES menu bar app, which opens the onboarding wizard

**Options:**
- `--role primary|client` — set machine role without being prompted
- `--primary-url URL` — primary machine URL for client mode (e.g. `http://100.x.y.z:8787`)
- `--with-hermes` — also install Hermes Agent (optional coding/terminal addition)
- `--no-start` — skip launching after install
- `--backend jros|hermes|hybrid` — override default backend

### macOS: what you get

ARES lives in your **menu bar** (shield icon). Clicking it shows server status and controls. The main window has three tabs:

- **Companion** — embedded web UI: chat, onboarding wizard, settings, all your sessions
- **Terminal** — Hermes Agent TUI (if installed), falls back to a shell
- **JROS** — JaegerAI TUI, falls back to a shell

You can keep talking to your Companion in the Terminal tab even while the web UI is being modified or reloaded.

### Linux / Windows

```bash
# Linux
bash install.sh   # from clone, or pipe from curl above

# Windows (WSL recommended)
bash install.sh
# Then open: http://localhost:8787
```

Windows native app (Tauri wrapper):

```powershell
cd ARES-Windows && cargo tauri dev
```

## Features

- **Multi-Agent Orchestrator (The "CEO" Model)** — ARES is now a lightweight, independent orchestrator shell. It boots instantly and seamlessly connects to your choice of "synthetic minds" (Jaeger OS or Hermes).
- **Paperclip Multi-Agent Capabilities** — Give your primary agent (e.g. Jaeger OS) a massive goal, and it will automatically spin up Hermes or Cloud LLMs in the background to delegate coding and writing tasks via our **MCP Bridge**.
- **Infinite Compute (Reverse API)** — ARES includes scaffolding to safely proxy requests through your existing $20/mo consumer subscriptions (Claude Pro, ChatGPT Plus), bypassing expensive developer API fees for massive background goals.
- **Scientist-Grade Diagnostics** — Run `ares doctor` in your terminal anytime to get a beautifully formatted, color-coded health check of your network, Tailscale status, Python environment, and backend engine status.
- **Safe Updates** — Run `ares update` to safely stash local tweaks, pull the latest code, and restart your environment without breaking your configuration.
- **Interactive WebUI Onboarding** — No more editing config files in the terminal. The sleek, glassmorphic UI handles Framework Selection and onboarding directly from your browser.
- **Tailscale Remote Access** — Because ARES automatically detects Tailscale, you can pull out your iPhone, navigate to your Tailscale IP, and check on your CEO's progress from anywhere in the world.
- **Mac-First Native Home** — SwiftUI app launches the Web UI, wraps it in WKWebView, and acts as the native menu integration layer for local Mac automation.
- **Hot Reload** — Edit Python files → server auto-restarts in ~2s. Edit static files → browser auto-reloads. Zero downtime for static, ~2s blip for Python.
- **Local + Cloud Choice** — The active runtime can choose local or cloud models depending on the task, including OpenAI/ChatGPT-compatible providers where configured.
- **Mail Butler** — IMAP-based mail cleaner with 321 classification rules. Server-side, no Mail.app dependency.
- **Built in Public** — Every episode of the build is documented as part of the "Building Ares" YouTube series.

## Character Avatar Browser

ARES treats characters as presentation data for the assistant interface. The character tab loads JaegerAI `character/v1` YAML data, displays avatar card art, shows role/voice/trait/lore detail, and lets the user select the character projection ARES presents.

- **Visual roster:** 14 built-in character cards are checked into `webui/static/persona-cards/` and `webui/static/characters/`.
- **Schema-backed:** The browser reads JaegerAI character data through `webui/api/characters.py` and `/api/ares/characters`.
- **Runtime control:** Selecting a character updates the presentation/adapter surface; JaegerAI remains the canonical owner of character behavior in JaegerAI-backed mode.

<p align="center">
## Architecture

```
┌──────────────────────────────────────────────────┐
│                    ARES                          │
│ presentation layer + adapter host + client apps   │
│                                                  │
│  ┌───────────┐ ┌────────────┐ ┌──────────────┐ │
│  │ Mac App    │ │ Web UI     │ │ Presence     │ │
│  │ menus/sys  │ │ Tailscale  │ │ avatar/voice │ │
│  └─────┬─────┘ └─────┬──────┘ └──────┬───────┘ │
│        │             │               │         │
│        ▼             ▼               ▼         │
│  ┌──────────────────────────────────────────┐  │
│  │ Integration layer: identity projection,  │  │
│  │ permissions, sessions, events, adapters  │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
       │              │              │             │
       ▼              ▼              ▼             ▼
 ┌───────────┐  ┌──────────┐  ┌────────────┐  ┌────────┐
 │ JaegerAI  │  │ Hermes   │  │ OpenAI/    │  │ Tools  │
 │ runtime   │  │ runtime  │  │ providers  │  │ apps   │
 └───────────┘  └──────────┘  └────────────┘  └────────┘
```

ARES is intentionally not a second JROS, a second Hermes, or a multi-agent
company simulator. It is a client and integration layer over independent
runtimes and capability providers. A runtime owns a turn, a model/provider may
provide reasoning, an avatar renderer may provide presentation, and a tool may
provide external action; ARES coordinates those pieces into one assistant
interface.

## Repository Structure

```
ARES/
├── Package.swift          # Swift Package Manager manifest
├── ARES-Desktop/          # Native macOS app + ARESCore contracts
│   ├── Sources/ARES/      # SwiftUI/WKWebView shell and native app surface
│   ├── Sources/ARESCore/  # Shared models, contracts, discovery, utilities
│   └── Tests/             # Native app tests
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

1. **ARES composes an assistant interface.** The goal is one coherent user-facing AI experience assembled from runtimes, tools, models, memory providers, avatar renderers, and device integrations.
2. **Web UI lives in `webui/`** — self-contained: own venv, own auth, own deps. One repo with the Swift app.
3. **Mac app first, web access everywhere.** The SwiftUI app is the native Mac home with menus/system integration and launches the Web UI; the same Web UI remains reachable from other devices over Tailscale/LAN.
4. **JaegerAI is the primary embodied path.** ARES talks to JaegerAI through the bridge/client protocol and displays JaegerAI characters, voice, tools, and body capabilities without replacing JaegerAI's own UI or runtime.
5. **Hermes and OpenAI-compatible services stay capability providers.** They provide coding, automation, model access, cloud reasoning, tools, and Mac/system integrations where configured.
6. **Presence is modular.** Animated eyes, character cards, Live2D-style rigs, VR sprite rigs, Grok-like avatars, desktop modes, and future robotic bodies are renderer surfaces for the assistant.

## Update Checking

The Web UI checks for updates on three repos:
- **ARES** — this repo (`shuwalker/ARES`)
- **Hermes** — the agent engine (`NousResearch/hermes-agent`)
- **JaegerAI** — robotics/embodiment (`JenkinsRobotics/JaegerAI`)

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
