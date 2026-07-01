# ARES Web UI

Web interface for ARES — Artificial Reasoning Entity System.

Forked from [hermes-webui](https://github.com/nesquena/hermes-webui), rebranded as ARES.

## Running

```bash
# Create venv (Python 3.11+)
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install -e ~/.hermes/hermes-agent  # Hermes Agent (editable)

# Configure
cp .env.example .env
# Edit .env — set HERMES_WEBUI_PASSWORD

# Start
.venv/bin/python server.py
# → http://localhost:8787
```

## What Changed from Hermes WebUI

- Title, favicon, manifest → ARES branding
- Default skin → "ares" (red accent)
- Server header → `ARESWebUI/`
- Update checker → tracks ARES, Hermes, and JROS repos
- `api/persona.py` — JROS persona injection module
- All Hermes-facing UI strings rebranded

## Dependencies

- Python 3.11+
- [Hermes Agent](https://hermes-agent.nousresearch.com/) (installed in editable mode)
- See `requirements.txt` for Python deps
