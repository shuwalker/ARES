# ARES + JROS Integration Guide

ARES supports JROS as a first-class peer backend. The supported integration is service-style: install JROS once at `~/jaeger` (or set `JAEGER_HOME`), then ARES talks to the existing `jaeger bridge` process. ARES does not install JROS inside its Python virtual environment and does not clone a second JROS copy.

## Install JROS

```bash
curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JROS/master/scripts/install.sh | bash
cd ~/jaeger
./jaeger agent create
```

## Install ARES with JROS as the primary backend

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES
bash webui/scripts/install.sh --backend jros
cd ~/.ares/webui
./venv/bin/python server.py
```

Open http://localhost:8787. ARES will route normal chat turns to JROS through the bundled stdlib bridge client at `webui/api/jros_client.py`.

## Switch an existing ARES install to JROS

Use the Backend Selector in the UI, or call the API:

```bash
curl -s http://127.0.0.1:8787/api/ares/backend/set \
  -H 'Content-Type: application/json' \
  -d '{"backend":"jros"}'
```

Valid backend values are `hermes`, `jros`, and `hybrid`.

## Backend comparison

| Capability | Hermes backend | JROS backend |
| --- | --- | --- |
| Primary role | General agent orchestration | Embodied/persona/robotics agent framework |
| Runtime path | Hermes Agent / gateway / in-process worker | Existing `~/jaeger/jaeger bridge` stdio NDJSON process |
| Install model | Installed as ARES WebUI Python dependency or external Hermes checkout | Installed separately once; not vendored into ARES venv |
| Best fit | Coding, ops, MCP, skills, cron, provider routing | Character/persona, embodied interaction, robot/device workflows |
| Live IO | WebUI SSE stream and tool events | WebUI SSE stream fed by JROS tool/state frames |

## Environment variables

- `JAEGER_HOME` or `ARES_JAEGER_HOME` — non-default JROS install path. Defaults to `~/jaeger`.
- `ARES_JROS_INSTANCE` — optional JROS instance name. Omit to use the active/default JROS agent.
- `ARES_JROS_DIR` — optional source checkout path for character/schema browsing. Not required for chat turns.

## Troubleshooting

- If ARES says JROS is unavailable, confirm `~/jaeger/jaeger` exists and is executable.
- If the first JROS response is slow, that is expected: the bridge may need to load the active local model. Keep the WebUI running so the bridge client can be reused.
- If you only want Hermes, install normally or run `bash webui/scripts/install.sh --backend hermes`.
