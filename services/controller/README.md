# ARES Web UI

Browser surface for ARES — Artificial Reasoning Entity System.

The WebUI is forked from [ares-webui](https://github.com/nesquena/ares-webui)
and extended into the remote-access face of ARES: chat, sessions, backend
adapters, character projection, model/provider management, and presence controls
for one assistant interface assembled from Jaeger AI, Ares, OpenAI-compatible
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

ARES elects **one external live adapter** at a time. IDs match
`api.backend_selector.VALID_BACKENDS` (for example `jaeger_local`,
`hermes_local`, `claude_local`, `openai_cloud`, `ollama_local`). Short
aliases such as `jros` and `hermes` normalize to canonical connection IDs.
Deleted product modes `ares` and `hybrid` are rejected and must not be
written to config.

| Mode | Purpose |
| --- | --- |
| `jaeger_local` | Jaeger AI runtime through its live gateway or local bridge. Best for character, voice, robotics, and body-aware workflows. A checkout alone is not "available". |
| `hermes_local` | Hermes Agent runtime for coding, terminal work, MCP, skills, cron, provider routing, and operations (optional install). |
| CLI / cloud adapters | Other registered adapters (`claude_local`, `openai_cloud`, `ollama_local`, …) when their tools or APIs are present. |

Backend selection is independent from provider/model selection. Do not add fake framework-named model entries; Jaeger AI uses real configured providers and models.

## Jaeger AI Integration

ARES does **not** install Jaeger AI into the controller venv and does **not** clone a
second copy. Runtime chat uses the installed Jaeger AI process through the
gateway/bridge adapter. Jaeger AI keeps its own runtime and UI; ARES provides an
additional Mac and web client surface.

Path resolution is centralized in `integrations/providers/jaeger/paths.py`:

1. `ARES_JAEGER_HOME`
2. `JAEGER_HOME`
3. standard installer path (`~/jaeger`)
4. `ARES_JAEGER_SOURCE_DIR` for optional source-checkout features only
5. `ARES_JAEGER_CONFIG_PATH` / `JAEGER_INSTANCE_DIR` for explicit config overrides

See [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).

## What Changed from Ares WebUI

- ARES title, favicon, manifest, skin, and server header.
- Backend selector for external live adapters (Jaeger AI, Hermes, CLI/cloud tools).
- Jaeger AI bridge client and streaming integration under `integrations/providers/jaeger/`.
- Shared Jaeger path resolver so runtime paths have one source of truth.
- Provider sync helpers for keeping Ares and Jaeger AI model configuration aligned without copying secrets.
- Character/persona APIs for Jaeger AI character and legacy persona data.
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

## Jaeger AI Backend (gateway)

The backend selector's Jaeger AI mode runs each chat turn on a **Jaeger AI gateway
server** over HTTP — the same integration shape as the Ares Gateway bridge.
Jaeger AI runs as its own process (so it never fights a running Jaeger AI TUI/app for
the instance lock), and it can live on a different machine:

```bash
# on the machine where Jaeger AI is installed (same box, or a PC on your network)
jaeger gateway                          # localhost only, port 8643
jaeger gateway --host 0.0.0.0 --port 8643   # reachable from other machines

# on the machine running ARES (skip if Jaeger AI is on the same box)
export ARES_JAEGER_GATEWAY_URL=http://<jaeger-host>:8643
```

If an older Jaeger AI checkout does not have the `jaeger gateway` command, use
the compatibility gateway shipped here and run it on the Jaeger AI machine:

```bash
python3 scripts/jros_gateway.py --jros-dir /path/to/JaegerAI --host 0.0.0.0
```

It auto-delegates to the native `jaeger gateway` once the checkout ships it.

**No gateway? It still works locally.** When no gateway answers and
`ARES_JAEGER_SOURCE_DIR` points at a Jaeger AI checkout on the same machine,
ARES spawns `jaeger bridge` and speaks its stdio protocol while Jaeger AI stays
inside its own virtualenv. Two caveats are reported as actionable messages:
Jaeger AI allows only one running copy per instance, so if the Jaeger AI
app/TUI is already open you'll be asked to close it (or run `jaeger
gateway` in its place); and a machine with no Jaeger AI instance yet is told to
run `jaeger setup` first.

Order of preference: gateway first (works for remote machines and alongside
a running gateway), local bridge fallback second (local convenience).

Optional auth: set `JAEGER_GATEWAY_KEY` on the gateway and the same value in
`ARES_JAEGER_GATEWAY_KEY` for ARES. The UI treats Jaeger AI as **available** only
when the gateway answers `GET /v1/health`. A local checkout
(`ARES_JAEGER_SOURCE_DIR` / `ARES_JAEGER_HOME`) enables install detection, character
browser paths, and degraded local-bridge fallback for turns — it does not
mark execution as ready by itself.

## Dependencies

- Python 3.11+
- Optional Jaeger AI install for `jaeger_local` (gateway recommended)
- Optional Hermes Agent (or other CLI adapters) when those backends are elected
- See `requirements.txt` for WebUI Python dependencies

## Compatibility

- Upgrade both together: WebUI and ares-agent must match.
- Always pin both image tags in Docker configurations to avoid interface mismatches.
- See [`../../docs/DEVELOPMENT.md`](../../docs/DEVELOPMENT.md) and [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).
- Policy defined in context of issue #2491.

## More Docs

- [Root README](../README.md)
- [Architecture](../../docs/ARCHITECTURE.md)
- [Development and deployment](../../docs/DEVELOPMENT.md)
- [Security](../../docs/SECURITY.md)

## Common Local Host / Docker Failures

- Host API at `localhost` fails from WebUI. Container `localhost` means the container itself, not the host. Use `host.docker.internal` to reach host-local services.
- `sudo docker compose up -d` can make `${HOME}` expand to the root user's home, so Docker mounts the wrong `.ares` directory instead of your real `~/.ares`. Set `ARES_HOME=/home/you/.ares` explicitly.
