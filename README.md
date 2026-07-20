<p align="center">
  <strong style="font-size: 2em;">ARES</strong><br>
  <em>Artificial Reasoning & Execution System</em>
</p>

<p align="center">
  A Mac-first platform hosting a persistent Synthetic Intelligence (SI).<br>
  The SI knows the user, remembers history, protects data, plans work,<br>
  delegates to workers, verifies results, and remains consistent across providers.<br>
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
  <a href="https://github.com/NousResearch/ares-agent"><img src="https://img.shields.io/badge/powered%20by-Ares%20Agent-purple" alt="Powered by Ares Agent"></a>
  <a href="https://github.com/JenkinsRobotics/JaegerAI"><img src="https://img.shields.io/badge/robotics-JaegerAI-cyan" alt="JaegerAI Robotics"></a>
</p>

---

## Quick Start

### How To Run ARES Today

ARES currently has three supported local run paths and two planned packaging
paths:

- **Developer mode:** run `swift run ARES` from the repo root. This launches
  the native macOS shell, which wraps and controls the Web UI.
- **Web mode:** run `./start.sh` from the repo root, then open
  `http://localhost:8787` in a browser.
- **Windows companion app mode:** run the Web UI, then run the Tauri wrapper
  from `ARES-Windows/`. This is the Windows native shell path for wrapping the
  Web UI and adding Windows desktop integrations.
- **Future standalone modes:** package `ARES.app` on macOS and a Windows
  installer from `ARES-Windows/`, each with `webui/`, a Python
  runtime/environment, dependencies, and first-run setup. This is not complete
  yet, so current native builds are for local/developer use.

For a first local setup:

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES

# Run the installer
bash install.sh
```

The installer handles everything automatically:
- Detects or installs JaegerAI/JROS when available (optional for saving a Local Profile)
- Creates a Python virtual environment
- Installs Python dependencies
- Configures a live adapter when one is detected (defaults to `jros_local`)

**Options:**
- `--with-ares` — also install Ares Agent package (optional coding addition; not a backend mode)
- `--no-start` — skip auto-starting the server after install
- `--backend auto|jros_local|hermes_local|claude_local|...` — elect a live adapter ID (deleted modes `ares`/`hybrid` are rejected)

After install, run the Web UI:

```bash
./start.sh
# → http://localhost:8787
```

### Native macOS App

```bash
cd ARES
swift run ARES
```

### Windows Companion App

```powershell
cd ARES
cd webui
.\.venv\Scripts\python.exe server.py
```

In a second PowerShell window:

```powershell
cd ARES
cd ARES-Windows
cargo tauri dev
```

The Windows app currently loads the running Web UI from
`http://127.0.0.1:8787`. Its goal is to become the Windows version of the ARES
native shell, including native start/stop control for the Web UI and Windows
tray/menu integrations.

## Features

- **Single User-Facing Assistant Interface** — ARES composes runtimes, models, tools, voice, avatars, memory providers, and device integrations behind one consistent user experience.
- **Runtime-Compatible Adapter Layer** — JaegerAI, Ares, OpenAI/ChatGPT-compatible services, and future systems connect through adapters. ARES presents and coordinates them without copying their internals.
- **Mac-First Native Home** — SwiftUI app launches the Web UI, wraps it in WKWebView, and grows into the native menu/system integration layer for local Mac automation, status, notifications, and approvals.
- **Windows Companion Shell** — Tauri app in `ARES-Windows/` wraps the Web UI for Windows and is the home for Windows tray/menu/server-control integrations.
- **Web UI Everywhere** — Self-contained Python server with streaming, session management, hot-reload, and password auth. Works on other devices over Tailscale/LAN while native apps are still Mac-first.
- **JaegerAI Embodiment Path** — JaegerAI is the primary embodied runtime. Turns run through the local `jaeger bridge` over stdio (NDJSON) on the same machine.
- **Ares Capability Path** — Ares remains available as an independent runtime for coding, terminal work, skills, sessions, cron, memory-backed automation, provider routing, delegation, and operations.
- **Explicit Hybrid Composition** — Hybrid mode composes capabilities deliberately. Prefer one turn owner and call additional runtimes/providers only when needed.
- **Character Avatar Browser** — 14 visual character personas (HAL 9000, GLaDOS, Jarvis, TARS, Bender, Helldiver, and more) with card art, traits, lore, and active character selection from JaegerAI data.
- **Presence Renderers** — Avatar/voice/body surfaces can evolve from animated eyes to Live2D-style, VR sprite rigs, Grok-like avatars, desktop modes, and future robotic bodies.
- **Development Reload** — Vite provides frontend hot-module replacement; `ARES_WEBUI_RELOAD=1` restarts the Python controller after backend edits.
- **Local + Cloud Choice** — The active runtime can choose local or cloud models depending on the task, including OpenAI/ChatGPT-compatible providers where configured.
- **Mail Butler** — IMAP-based mail cleaner with 321 classification rules. Server-side, no Mail.app dependency.
- **Built in Public** — Every episode of the build is documented as part of the "Building Ares" YouTube series.

## Character Avatar Browser

ARES treats characters as presentation data for the assistant interface. The character tab loads JaegerAI `character/v1` YAML data, displays avatar card art, shows role/voice/trait/lore detail, and lets the user select the character projection ARES presents.

- **Visual roster:** Character metadata comes from connected JaegerAI data; the current React interface uses the ARES app icon until a normalized avatar renderer is connected.
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
 │ JaegerAI  │  │ Ares   │  │ OpenAI/    │  │ Tools  │
 │ runtime   │  │ runtime  │  │ providers  │  │ apps   │
 └───────────┘  └──────────┘  └────────────┘  └────────┘
```

ARES is intentionally not a second JROS, a second Ares, or a multi-agent
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
│   ├── frontend/          # React/Vite frontend, public assets, and API adapters
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
5. **Ares and OpenAI-compatible services stay capability providers.** They provide coding, automation, model access, cloud reasoning, tools, and Mac/system integrations where configured.
6. **Presence is modular.** Animated eyes, character cards, Live2D-style rigs, VR sprite rigs, Grok-like avatars, desktop modes, and future robotic bodies are renderer surfaces for the assistant.

## Update Checking

The Web UI checks for updates on three repos:
- **ARES** — this repo (`shuwalker/ARES`)
- **Ares** — the agent engine (`NousResearch/ares-agent`)
- **JaegerAI** — robotics/embodiment (`JenkinsRobotics/JaegerAI`)

## Credits

The ARES Web UI (`webui/`) is forked from [ares-webui](https://github.com/nesquena/ares-webui) by the Ares Web UI Contributors, originally licensed under MIT. See `LICENSE` for ARES, `COMMERCIAL-LICENSE.md` for commercial licensing, and `webui/LICENSE` for the preserved upstream MIT notice.

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
