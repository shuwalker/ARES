# ARES Web UI

Browser command center for ARES — Artificial Reasoning Entity System.

The WebUI is forked from [hermes-webui](https://github.com/nesquena/hermes-webui) and extended into an ARES surface: ARES branding, backend selection, character/persona browsing, model/provider management, and peer-framework routing for Hermes Agent and JROS.

## Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.sh | bash
```

### Windows PowerShell

```powershell
iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)
```

### Windows no-terminal path

Download `webui/start_ares.bat`, double-click it, and follow browser onboarding.

All install paths create or reuse an ARES WebUI checkout, set up Python dependencies, and start the server. Open:

```text
http://localhost:8787
```

## Manual Development Start

```bash
cd ARES/webui
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server.py
```

## Backend Modes

| Mode | Purpose |
| --- | --- |
| `hermes` | Hermes Agent runtime for tools, MCP, skills, cron, coding, provider routing, and operations. |
| `jros` | JROS runtime through an existing `jaeger bridge` install. Best for characters, personas, robotics, and embodied workflows. |
| `hybrid` | Hermes execution loop with JROS context/tool/persona integration where configured. |

Backend selection is independent from provider/model selection. Do not add fake `jros` model entries; JROS mode still uses real configured providers/models.

## JROS Integration

ARES does **not** install JROS into the WebUI venv and does **not** clone a second copy. Runtime chat uses the installed `jaeger bridge` process through `api/jros_client.py`.

Path resolution is centralized in `api/jros_paths.py`:

1. `ARES_JAEGER_HOME`
2. `JAEGER_HOME`
3. standard installer path (`~/jaeger`)
4. `ARES_JROS_DIR` for optional source-checkout features only
5. `ARES_JROS_CONFIG_PATH` / `JAEGER_INSTANCE_DIR` for explicit config overrides

See [`../docs/jros-integration.md`](../docs/jros-integration.md).

## What Changed from Hermes WebUI

- ARES title, favicon, manifest, skin, and server header.
- Backend selector for Hermes, JROS, and hybrid runtime modes.
- JROS bridge client (`api/jros_client.py`) and streaming integration (`api/jros_bridge.py`).
- Shared JROS path resolver (`api/jros_paths.py`) so Jaeger/JROS paths have one source of truth.
- Provider sync helpers for keeping Hermes/JROS model config aligned without copying secrets.
- Character/persona APIs for JROS `character/v1` and legacy `persona/v1` data.
- Characters panel, checked-in avatar art, and public showcase assets.

## Character Avatar Tab

The Characters panel is the visual front door for ARES identity selection.

Runtime paths:

- `GET /api/ares/characters` — list character summaries and detail data.
- `GET /api/ares/character?id=<id>` — load one character YAML.
- `GET /api/ares/persona/current` — read the active persona.
- `POST /api/ares/persona/set` — set active persona from the UI.

The public showcase image lives at `../docs/assets/character-tab-showcase.png`.

## Dependencies

- Python 3.11+
- Hermes Agent for Hermes runtime mode
- Optional JROS install for `jros` / `hybrid` runtime modes
- See `requirements.txt` for WebUI Python dependencies

## Compatibility Notes

- WebUI and Hermes Agent should be upgraded/pinned together where possible.
- Docker deployments should pin WebUI and agent images from the same release train/date.
- JROS is treated as an external peer runtime, not a vendored Python package.

## More Docs

- [Root README](../README.md)
- [ARES + JROS Integration](../docs/jros-integration.md)
- [Why Hermes?](../docs/why-hermes.md)
- [WSL Autostart](../docs/wsl-autostart.md)
- [Docker Guide](docs/docker.md)

## Common Local Host / Docker Failures

- Container `localhost` means the container itself, not the host machine. To connect to host-local providers such as Ollama or Jaeger from Docker, use `host.docker.internal`.
- `sudo docker compose up -d` can expand `${HOME}` to root's home. Set `HERMES_HOME` explicitly when bind-mounting an existing Hermes home.
