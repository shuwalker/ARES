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
http://localhost:8787
```

The root `start.sh` is a convenience wrapper around `webui/start.sh`.

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

## Windows Companion App Mode

Use this when you want the Windows native wrapper around the ARES Web UI. This
is the Windows version of the native app idea: a Tauri shell that opens the Web
UI in a desktop window and can grow native Windows integrations around it.

```powershell
cd /path/to/ARES
cd webui
.\.venv\Scripts\python.exe server.py
```

In a second PowerShell window, build/run the Tauri wrapper from:

```powershell
cd /path/to/ARES
cd ARES-Windows
cargo tauri dev
```

The current Windows wrapper expects the Web UI to already be running on
`http://127.0.0.1:8787`. The intended next step is to make the Windows wrapper
start/stop the Web UI itself, similar to the Mac developer app.

## First Local Setup

Run the installer from the repo root:

```bash
cd /path/to/ARES
bash install.sh
```

The installer:
- Detects or installs JaegerAI (required Companion runtime)
- Creates a Python virtual environment in `webui/.venv`
- Installs Python dependencies
- Configures the backend (defaults to jros)

**Options:**
- `--with-hermes` — also install Hermes Agent (optional coding/terminal addition)
- `--no-start` — skip auto-starting the server after install
- `--backend jros|hermes|hybrid` — set the default backend mode

After install, use any of the run modes above (Web, Mac app, or Windows).

## Future Standalone App Modes

The planned standalone macOS package will bundle:

- `ARES.app`
- `webui/`
- Python runtime/environment
- Python dependencies
- first-run setup/onboarding

The planned standalone Windows package will do the same job through the Tauri
wrapper in `ARES-Windows/`, producing a Windows installer/desktop app around
the Web UI.

That packaging is not complete yet. Current native builds are for
local/developer use.

## Windows Companion App Notes

The Windows/Tauri companion app notes live at
[ARES-Windows/INSTALL.md](ARES-Windows/INSTALL.md).
