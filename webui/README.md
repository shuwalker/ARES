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

## Dependencies

- Python 3.11+
- [Hermes Agent](https://hermes-agent.nousresearch.com/) (installed in editable mode)
- See `requirements.txt` for Python deps

## Compatibility

The WebUI is coupled to Hermes Agent internals. In practice, version skew can cause import or behavior drift.
- **Upgrade both together**: upgrade or pin WebUI and hermes-agent together (same release train/version/date), especially before enabling production traffic.
- When running in Docker, you should pin both image tags together (e.g. same tag/date).
- Running pinned older/newer combinations is untested and unsupported until the stable API boundary work in [docs/rfcs/agent-source-boundary.md](docs/rfcs/agent-source-boundary.md) / [#2491](#2491) is in place.
- For Docker-based deployments and guides, see [docs/docker.md](docs/docker.md).

## Advanced & Troubleshooting Documentation

For more architectural and setup information, see:
- [Why Hermes?](docs/why-hermes.md)
- [WSL Autostart Guide](docs/wsl-autostart.md)

### Common Local Host / Docker Failures

- **Host API at `localhost` fails from WebUI**: Container `localhost` means the container itself, not the host machine. To connect to a local provider (like Ollama or Jaeger), use `host.docker.internal` instead of `localhost`.
- **`sudo docker compose up -d` can make `${HOME}` expand to the root user's home**: Docker mounts the wrong `.hermes` directory instead of your real `~/.hermes`. To fix, explicitly run `HERMES_HOME=/home/you/.hermes` or set it in your environment.
