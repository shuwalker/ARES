# ARES Web UI

Browser surface for ARES — Artificial Reasoning Entity System.

The WebUI is forked from [ares-webui](https://github.com/nesquena/ares-webui)
and extended into the remote-access face of ARES: chat, sessions, backend
adapters, character projection, model/provider management, and presence controls
for one assistant interface assembled from JROS, Ares, OpenAI-compatible
providers, local tools, and future body/avatar renderers.

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
.venv/bin/python bootstrap.py --foreground
```

## Backend Modes

| Mode | Purpose |
| --- | --- |
| `jros` | Embodied JROS/Jaeger runtime through an existing gateway/bridge. Best for character, voice, robotics, and body-aware workflows. |
| `ares` | Ares Agent runtime for coding, terminal work, MCP, skills, cron, provider routing, and operations. |
| `hybrid` | Explicit composition: one clear turn owner with extra capabilities borrowed from another runtime only when configured. |

Backend selection is independent from provider/model selection. Do not add fake `jros` model entries; JROS mode still uses real configured providers/models.

## JROS Integration

ARES does **not** install JROS into the WebUI venv and does **not** clone a
second copy. Runtime chat uses the installed JROS/Jaeger process through the
gateway/bridge adapter. JROS keeps its own runtime and UI; ARES provides an
additional Mac and web client surface.

Path resolution is centralized in `api/jros_paths.py`:

1. `ARES_JAEGER_HOME`
2. `JAEGER_HOME`
3. standard installer path (`~/jaeger`)
4. `ARES_JROS_DIR` for optional source-checkout features only
5. `ARES_JROS_CONFIG_PATH` / `JAEGER_INSTANCE_DIR` for explicit config overrides

See [`../docs/jros-integration.md`](../docs/jros-integration.md).

## What Changed from Ares WebUI

- ARES title, favicon, manifest, skin, and server header.
- Backend selector for Ares, JROS, and hybrid runtime modes.
- JROS bridge client (`api/jros_client.py`) and streaming integration (`api/jros_bridge.py`).
- Shared JROS path resolver (`api/jros_paths.py`) so Jaeger/JROS paths have one source of truth.
- Provider sync helpers for keeping Ares/JROS model config aligned without copying secrets.
- Character/persona APIs for JROS `character/v1` and legacy `persona/v1` data.
- Characters panel, checked-in avatar art, and public showcase assets.

## Character Avatar Tab

The Characters panel is the visual entry point for assistant presentation. It
shows the character/avatar projection ARES should present while leaving
canonical behavior with the active runtime.

Runtime paths:

- `GET /api/ares/characters` — list character summaries and detail data.
- `GET /api/ares/character?id=<id>` — load one character YAML.
- `GET /api/ares/persona/current` — read the active persona.
- `POST /api/ares/persona/set` — set active persona from the UI.

The public showcase image lives at `../docs/assets/character-tab-showcase.png`.

## JROS Backend (gateway)

The backend selector's JROS mode runs each chat turn on a **JROS gateway
server** over HTTP — the same integration shape as the Ares Gateway bridge.
JROS runs as its own process (so it never fights a running JROS TUI/app for
the instance lock), and it can live on a different machine:

```bash
# on the machine where JROS is installed (same box, or a PC on your network)
jaeger gateway                          # localhost only, port 8643
jaeger gateway --host 0.0.0.0 --port 8643   # reachable from other machines

# on the machine running ARES (skip if JROS is on the same box)
export ARES_JROS_GATEWAY_URL=http://<jros-host>:8643
```

If your JROS checkout doesn't have the `jaeger gateway` command yet (it's
pending upstream), use the standalone twin shipped here — copy this ONE file
to the machine where JROS lives and run it there:

```bash
python3 webui/scripts/jros_gateway.py --jros-dir /path/to/JROS --host 0.0.0.0
```

It auto-delegates to the native `jaeger gateway` once the checkout ships it.

**No gateway? It still works locally.** When no gateway answers and
`ARES_JROS_DIR` points at a JROS checkout on the same machine, ARES spawns
`jaeger bridge` and speaks JROS's stdio protocol — flip the toggle and go,
while JROS stays inside its own virtualenv. Two caveats, reported as plain messages instead of
failures: JROS allows only one running copy per instance, so if the JROS
app/TUI is already open you'll be asked to close it (or run `jaeger
gateway` in its place); and a machine with no JROS instance yet is told to
run `jaeger setup` first.

Order of preference: gateway first (works for remote machines and alongside
a running gateway), local bridge fallback second (local convenience).

Optional auth: set `JAEGER_GATEWAY_KEY` on the gateway and the same value in
`ARES_JROS_GATEWAY_KEY` for ARES. The UI's JROS option lights up when the
gateway answers `GET /v1/health` — or, with no gateway, when a local
checkout is available for the fallback (the dropdown shows which mode
you're in). `ARES_JROS_DIR` also still feeds the character browser and
update checker.

## Dependencies

- Python 3.11+
- Ares Agent for Ares runtime mode
- Optional JROS install for `jros` / `hybrid` runtime modes
- See `requirements.txt` for WebUI Python dependencies

## Compatibility

- Upgrade both together: WebUI and ares-agent must match.
- Always pin both image tags in Docker configurations to avoid interface mismatches.
- See [docs/docker.md](docs/docker.md) and [docs/rfcs/agent-source-boundary.md](docs/rfcs/agent-source-boundary.md).
- Policy defined in context of issue #2491.

## More Docs

- [Root README](../README.md)
- [ARES + JROS Integration](../docs/jros-integration.md)
- [Why Ares?](../docs/why-ares.md)
- [WSL Autostart](../docs/wsl-autostart.md)
- [Docker Guide](docs/docker.md)

## Common Local Host / Docker Failures

- Host API at `localhost` fails from WebUI. Container `localhost` means the container itself, not the host. Use `host.docker.internal` to reach host-local services.
- `sudo docker compose up -d` can make `${HOME}` expand to the root user's home, so Docker mounts the wrong `.ares` directory instead of your real `~/.ares`. Set `ARES_HOME=/home/you/.ares` explicitly.
