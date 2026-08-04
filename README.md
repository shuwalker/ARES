# ARES

**One AI assistant. Multiple agents underneath.**

You talk to one thing — one conversation, one memory, one place that knows you. Underneath, ARES uses multiple agents to get work done: Jaeger for local tasks, Hermes for general work, Claude Code for coding, Ollama for local inference. You never talk to those agents directly. You talk to ARES, and ARES picks the right tool for the job, runs several in parallel when needed, and comes back with one answer.

The agents are replaceable hands. Swap any model or runtime underneath and nothing is lost — ARES holds the memory, the plans, the history, and the verification.

## Quick Start

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES
bash install.sh
./start.sh
# → http://localhost:8788
```

Or run the native macOS app:
```bash
swift run ARES
```

## Documentation

- **[Vision](docs/vision.md)** — what ARES is, the problem it solves, and how it works
- **[Architecture](docs/architecture.md)** — dispatch, guard, memory, runtime, boundaries
- **[Development](docs/development.md)** — install, run, Docker, troubleshooting, contributing
- **[API Reference](docs/api.md)** — endpoints and contracts

## Repository

```
ARES/
├── apps/macos/            # Native macOS app (SwiftUI/WKWebView)
├── apps/web/              # React/TypeScript SPA
├── services/controller/   # FastAPI backend + API + tests
├── core/                  # SI core: planner, orchestrator, trust, verification
├── integrations/          # Worker adapters (Jaeger, Hermes, Claude, Codex, Ollama)
└── docs/                  # Documentation
```

## Owner

Matthew Jenkins (shuwalker) · Jenkins Robotics
