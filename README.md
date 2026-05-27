# ARES — Autonomous Reasoning & Execution System

ARES is a native macOS AI companion application that connects to a persistent local AI agent running on your network. It provides a unified interface for conversation, agent management, and system control — powered by your own hardware, with no cloud dependency.

## App Structure

| Tab | Description |
|---|---|
| **Companion** | AI chat interface with voice input, wired to your Hermes agent |
| **Hub** | Agent dashboard — Hermes web UI and native Dodo management views |
| **Office** | Autonomous task execution workspace *(Phase 4)* |
| **Settings** | Gateway configuration, model selection, integrations |

## Architecture

```
ARES (macOS app)
  └── Swift UI layer
  └── ARES Python daemon  ←→  ZeroMQ IPC
        └── Hermes Agent (Mac Studio, port 8642)
              └── Ollama local models (hermes-3, llama3.2:3b, llava:7b)
        └── OSC telemetry → Unity avatar renderer (port 9000)
```

## Requirements

- macOS 14+
- Python 3.11+
- [Ollama](https://ollama.ai) with models pulled: `hermes-3`, `llama3.2:3b`
- Hermes Agent running and accessible (default: `http://localhost:8642`)
- Xcode 15+ command-line tools (for SwiftPM)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/shuwalker/ARES.git
cd ARES

# 2. Install the Python daemon
pip install -e .

# 3. Start the daemon
ares start

# 4. Build the macOS app bundle
cd ARES-Desktop && ./build-app.sh
# Produces ARES-Desktop/ARES.app — open it or drag to /Applications.
# For Xcode iteration: open ARES-Desktop/Package.swift, select the ARES scheme, ⌘B.
```

## Configuration

ARES reads from `~/.ares/config/ares.toml` on first run. A complete annotated example lives at `ares.toml.example` in the repo root — copy it into place and edit. Key fields:

```toml
[agent]
backend = "hermes"          # "hermes" | "lilith" | "local" | "cloud"
fast_path_enabled = false

[agent.hermes]
api_url = "http://localhost:8321"
api_key = ""                # Prefer ARES_HERMES_API_KEY env var

[agent.local]
model = "gemma3:12b"
ollama_url = "http://localhost:11434"
num_ctx = 65536

[gateway]
host = "127.0.0.1"
port = 7860

[telemetry.osc]
enabled = false
host = "127.0.0.1"
port = 9000
```

Environment variable overrides (read by `ares/runtime/config.py`):
- `ARES_HOME` — Override `~/.ares` location
- `ARES_GATEWAY_HOST`, `ARES_GATEWAY_PORT` — Gateway bind address
- `ARES_AGENT_BACKEND` — Which brain (`hermes` / `lilith` / `local` / `cloud`)
- `ARES_HERMES_URL`, `ARES_HERMES_API_KEY` — Hermes gateway + key
- `ARES_LOCAL_MODEL`, `ARES_OLLAMA_URL` — Local backend settings
- `OLLAMA_NUM_CTX` — Override Ollama context window

## Diagnostics

```bash
ares doctor    # Check daemon health and service connectivity
ares status    # Show running services and memory state
```
