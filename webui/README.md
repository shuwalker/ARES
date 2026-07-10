# ARES Web UI

Web interface for ARES — Artificial Reasoning Entity System.

Forked from [hermes-webui](https://github.com/nesquena/hermes-webui), rebranded as ARES.

## Install

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.sh | bash
```

**Windows (PowerShell):**
```powershell
iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)
```

**Windows (no terminal):**
Download [`start_ares.bat`](webui/start_ares.bat) and double-click it.

All paths auto-install Python if needed, clone the repo, set up a venv, install dependencies, and start the server. Open http://localhost:8787 in your browser — the onboarding wizard handles the rest.

**Remote access:** Install [Tailscale](https://tailscale.com) on both machines, sign into the same account, then access via `http://<tailscale-ip>:8787`.

## Manual start

```bash
cd ARES/webui
python server.py
# → http://localhost:8787
```

## What Changed from Hermes WebUI

- Title, favicon, manifest → ARES branding
- Default skin → "ares" (red accent)
- Server header → `ARESWebUI/`
- Update checker → tracks ARES, Hermes, and JROS repos
- `api/persona.py` — JROS persona injection module
- `api/characters.py` — full character browser data loader for JROS `character/v1` YAML
- `static/characters.js` + `static/characters.css` — avatar tab UI with character list, detail pane, traits, lore, and active persona selection
- `static/characters/` and `static/persona-cards/` — checked-in character art used by the avatar browser and public website assets
- All Hermes-facing UI strings rebranded

## Character Avatar Tab

The Characters panel is the visual front door for ARES identity selection. It exposes 14 JROS-backed personas with avatar art, roles, voice tone, traits, lore, backstory, and speech patterns.

Runtime paths:

- `GET /api/ares/characters` — list all characters with summary/detail data
- `GET /api/ares/character?id=<id>` — load one character YAML
- `GET /api/ares/persona/current` — current active persona
- `POST /api/ares/persona/set` — set active persona from the UI

The public website/README showcase image is generated from the same checked-in character card art and lives at `../docs/assets/character-tab-showcase.png`.

## JROS Backend (gateway)

The backend selector's JROS mode runs each chat turn on a **JROS gateway
server** over HTTP — the same integration shape as the Hermes Gateway bridge.
JROS runs as its own process (so it never fights a running JROS TUI/app for
the instance lock), and it can live on a different machine:

```bash
# on the machine where JROS is installed (same box, or a PC on your network)
jaeger gateway                          # localhost only, port 8643
jaeger gateway --host 0.0.0.0 --port 8643   # reachable from other machines

# on the machine running ARES (skip if JROS is on the same box)
export ARES_JROS_GATEWAY_URL=http://<jros-host>:8643
```

Optional auth: set `JAEGER_GATEWAY_KEY` on the gateway and the same value in
`ARES_JROS_GATEWAY_KEY` for ARES. The UI's JROS option lights up when the
gateway answers `GET /v1/health`. `ARES_JROS_DIR` is still used by the
character browser and update checker, but chat no longer needs a local JROS
checkout.

## Dependencies

- Python 3.11+
- [Hermes Agent](https://hermes-agent.nousresearch.com/) (installed in editable mode)
- See `requirements.txt` for Python deps
