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
- Xcode 15+ (to build the Swift app)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/shuwalker/ARES.git
cd ARES

# 2. Install the Python daemon
pip install -e .

# 3. Start the daemon
ares start

# 4. Build the macOS app
open ARES-Desktop/Package.swift   # Opens in Xcode
# Press ⌘B to build, then ⌘R to run
```

## Configuration

ARES reads from `~/.ares/ares.toml` on first run. Key fields:

```toml
[agent]
hermes_url = "http://localhost:8642"   # Your Hermes gateway URL
model = "hermes-agent"                  # Default model
api_key = ""                            # Set via env var instead

[ollama]
base_url = "http://localhost:11434"
num_ctx = 65536                         # Context window for reasoning model
keep_alive = "5m"

[telemetry]
osc_enabled = false                     # Enable OSC avatar control
osc_host = "127.0.0.1"
osc_port = 9000
```

Environment variable overrides:
- `ARES_HERMES_URL` — Hermes gateway URL
- `ARES_HERMES_MODEL` — Model identifier
- `ARES_HERMES_API_KEY` — API key (preferred over config file)

## Diagnostics

```bash
ares doctor    # Check daemon health and service connectivity
ares status    # Show running services and memory state
```
