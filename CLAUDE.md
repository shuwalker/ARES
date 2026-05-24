# CLAUDE.md — ARES Development Guide

For Claude Code contributors. This file tells you what ARES is, what's built,
and how to work on it without breaking things.

> **The single source of truth for what ARES is:** the GitHub repo description.
> If this file ever contradicts the GitHub description, the GitHub description
> wins and this file is stale.

## What ARES Is

> *"An open-source embodied AI operating system. Deploy a persistent
> intelligence to orchestrate your local stack, automate complex workflows,
> and interact through a native AI avatar."*

ARES is an **operating system for your local AI stack**, not a chatbot or a
companion app. The mental model:

- **ARES is the OS.** It owns the user's relationship with their AI stack —
  identity, memory, intent routing, approval, and the user-facing UI.
- **The avatar is the shell.** Like Finder is the shell for macOS, the
  Companion is how you interact with ARES. It is not the product.
- **Other AI components are apps.** Ollama (brain / LLM inference), Hermes
  Agent (tools / skills / MCP), Blender / DaVinci / VTuber apps (capabilities),
  WebUIs (visual surfaces) — all *apps* that ARES hosts and orchestrates.
- **Workflows are first-class.** Cross-app automation is a primary product,
  not an add-on.

### What ARES is NOT

- Not a fork of Hermes Desktop. (`ARES-Desktop/Sources/ARES/Dodo/` exists as a
  stopgap embed and is on the deletion path. See `docs/ARES_GUEST_FRAMEWORK.md`.)
- Not a chatbot. Chat is one surface, not the product.
- Not a wrapper around a single model. ARES is model/tool-agnostic; it
  orchestrates whatever is in your stack.
- Not a robot framework. Hardware extensibility is on the long-term roadmap
  but is not the current product.

## The 3-Tab Shell (ARES-Desktop)

| Tab | Role | macOS analog |
|---|---|---|
| **Companion** | The avatar / face. Voice states, greeting, self-model excerpt, primary user interaction surface. | Finder / Spotlight |
| **Office** | The workspace dashboard over the stack. What's ARES doing right now — active sessions, running workflows, app status. | Mission Control |
| **Hub** | App launcher + coordinator. Lists every "app" running on ARES (WebUIs, native Mac apps, in-process Swift views) with status + actions. | Dock + Launchpad |

These are defined in `ARES-Desktop/Sources/ARES/App/ARESAppState.swift`
(`ARESTab` enum). The shell is `ARES-Desktop/Sources/ARES/Views/ARESRootView.swift`.

## The Stack (Apps That Run on ARES)

| Component | Role | Where it lives | How ARES talks to it |
|---|---|---|---|
| **Ollama** | Brain — LLM inference | `localhost:11434` | HTTP |
| **Hermes Agent** | Tools — skills, MCP, sessions, cron | `~/.hermes/` | HTTP + MCP |
| **Hermes Desktop** | Operator UI for Hermes (third-party app) | `/Applications/Hermes Desktop.app` | Launch / coordinate; today embedded via `Dodo/` |
| **Hermes WebUI** | Web dashboard for Hermes | `localhost:9119` | `WKWebView` in Hub |
| **Blender / DaVinci / VTuber / Obsidian** | Capability apps | Standard Mac apps | `NSWorkspace` launch, URL schemes, Accessibility |
| **n8n** | Workflow execution | `localhost:5678` | HTTP (planned) |
| **SearXNG** | Web search | Docker `searxng:8080` | HTTP |

The contract for hosting these inside ARES is being formalized — see
`docs/ARES_GUEST_FRAMEWORK.md` for the Guest protocol sketch.

## What's Built

| Component | Status | Location |
|---|---|---|
| ARES-Desktop shell (3 tabs) | ✅ | `ARES-Desktop/Sources/ARES/` |
| Companion tab (avatar, self-model load, voice state enum) | 🟡 Scaffold | `ARES-Desktop/Sources/ARES/Views/Companion/` |
| Office tab | 🟡 Scaffold | `ARES-Desktop/Sources/ARES/Views/Office/` |
| Hub tab (WebUI + Settings + embedded Hermes Desktop) | ✅ Working; embed is leaky (PR #11) | `ARES-Desktop/Sources/ARES/Views/Hub/` |
| Bootstrap / dependency installer | ✅ | `ARES-Desktop/Sources/ARES/Bootstrap/` |
| Legacy Hermes Desktop UI (Dodo) | ✅ Embedded as stopgap | `ARES-Desktop/Sources/ARES/Dodo/` |
| Python package (CLI, config, memory, LLM router) | ✅ Basic | `ares/` |
| Hermes integration (collaboration hub) | ✅ v1 protocol | `ares/runtime/collaboration.py` |
| Governance policies (YAML specs) | 🟡 Defined; no runtime enforcement | `governance/` |
| Tests | ✅ Python: 30 passed / 12 skipped (when venv is set up) | `tests/` |

## What's NOT Built (Don't Assume)

- Voice (TTS/STT) — not wired
- Working avatar renderer (pixel office is scaffold)
- Cross-app workflow engine — `ares/workflows/` is sketch
- Approval/policy enforcement — YAML rules exist, no engine
- Guest Framework — sketched in `docs/ARES_GUEST_FRAMEWORK.md`, not implemented
- Robot hardware — design phase only

## Development Setup

```bash
cd /path/to/ARES

# Python (CLI + runtime)
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e .
pytest tests/unit/ -x -q   # expect 30 passed / 12 skipped

# Swift (desktop app) — Mac only
cd ARES-Desktop
swift build
# Or open in Xcode: ARES-Desktop/Package.swift
```

## Git Rules

- **Main is protected.** Feature branches only.
- Origin: `shuwalker/ARES`.
- Push only to the branch the current session was assigned. Open PRs as **draft**.

## Code Standards

- **Python:** Black + ruff, line length 120 (configured in `pyproject.toml`).
- **Swift:** Standard Xcode formatting.
- **No new "Coming Soon" features.** If it doesn't ship, don't add a tab for it.
- **Don't fork upstream apps.** Host them via the Guest pattern (or coordinate
  them as standalone Mac apps). The `Dodo/` fork is the *only* exception and
  is on the deletion path.

## Current Priorities (In Order)

1. **Make the shell feel like an OS.** Companion polish + Office becoming a
   real dashboard over the stack.
2. **Guest Framework.** Replace the `NativeGuestHost` hack in
   `ARES-Desktop/Sources/ARES/Views/Hub/HubView.swift` with a proper protocol
   so any app can be registered. Start with `WebGuest` and `NativeSwiftUIGuest`.
3. **Voice loop.** ARES talking back in < 500 ms with its own personality.
4. **Office data sources.** Wire status tiles to Ollama / Hermes / app state.
5. **Retire `Dodo/`.** As Office grows native views for sessions/files/etc.,
   delete the corresponding chunk of the fork.
6. **Approval policy engine.** Make the `governance/*.yaml` rules actually
   enforce something.
7. **Robot hardware.** Long-term; only after the OS layer is solid.

## What Will Break Things

- Changing `ARESApp.swift` or `ARESRootView.swift` structure without preserving
  the 3-tab shell.
- Adding more sections to the legacy `Dodo/AppSection.swift` (it's already
  trimmed; reverse the trend, don't add to it).
- Re-introducing a "Coming Soon" group anywhere.
- Forking another upstream app into the repo. Host via Guest, or launch as a
  separate Mac app.
- Anything that requires ARES to call external paid APIs without an explicit
  user-approved code path.

## Operator Context

- **Owner:** Matthew Jenkins (shuwalker)
- **Primary machine:** Mac Studio
- **Secondary:** MacBook Pro (state via iCloud)
- **External services that ARES orchestrates:** Hermes Agent (`~/.hermes/`),
  Ollama (`localhost:11434`), HyperFrames (`~/hyperframes/`), Obsidian vault
  (`/Volumes/Jenkins_Robotics/03_Knowledge/`), RackPC (`100.85.249.11`).
