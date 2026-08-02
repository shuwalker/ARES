# Developer & Operator Guide

| Attribute | Details |
| :--- | :--- |
| **Status** | Active Operational Manual |
| **Audience** | Developers, DevOps Engineers, System Administrators |
| **Owner** | ARES engineering maintainers |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Install scripts, package manifests, workflows, and verification commands |

This guide covers local environment setup, application execution paths, external provider registration, containerized deployments, WSL integration, and troubleshooting procedures.

---

## 1. Quick Start & Execution Modes

ARES supports three primary local execution paths:

### Developer Mode (Native macOS Shell)
Launches the native macOS app shell built with SwiftUI and WKWebView:
```bash
swift run ARES
```

### Standalone Web Mode (Development Server)
Launches the Python FastAPI controller and React SPA web application:
```bash
./start.sh
# Access the web UI at http://localhost:8788
```

Additional native clients are planned, but this repository currently ships the
macOS and Web paths above. Do not document an untracked client directory as an
available execution mode.

---

## 2. Environment Setup & Installation

### First-Time Local Installation

```bash
git clone https://github.com/shuwalker/ARES.git
cd ARES

# Run automated installer
bash install.sh
```

The installer script automatically handles:
- Detecting or initializing Python virtual environments (`.venv`).
- Installing required Python dependencies (`requirements.txt`).
- Configuring active provider adapters (`jaeger_local`, `hermes_local`, or `unassigned`).

### Installation Options
- `--no-start`: Skips auto-launching the web server after installation completes.
- `--backend <name>`: Elects an initial runtime provider (defaults to `unassigned`).

---

## 3. External AI Runtime Registry

External AI runtimes (Jaeger AI, Ollama, Hermes Agent, and cloud LLMs) are managed independently. ARES discovers and registers them via `~/.ares/providers.json` (override using `ARES_PROVIDER_REGISTRY_PATH`).

### Configuration Schema (`~/.ares/providers.json`)

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

> [!NOTE]
> **Provider Registration vs. Election**
> Registering a provider makes it available for selection. A provider becomes active only when explicitly elected via the `/api/ares/providers` endpoint or the UI settings panel.

---

## 4. Container Deployment (Docker)

Docker configurations are located under `services/controller/`:

```bash
cd services/controller

# Single-container build
docker build -t ares-controller .
docker run -d -p 8788:8788 -v ares_data:/root/.ares ares-controller

# Multi-container orchestration
docker compose -f docker-compose.three-container.yml up -d
```

### Production image security model

ARES production Docker containers do not grant passwordless sudo or escalate privileges. Container execution starts under an unprivileged `areswebui` user in single-tenant deployments, dropping root permissions prior to launching the application server.

### Container Networking & Host API URLs

Inside a container, `localhost` means *that container*. If an API base URL set to localhost fails from Docker, configure the container network host bridge:
- Use `host.docker.internal` or `host.containers.internal` with `--add-host host.docker.internal:host-gateway`.
- Avoid running `sudo docker compose up -d` without explicit `ARES_HOME=/home/youruser/.ares` export, as `sudo` often changes `$HOME` to `/root`, causing `${ARES_HOME:-${HOME}/.ares}` becomes `/root/.ares` instead of your real user home. Validate configuration using `docker compose config`.

### Related issues
Refer to issues #3012 and #3006 for Docker networking and permission hardening details.


---

## 5. WSL & Linux Autostart Configuration

For Linux/WSL environments, system autostart can be configured using a systemd service unit:

```ini
[Unit]
Description=ARES Assistant Controller Service
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

---

## 6. Troubleshooting & Diagnostics

- **Controller Server Startup Failure**: Verify that Python 3.10+ is active and dependencies are installed in `.venv`.
- **Database Lock Warnings**: Check file permissions on `{ARES_HOME}/webui_state/` and ensure no orphaned instances hold WAL file locks.
- **Runtime Disconnected**: Inspect network connectivity to the provider endpoint and confirm environment key variables match `credential_env`.

### `AIAgent not available`

This error means the Python process serving ARES cannot import the external
Ares Agent package. First confirm the checkout and any symlink resolve to a real
agent module:

```bash
ls -la /path/to/ares-agent
readlink /path/to/ares-agent
ls /path/to/ares-agent/agent/__init__.py
```

Then confirm `ARES_WEBUI_AGENT_DIR` and the Python interpreter shown in the
controller diagnostic refer to the intended installation. The usual repair is
to install the agent into that same interpreter in editable mode:

```bash
cd /path/to/ares-agent
pip install -e .
```

Restart ARES and verify the import directly with that interpreter. Do not copy
agent sources into the controller or silently fall back to another runtime.

---

## 7. Safe Onboarding and Reinstallation

- Detect an existing installation before creating configuration or state.
- Use isolated state directories for trials and automated verification.
- Never delete, replace, or migrate a real provider home without explicit
  operator approval.
- Never print complete secret-bearing files during diagnosis.
- Treat Jaeger AI, Hermes, Ollama, and other workers as peer products. ARES may
  detect them or delegate to their installers, but does not copy their runtime
  implementation into this repository.
- New Jaeger configuration uses `ARES_JAEGER_HOME`,
  `ARES_JAEGER_GATEWAY_URL`, and `ARES_JAEGER_GATEWAY_KEY`. Retired JROS names
  are compatibility inputs only and must not be emitted by new launchers.

## 8. Verification

Run checks from the repository they validate:

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

The controller test script owns its supported Python environment. Use isolated
ports and state, and confirm the process serving the port belongs to ARES—not a
legacy Hermes Web UI checkout—before interpreting browser results.

## 9. Contract Changes

For a contract-affecting PR, include `Contract Routing` and `Contract Change`
in the PR body. The contract tests and corresponding docs must move together; tests
must not silently redefine behavior without changing its public contract.

This static coverage is advisory. It is not an automated policy gate and does not enforce PR-body content or replace review. A future release-time
check may surface missing declarations, and each release batch should list its
contract-affecting changes explicitly.

### Documentation impact

Start work at [`AGENTS.md`](../AGENTS.md) and route through
[`docs/README.md`](README.md). A change must update its owning document when it
alters product behavior, state ownership, a setting, an API, a trust boundary,
or an accepted decision. Feature specifications must state what is implemented
and what remains intended.
