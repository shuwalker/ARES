# Installing And Running ARES

ARES currently supports three practical local run paths and two planned
packaging paths.

## Web Mode

Use this when you want the browser-based ARES Web UI.

```bash
cd /path/to/ARES
./start.sh
```

Then open:

```text
http://localhost:8788
```

The root `start.sh` is a convenience wrapper around `services/controller/start.sh`.

## Developer Mac App Mode

Use this when you want the native macOS shell with menu bar controls, native
settings, server control, remote access status, and the Web UI inside a
`WKWebView`.

```bash
cd /path/to/ARES
swift run ARES
```

The Mac app expects the Web UI source and Python environment to exist in the
repo checkout. It can start the Web UI server for you, but it is not yet a
fully self-contained drag-and-drop app.

## Windows App Mode

Use this when you want the Windows native wrapper around the ARES Web UI. This
is the Windows version of the native app idea: a Tauri shell that opens the Web
UI in a desktop window and can grow native Windows integrations around it.

```powershell
cd /path/to/ARES
.\start.sh
# or, from the controller tree:
# cd services\controller
# .\.venv\Scripts\python.exe -m uvicorn fastapi_app.main:app --host 127.0.0.1 --port 8788
```

In a second PowerShell window, build/run the Tauri wrapper if present in your checkout (path may be `ARES-Windows/` when that tree is available):

```powershell
cd /path/to/ARES
cd ARES-Windows
cargo tauri dev
```

The current Windows wrapper expects the Web UI to already be running on
`http://127.0.0.1:8788`. The intended next step is to make the Windows wrapper
start/stop the Web UI itself, similar to the Mac developer app.

## First Local Setup

Run the installer from the repo root:

```bash
cd /path/to/ARES
bash install.sh
```

When run from a checkout, the installer deploys that exact checkout into
`~/.ares` so local Web UI changes are not replaced by a different remote
revision. The installer also registers `ares`, `hermes`, and `jaeger` in
`~/.local/bin` and adds that directory to zsh's login path.

The installer:
- Detects or installs JaegerAI when available (optional for saving a Local Profile)
- Creates a Python virtual environment in `services/controller/.venv`
- Installs Python dependencies
- Configures a live adapter when one is detected (defaults to `jros_local`)

**Options:**
- `--with-ares` — also install Ares Agent package (optional coding addition; not a backend mode)
- `--no-start` — skip auto-starting the server after install
- `--backend auto|jros_local|hermes_local|claude_local|...` — elect a live adapter ID (deleted modes `ares`/`hybrid` are rejected)

After install, use any of the run modes above (Web, Mac app, or Windows).

## Future Standalone App Modes

The planned standalone macOS package will bundle:

- `ARES.app`
- `services/controller/` and `apps/web/`
- Python runtime/environment
- Python dependencies
- first-run setup/onboarding

The planned standalone Windows package will do the same job through the Tauri
wrapper when available, producing a Windows installer/desktop app around
the Web UI.

That packaging is not complete yet. Current native builds are for
local/developer use. The native app is an ARES control shell around the Web UI;
it does not replace JaegerAI's character/runtime app or Hermes's own TUI.

## Windows App Notes

The Windows/Tauri companion app notes live at
[ARES-Windows/INSTALL.md](ARES-Windows/INSTALL.md).
