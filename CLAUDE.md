# CLAUDE.md — ARES Development Guide

For Claude Code contributors. This file tells you what's built, what's planned, and how to work on ARES without breaking things.

## What ARES Is

ARES = Autonomous Reasoning & Execution System. A persistent embodied AI companion that runs locally on a Mac Studio (primary) and syncs to a MacBook Pro (secondary) via iCloud Drive.

**ARES is not Hermes.** Hermes is one reasoning engine inside ARES. ARES is the product — avatar, sensors, memory, tools, approval layer, and workflows.

**Current phase:** Rebuild (ARES 2). See `docs/ARES_2_REBUILD.md` for the full thesis. The target is a Jarvis-like always-on entity with a Swift face, voice states, memory, and tool execution.

## Architecture (8 Layers)

Defined in `ares/runtime/agent_stack` and `docs/ARES_2_REBUILD.md`:

1. **Presence** — Avatar, voice, emotion, idle behavior, visible cognitive activity
2. **Runtime** — Always-on process, config, health, restart, service lifecycle (borrow Lilith's discipline)
3. **Memory** — Identity, preferences, episodic history, project memory, summaries
4. **Perception** — Permissioned sensors: mic, screen, camera, files, later robot inputs
5. **Reasoning** — Model routing, planning, reflection. Hermes is one adapter here.
6. **Tools** — MCP, filesystem, browser/computer control, code, n8n, creative tools
7. **Approval** — Policy layer for installs, deletion, publishing, spending, hardware control
8. **Workflows** — Content creation, research, coding, automation, robot tasks

## What's Built

| Component | Status | Location |
|---|---|---|
| Python package | ✅ Installed in venv | `ares/` package, `pyproject.toml` |
| CLI entrypoint | ✅ `ares --help` works | `ares/cli.py` |
| Config system | ✅ TOML-based | `ares/config/` |
| Core runtime | ✅ Basic | `ares/core/`, `ares/runtime/` |
| Memory module | ✅ Basic TOML/JSONL | `ares/memory.py` |
| LLM routing | ✅ Local/cloud switch | `ares/llm/` |
| Embodiment | 🟡 Swift face scaffolded | `ares/embodiment/` |
| ARES-Desktop app | ✅ SwiftUI app exists | `ARES-Desktop/` (forked from Hermes desktop) |
| MCP integration | 🟡 Skeleton | `ares/tools/`, depends on external MCP servers |
| Workflows | 🟡 Content pipeline defined | `ares/workflows/`, `docs/content_workflow.md` |
| Video production | 🟡 HyperFrames just integrated | `~/hyperframes/` (external, see below) |
| Tests | ✅ 30 passed, 12 skipped | `tests/unit/`, `tests/integration/` |

## What's NOT Built (Don't Assume It Exists)

- **Robot hardware MCP servers** — motion (:9520), vision (:9521), voice (:9522) are ports on a spec, not running services
- **Physical ARES build** — skeleton, eyes, hands are design-phase only
- **Avatar face** — SwiftUI scaffold exists but no active rendering pipeline
- **Voice synthesis** — No TTS engine wired in yet
- **n8n workflows** — localhost:5678 is the target, not implemented
- **Content publish pipeline** — No YouTube upload, no social auto-post

## External Integrations (Managed Outside ARES Repo)

These live outside the repo but are part of the operational stack:

| Tool | Location | Role |
|---|---|---|
| Hermes Agent | `~/.hermes/` | Primary reasoning engine, Discord gateway, cron, skills |
| Ollama | `http://localhost:11434` | Local LLM server (gemma4:31b, mistral-large-3, etc.) |
| HyperFrames | `~/hyperframes/` | HTML→MP4 renderer (HeyGen open-source) |
| HyperDirector | `~/.hermes/skills/hyperdirector` | Hermes skill for video production workflow |
| ARES Dashboard | `~/hyperframes/ares-dashboard/index.html` | Live status dashboard for the stack |
| Obsidian KB | `/Volumes/Jenkins_Robotics/03_Knowledge/YouTube/` | Pipeline output: video_index + 7-axis entries |
| NAS | `/Volumes/Jenkins_Robotics/` | Network storage for media, renders, backups |
| RackPC | `100.85.249.11` (Tailscale) | Homelab server for CI/batch compute |
| Hermes Self-Reflection | `~/.hermes/skills/hermes-self-reflection/` | Weekly cron skill — reads vault + sessions, writes evolving self-model |
| SearXNG | Docker `searxng:8080` | Self-hosted search — free, no API keys, no rate limits |

## Development Setup

```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System

# Python 3.11+ required (pyproject.toml: requires-python >=3.11)
# Use homebrew Python if system Python is <3.11
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e .

# Verify
ares --help
pytest tests/unit/ -x -q
```

**Claude Code workflow:**
- `claude` from the repo root opens Claude Code with full context
- Use worktrees for isolated features: `claude --worktree`
- Clean worktrees when done: `git worktree prune` + delete `.claude/worktrees/*`

## Git Rules

- **Main is protected.** Branch for all work. Feature branches only.
- **Never commit to main directly.**
- **Upstream:** `nousresearch/hermes-desktop` — this repo forked from there. Keep `upstream` remote current.
- **Origin:** `shuwalker/ARES-Autonomous-Reasoning-Execution-System` — personal fork.

## Testing

```bash
# Fast unit tests (no services needed)
pytest tests/unit/ -x -q

# Integration tests (skip if services not running)
pytest tests/integration/ -x -q

# With coverage
pytest tests/ --cov=ares --cov-report=term-missing
```

Current status: 30 passed, 12 skipped (integration tests auto-skip if ARES services unreachable).

## Code Standards

- **Python:** Black + ruff configured in `pyproject.toml` (line length 120)
- **Swift:** Standard Xcode formatting
- **No `any` or `as T` assertions** in TypeScript (HyperFrames rule, inherited)
- **Keep Hermes integration clean.** Hermes calls ARES via MCP or CLI. Don't embed Hermes internals into ARES.

## Current Priorities (In Order)

1. **ARES-Desktop Swift app** — Get the SwiftUI face rendering, even if static. This is the user-facing product.
2. **MCP server wiring** — Connect ARES to Hermes's MCP tool layer so ARES can call Hermes skills.
3. **Memory persistence** — Make `ares/memory.py` survive restarts with proper TOML/JSONL storage on iCloud.
4. **Voice states** — Idle, listening, thinking, speaking, sleeping. Even without TTS, the state machine matters.
5. **Content workflow** — Hook HyperDirector skill into ARES workflow system so ARES can request video production.
6. **Approval layer** — Policy engine for high-risk actions. Start with simple allowlist/blocklist.
7. **Robot hardware** — Only after above are solid. MCP servers for motion/vision/voice when JP01 is built.

## What Will Break Things

- Changing `ares/cli.py` entrypoint signature
- Moving `ares/` package without updating `pyproject.toml [tool.setuptools.packages.find]`
- Committing `.claude/worktrees/` (they're tracked, don't add new ones)
- Breaking Hermes MCP integration (ARES depends on Hermes for reasoning)
- Adding cloud-only dependencies without local fallback
- Anything that requires ARES to "phone home" or call external APIs without user approval

## Contact / Context

- **Owner:** Matthew Jenkins (shuwalker)
- **Primary machine:** Mac Studio (this machine)
- **Secondary:** MacBook Pro (sync via iCloud)
- **Hermes runs here:** Mac Studio, `~/.hermes/`
- **This repo:** Forked from `nousresearch/hermes-desktop`, diverged significantly for robotics/embodiment