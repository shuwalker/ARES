<p align="center">
  <img src="docs/assets/ares-wordmark.png" alt="ARES" width="180">
</p>

<p align="center">
  <strong>Artificial Reasoning Entity System</strong><br>
  The UI and control layer for Hermes Agent and JROS today — building toward a persistent AI companion and droid system.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#what-ares-is">What ARES Is</a> ·
  <a href="#backends">Backends</a> ·
  <a href="#native-app">Native App</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#license-and-attribution">License</a>
</p>

<p align="center">
  <a href="https://github.com/shuwalker/ARES/releases"><img src="https://img.shields.io/badge/status-beta-orange" alt="Status: Beta"></a>
  <a href="https://github.com/shuwalker/ARES/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License: AGPL-3.0"></a>
  <a href="https://github.com/NousResearch/hermes-agent"><img src="https://img.shields.io/badge/backend-Hermes%20Agent-purple" alt="Hermes Agent"></a>
  <a href="https://github.com/JenkinsRobotics/JROS"><img src="https://img.shields.io/badge/backend-JROS-cyan" alt="JROS"></a>
</p>

<p align="center">
  <img src="docs/assets/webui-screenshot.png" alt="ARES Web UI">
</p>

<p align="center">
  <img src="docs/assets/character-tab-showcase.png" alt="ARES character avatar browser">
</p>

---

## Quick Start

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.sh | bash
```

Then open:

```text
http://localhost:8787
```

### Windows

PowerShell:

```powershell
iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)
```

No-terminal path: download `webui/start_ares.bat`, double-click it, and follow the browser onboarding flow.

### Manual development install

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES/webui
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server.py
```

The browser onboarding wizard handles model/provider setup. If you want a specific backend at install time:

```bash
bash webui/scripts/install.sh --backend hermes
bash webui/scripts/install.sh --backend jros
bash webui/scripts/install.sh --backend hybrid
```

## What ARES Is

ARES today is the public UI/control layer around Hermes Agent and JROS. It gives the user one place to install, configure, switch, and use those frameworks while the larger ARES companion/droid system is built up in public.

- **Web UI:** browser-based command center with streaming chat, settings, providers, tools, personas, and backend selection.
- **Backend selector:** Hermes, JROS, or hybrid mode without pretending JROS is a fake model/provider.
- **Native macOS work:** SwiftUI Mission Control surface under `ARES-Desktop/`.
- **Model/provider settings:** cloud/local provider selection stays separate from framework/runtime selection.
- **Roadmap:** persistent identity, task continuity, embodied presence, robot/droid workflows, and ARES-native services.

ARES is not finished AI personhood yet. The repo is the path toward that: a working UI first, then deeper ARES-owned persistence and embodiment over time.

## Backends

ARES supports three runtime modes:

| Mode | Purpose | Notes |
| --- | --- | --- |
| `hermes` | General agent orchestration | Best for tools, MCP, skills, cron, coding, file ops, provider routing, and operational workflows. |
| `jros` | Embodied/persona/robotics runtime | Uses an existing JROS install through the supported `jaeger bridge` NDJSON protocol. JROS is not vendored into the ARES venv. |
| `hybrid` | Hermes loop plus JROS context | Keeps Hermes as the execution loop while adding JROS persona/tool context where configured. |

Backend selection is **not** model selection. ARES can run JROS while still using a real configured provider/model; it does not fake JROS as a model provider.

### JROS path configuration

ARES resolves JROS paths in one shared place: `webui/api/jros_paths.py`.

Resolution order:

1. `ARES_JAEGER_HOME` — ARES-specific installed Jaeger/JROS home override.
2. `JAEGER_HOME` — JROS-wide installed Jaeger/JROS home override.
3. standard installer path, normally `~/jaeger`.
4. `ARES_JROS_DIR` — optional source checkout only for source-tree features such as character/schema browsing.
5. `ARES_JROS_CONFIG_PATH` / `JAEGER_INSTANCE_DIR` — explicit instance config overrides.

See [docs/jros-integration.md](docs/jros-integration.md) for setup, environment variables, and troubleshooting.

## Native App

The repo includes Swift surfaces for native macOS work:

- `ARES-Desktop/` — primary SwiftUI Mission Control app.
- `Sources/ARES/` — earlier lightweight Swift app target kept for migration/reference.
- `ARES-Modules/` — local Swift module package.

Build from the repo root:

```bash
swift build
swift test
swift run ARES
```

## Character Avatar Browser

The Characters panel turns persona selection into a first-class product surface:

- checked-in card art in `webui/static/persona-cards/` and `webui/static/characters/`
- character/persona data loaded through `/api/ares/characters` and `/api/ares/persona/*`
- active identity selection from the browser UI

## Repository Layout

```text
ARES/
├── ARES-Desktop/          # Primary native macOS app
├── ARES-Modules/          # Local Swift package modules
├── Sources/               # Legacy Swift app + CLI targets
├── webui/                 # Browser UI, Python server, frontend assets, tests
├── docs/                  # Public website, docs, assets, RFCs
├── tools/                 # Standalone utilities
├── windows-app/           # Windows wrapper/installer work
├── src-tauri/             # Tauri wrapper work
├── Package.swift          # Swift package manifest
└── LICENSE                # ARES AGPL-3.0 license
```

## Documentation

- [ARES + JROS Integration](docs/jros-integration.md)
- [Why Hermes?](docs/why-hermes.md)
- [Remote Access](docs/remote-access.md)
- [WSL Autostart](docs/wsl-autostart.md)
- [Workspace + Git Notes](docs/workspace-git.md)
- [Architecture](ARCHITECTURE.md)
- [Fork Changes](webui/FORK_CHANGES.md)

Public landing page: <https://shuwalker.github.io/ARES/>

## Development Checks

Useful local checks before publishing changes:

```bash
# WebUI focused tests
cd webui
./scripts/test.sh tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py tests/test_characters_api.py

# Python syntax for backend modules
python3 -m py_compile api/jros_paths.py api/jros_client.py api/jros_bridge.py

# Native app
cd ..
swift build

# Git whitespace/conflict guard
git diff --check
```

## Public Repo Safety

ARES is a public repo. Do not commit:

- private paths, hostnames, Tailscale IPs, or local machine assumptions
- API keys, OAuth tokens, cookies, auth files, or runtime databases
- user-specific `.hermes`, `.ares/config`, SOUL, profile, or workspace state
- generated build outputs, caches, or local session state

Use environment variables, config files, detected paths, or user-selected paths instead.

## License and Attribution

ARES is licensed under AGPL-3.0. See [LICENSE](LICENSE).

The `webui/` surface is forked from [hermes-webui](https://github.com/nesquena/hermes-webui) by the Hermes Web UI contributors. Its upstream MIT notice is preserved at [webui/LICENSE](webui/LICENSE). ARES integrates with [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [JROS](https://github.com/JenkinsRobotics/JROS) as peer agentic frameworks.

## Owner

Built by Jenkins Robotics.
