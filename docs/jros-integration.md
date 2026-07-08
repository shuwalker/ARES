# ARES + JROS Integration Guide

ARES supports JROS as a first-class peer backend. The supported integration is service-style: install JROS once, then ARES talks to the existing `jaeger bridge` process. ARES does not install JROS into its Python virtual environment and does not clone a second JROS copy.

## Mental Model

- **ARES** owns the user-facing product layer: UI, identity, continuity, backend choice, model choice, and presentation.
- **JROS** owns embodied/persona/robotics runtime behavior.
- **Hermes Agent** remains a peer runtime for tools, MCP, skills, cron, provider routing, coding, and operations.

Backend selection and model selection are separate. `backend=jros` means JROS executes the turn; it does not mean `model_provider=jros`.

## Install JROS

```bash
curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JROS/master/scripts/install.sh | bash
```

Then create or select a JROS agent using the JROS launcher from the installed Jaeger/JROS home.

## Install ARES with JROS as Primary Backend

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES
bash webui/scripts/install.sh --backend jros
```

Open:

```text
http://localhost:8787
```

ARES routes chat turns to JROS through `webui/api/jros_client.py`, which speaks the JROS v1 NDJSON bridge protocol.

## Switch an Existing ARES Install to JROS

Use the Backend Selector in the UI, or call:

```bash
curl -s http://127.0.0.1:8787/api/ares/backend/set \
  -H 'Content-Type: application/json' \
  -d '{"backend":"jros"}'
```

Valid values:

- `hermes`
- `jros`
- `hybrid`

## Path Resolution

All WebUI JROS/Jaeger path logic is centralized in `webui/api/jros_paths.py`.

| Variable | Purpose |
| --- | --- |
| `ARES_JAEGER_HOME` | ARES-specific override for the installed Jaeger/JROS home. |
| `JAEGER_HOME` | JROS-wide override for the installed Jaeger/JROS home. |
| `ARES_JROS_DIR` | Optional JROS source checkout path for source-tree features such as character/schema browsing. Not required for chat turns. |
| `ARES_CHARACTER_DIR` | Optional direct override for the character library directory. |
| `ARES_PERSONA_DIR` | Optional direct override for the legacy persona directory. |
| `ARES_JROS_CONFIG_PATH` | Explicit JROS instance `config.yaml` path. |
| `JAEGER_INSTANCE_DIR` | Explicit JROS instance directory; ARES appends `config.yaml`. |
| `ARES_JROS_INSTANCE` | Optional JROS instance name to pass to the bridge. |

Default installed home is the standard JROS installer location, normally `~/jaeger`.

## Backend Comparison

| Capability | Hermes backend | JROS backend |
| --- | --- | --- |
| Primary role | General agent orchestration | Embodied/persona/robotics agent framework |
| Runtime path | Hermes Agent worker/gateway | Existing `jaeger bridge` stdio NDJSON process |
| Install model | ARES dependency or external Hermes install | Installed separately once; not vendored into ARES venv |
| Best fit | Coding, ops, MCP, skills, cron, provider routing | Character/persona, embodied interaction, robot/device workflows |
| Live IO | WebUI SSE stream and tool events | WebUI SSE stream fed by JROS tool/state frames |

## Troubleshooting

- If JROS mode is unavailable, check that the installed `jaeger` launcher exists and is executable.
- If your JROS install is not in the standard location, set `ARES_JAEGER_HOME` or `JAEGER_HOME`.
- If character browsing fails but chat works, set `ARES_JROS_DIR` to a JROS source checkout or `ARES_CHARACTER_DIR` directly to the character directory.
- If the first JROS response is slow, the bridge may be loading the active model. Keep the WebUI running so the bridge client can be reused.
- If you only want Hermes mode, run `bash webui/scripts/install.sh --backend hermes` or select Hermes in the UI.
