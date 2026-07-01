# AGENTS.md — ARES Repository Guide

For AI contributors. This describes what actually exists in this repo.

## What ARES Is

ARES = Artificial Reasoning Entity System. A persistent AI entity with its own identity, voice, and presence. This repo contains both the native macOS app (Swift) and the web UI (Python, forked from hermes-webui).

## Repository Layout

```
ARES/
├── Sources/ARES/          # SwiftUI app — Companion chat, Hub, voice, avatar
├── Sources/AresTaskCLI/   # CLI tool for task management
├── webui/                 # ARES Web UI — Python web server (forked from hermes-webui, rebranded)
├── tools/                 # Standalone tools (mail-butler, etc.)
├── Package.swift          # Swift Package Manager manifest
└── .gitignore
```

## Web UI (webui/)

- Self-contained: own `.venv/`, own auth files (`.env`, `.pbkdf2_key`, `.signing_key`)
- Server entry: `webui/server.py`
- Runs on port 8787
- Hermes Agent installed in editable mode from `~/.hermes/hermes-agent`
- Update checker tracks: ARES (this repo), Hermes (agent), JROS (robotics)
- All Hermes branding replaced with ARES (title, favicon, skin, manifest, server header)
- `api/persona.py` — JROS persona injection module (built, not yet wired to streaming.py)

## Native App (Sources/ARES/)

- SwiftUI app targeting macOS 14+
- Wraps the Web UI in WKWebView
- Native voice (SpeechService) as fallback
- AppIcon.icns in Resources/

## Do Not

1. Don't modify Hermes Agent source code (`~/.hermes/hermes-agent/`)
2. Don't create a separate repo for the Web UI — it lives in `webui/`
3. Don't run two agent loops — one loop (Hermes), inject JROS pieces into it
4. Don't commit `.venv/`, `.env`, `.pbkdf2_key`, `.signing_key`, `.ares_state/`
5. Don't push without explicit permission from Matthew