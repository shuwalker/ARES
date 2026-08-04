# ARES Development Guide

## Quick Start

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES
bash install.sh
```

The installer handles:
- Python virtual environment (`.venv`) and dependencies
- Provider adapter configuration (`jaeger_local`, `hermes_local`, or `unassigned`)

**Installer options:**
- `--no-start` — skip auto-launching after install
- `--backend <name>` — elect an initial runtime provider

### Run

```bash
# Web UI
./start.sh
# → http://localhost:8788

# Native macOS app
swift run ARES
```

## Onboarding

The first time ARES starts, you choose a provider, a workspace, and optionally set a password. The bootstrap supports Linux, macOS, and WSL2.

### Re-running onboarding safely

Do not delete `~/.ares` to see the wizard again. For a clean trial, use an isolated home:

```bash
mkdir -p ~/ares-onboarding-test
ARES_HOME=~/ares-onboarding-test/.ares \
ARES_WEBUI_STATE_DIR=~/ares-onboarding-test/webui \
ARES_WEBUI_PORT=8789 \
python3 bootstrap.py
```

## Docker

### Single-container (recommended)

```bash
git clone https://github.com/shuwalker/ARES
cd ARES
cp .env.docker.example .env
docker compose up -d
open http://localhost:8787
```

### Multi-container

```bash
cd services/controller
docker compose -f docker-compose.three-container.yml up -d
```

### Production security

The production image runs as unprivileged `areswebui` user after init. No `sudo`, no `NOPASSWD` escalation. Init phase runs as root for UID/GID alignment, then drops privileges.

### Container networking

Inside a container, `localhost` means that container. Use `host.docker.internal` with `--add-host host.docker.internal:host-gateway` for host services. Avoid `sudo docker compose up -d` without explicit `ARES_HOME` — `sudo` changes `$HOME` to `/root`.

## WSL / Linux autostart

```ini
[Unit]
Description=ARES Controller
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/ARES/services/controller
ExecStart=/home/user/ARES/services/controller/.venv/bin/python server.py
Restart=always
Environment=ARES_HOME=/home/user/.ares

[Install]
WantedBy=default.target
```

## Process supervision

Use launchd (macOS), systemd (Linux), or supervisord to keep ARES running. Pass `--foreground` to `bootstrap.py`:

```bash
python3 bootstrap.py --foreground
```

## Provider configuration

External runtimes are registered via `~/.ares/providers.json`:

```json
{
  "schema_version": 1,
  "providers": {
    "jaeger_local": {
      "enabled": true,
      "kind": "runtime",
      "endpoint": "http://127.0.0.1:8000",
      "credential_env": "ARES_JAEGER_GATEWAY_KEY",
      "capabilities": ["chat", "embodiment"]
    }
  }
}
```

Registering makes a provider available. It becomes active only when elected via the API or UI.

## Workspace Git

Workspace Git controls let the browser inspect Git state for the active session workspace. Configured in Settings → System.

## Troubleshooting

### Controller won't start
Verify Python 3.10+ is active and dependencies are installed in `.venv`.

### Database lock warnings
Check file permissions on `ARES_HOME/webui_state/` and ensure no orphaned instances hold WAL file locks.

### Runtime disconnected
Check network connectivity to the provider endpoint and confirm environment key variables match `credential_env`.

### "AIAgent not available"
The Python process serving ARES cannot import the external agent package. Fix:

```bash
ls -la /path/to/ares-agent
readlink /path/to/ares-agent
ls /path/to/ares-agent/agent/__init__.py
cd /path/to/ares-agent
pip install -e .
```

Restart ARES. Do not copy agent sources into the controller.

### Docker home bind mount permissions
`sudo docker compose up -d` can make `$HOME` expand to `/root/.ares`. Set `ARES_HOME=/home/you/.ares` explicitly.

## Verification

```bash
cd apps/web
npm run typecheck
npm test -- --run
npm run build

cd ../..
swift test

cd services/controller
./scripts/test.sh
```

## Safe practices

- Detect existing installations before creating configuration
- Use isolated state directories for trials
- Never delete or migrate a real provider home without explicit operator approval
- Never print complete secret-bearing files during diagnosis
- Treat Jaeger AI, Hermes, Ollama, and other workers as peer products — ARES may detect them but does not copy their runtime implementation

## Contributors

Matthew Jenkins (shuwalker) · Jenkins Robotics

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.
