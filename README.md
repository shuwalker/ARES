# ARES

> **An open-source embodied AI operating system. Deploy a persistent intelligence to orchestrate your local stack, automate complex workflows, and interact through a native AI avatar.**

ARES is the OS for your local AI stack. It owns the user-facing layer
(identity, memory, intent routing, approval, the avatar shell) and orchestrates
the apps that do the actual work — Ollama for reasoning, Hermes Agent for
tools and skills, native Mac apps for capabilities, web UIs for visual
surfaces.

It is not a chatbot, not a Hermes Desktop fork, and not a wrapper around a
single model. Other apps are *guests* of ARES; ARES is the host.

> Status: **early.** The shell, bootstrap, and Hermes integration work. The
> avatar is scaffold. Voice isn't wired. See [What's Built](#whats-built).

## The Shell (ARES-Desktop)

Three tabs, modelled on a desktop OS:

| Tab | Role | macOS analog |
|---|---|---|
| **Companion** | The avatar. Voice states, greeting, self-model excerpt. How you talk to ARES. | Finder / Spotlight |
| **Office** | Live dashboard over the stack — what ARES is doing right now, across every app. | Mission Control |
| **Hub** | Launcher + coordinator for the apps running on ARES. Web UIs embed; native apps launch standalone. | Dock + Launchpad |

## The Stack (Apps ARES Hosts)

| Component | Role | Endpoint | How ARES talks to it |
|---|---|---|---|
| Ollama | Brain — LLM inference | `localhost:11434` | HTTP |
| Hermes Agent | Tools — skills, MCP, sessions, cron | `~/.hermes/` | HTTP + MCP |
| Hermes Desktop | Operator GUI for Hermes | `/Applications/Hermes Desktop.app` | Launch + coordinate |
| Hermes WebUI | Dashboard for Hermes | `localhost:9119` | `WKWebView` |
| Blender / DaVinci / Obsidian / VTuber apps | Capability apps | Standard Mac apps | `NSWorkspace`, URL schemes |
| n8n | Workflow execution | `localhost:5678` | HTTP (planned) |
| SearXNG | Web search | Docker `searxng:8080` | HTTP |

The contract for hosting these is being formalized in
[`docs/ARES_GUEST_FRAMEWORK.md`](docs/ARES_GUEST_FRAMEWORK.md).

## What's Built

- ✅ Three-tab desktop shell (Companion / Office / Hub)
- ✅ Bootstrap / dependency installer (first-run check for Hermes, Ollama, etc.)
- ✅ Hub: WebUI embed (Hermes WebUI), Settings, embedded Hermes Desktop (stopgap, see [PR #11](https://github.com/shuwalker/ARES/pull/11))
- ✅ Hermes Agent collaboration hub (v1 protocol) — `ares/runtime/collaboration.py`
- ✅ Python CLI + runtime (`ares` package): config, memory, basic LLM router
- 🟡 Companion tab — scaffold; avatar renderer is a placeholder
- 🟡 Office tab — scaffold; data sources not yet wired
- 🟡 Governance policies (`governance/*.yaml`) — defined, no runtime enforcement

## What's NOT Built (Yet)

- Voice (TTS / STT)
- Guest Framework (cross-app embedding contract — sketched only)
- Cross-app workflow engine
- Approval policy engine
- Anything robotics-related

## Install

**Requirements:** macOS 14+, Python 3.11+, Xcode 15+ (for the desktop app).

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES

# Python (CLI + runtime)
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e .
pytest tests/unit/ -x -q   # expect 30 passed / 12 skipped

# Desktop app — Mac only
cd ARES-Desktop
swift build
# Or open in Xcode:
open Package.swift
```

The desktop app's first-run BootstrapView will detect and offer to install
missing stack members (Hermes Agent, Ollama, SearXNG).

## Layout

```
ARES/
├── ARES-Desktop/        Swift app — the 3-tab shell (Companion/Office/Hub)
│   └── Sources/ARES/
│       ├── App/         ARESApp, ARESAppState, tab enum
│       ├── Views/       Companion, Office, Hub
│       ├── Bootstrap/   First-run dependency check
│       └── Dodo/        Legacy Hermes Desktop UI (stopgap, on deletion path)
├── ares/                Python package — runtime, CLI, integrations
│   ├── runtime/         Daemon, collaboration hub, service manager
│   ├── api.py           FastAPI endpoints (Hermes worker protocol)
│   ├── cli.py           `ares` command
│   ├── llm/             LLM routing
│   ├── memory.py        Persistent memory
│   ├── skills/          Skill registry
│   └── workflows/       YouTube research pipeline + workflow scaffolding
├── governance/          Approval policy specs (not yet enforced)
├── tools/               Collaboration test clients + TUI dashboard
├── docs/                Design docs, architecture, references
└── tests/               Pytest suite
```

## Contributing

See [`CLAUDE.md`](CLAUDE.md) for development guide, code standards, and current
priorities. The short version: **main is protected, feature branches only,
PRs open as draft, don't fork upstream apps into the repo.**

## License

(Add your license file when ready.)
