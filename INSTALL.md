# ARES — Windows Desktop Skeleton
#
# From an agent's perspective this branch IS the product source.
# Run the steps below in order; each section ends in a verification command.

---
## 0 · Prerequisites

| Tool            | Minimum version | Check command                 |
|-----------------|-----------------|-------------------------------|
| Git             | 2.30+           | `git --version`               |
| Node.js         | 18 LTS+         | `node --version`              |
| Python          | 3.11+            | `python --version`            |
| Rust / rustup   | stable 1.78+    | `rustc --version`             |
| MSVC build env  | VS Build Tools  | `cl.exe` must be on PATH      |
| curl / wget     | any             | used for cloning + downloads  |

Verify Rust build tools:
```
rustup show
rustc --version
cargo --version
```

### Install Rust (if missing)
```
winget install Rustlang.Rustup
# or visit https://www.rust-lang.org/tools/install and run rustup-init.exe
# Ensure MSVC target:
rustup default stable-x86_64-pc-windows-msvc
```

### Install cargo-tauri
```
cargo install cargo-tauri --locked
```

---
## 1 · Clone the public `spiral` branch

```
git clone --branch spiral --depth 1 git@github.com:shuwalker/ARES.git
cd ARES
```

The branch contains ONLY:
- `src-tauri/` — Tauri shell (Rust + tauri.conf.json)
- `AGENTS.md` — this repo's agent guide
- `docs/` — screenshots + install guide
- `webui/` — ARES Web UI (Python server + static JS frontend)

Local-only files (never committed) like `.env`, `.venv/`, and wrapper venvs
are auto-ignored via `.gitignore`.

---
## 2 · Install the ARES Web UI

The web UI ships as raw Python + static assets — no JS bundler required.

```
cd webui
python -m venv .venv
source .venv/bin/activate      # Git Bash / MSYS
# Windows: source .venv/Scripts/activate
pip install -r requirements.txt
pip install -e .
deactivate
cd ..
```

Verify:
```
python webui/server.py --help   # should print usage, not crash
```

---
## 3 · Run the Web UI server (dev)

```
cd webui
python server.py
```

Open http://127.0.0.1:8787 — the ARES dashboard should load.

Verify:
```
curl -s http://127.0.0.1:8787 | head -5
```

The server is self-contained; no database or Docker is required for
local development.

---
## 4 · Build the Tauri desktop wrapper (Windows)

### 4a · cargo-tauri dev (debug build, windowed)
```
cd src-tauri
cargo tauri dev
```
A Tauri window opens and loads http://127.0.0.1:8787 automatically.

### 4b · cargo-tauri build (release build, installable)
```
cd src-tauri
cargo tauri build
```

Artifacts land in:
```
src-tauri/target/release/bundle/nsis/ARES Setup 0.1.0.exe    ← Windows installer
src-tauri/target/release/ARES.exe                             ← portable binary
```

Verify:
```
ls src-tauri/target/release/bundle/nsis/
```

---
## 5 · Expected runtime behavior

1. First launch installs the app under `%LOCALAPPDATA%\ARES\`
2. App starts **minimized to the system tray** on Windows (release mode)
3. Left-click the tray icon or choose **Show / Hide** to restore the window
4. Closing the window hides it to tray — Quit from the tray menu exits
5. `webui/` must be running on port 8787 for the Tauri window to load content
6. The desktop wrapper reads/writes state inside `%APPDATA%\ARES\` and
   `%LOCALAPPDATA%\ARES\` (scoped in `tauri.conf.json`)

---
## 6 · What to commit vs keep local

**Commit:** `src-tauri/src/main.rs`, `src-tauri/tauri.conf.json`,
`src-tauri/build.rs`, `src-tauri/Cargo.toml`, `src-tauri/icons/`,
`AGENTS.md`, `docs/`, `.gitignore`.

**Never commit (auto-ignored):**
- `webui/.venv/`, `webui/.env`, `webui/.ares_state/`, auth keys
- `src-tauri/target/`, `src-tauri/dist/`
- `windows-app/node_modules/`, `windows-app/dist/`
- `.hermes/`, `.venv-ares-wrapper/`

---
## 7 · Troubleshooting

**`cargo: command not found`**
Add Rust to PATH: add `%USERPROFILE%\.cargo\bin` to System PATH and restart.

**`cl.exe not found`**
Install "Desktop development with C++" workload via Visual Studio Installer.
Open "x64 Native Tools Command Prompt for VS" before running cargo.

**Tauri window stays blank**
1. Ensure `python webui/server.py` is running first
2. Check `http://127.0.0.1:8787` in Chrome — if the server is down the Tauri view shows an error page
3. Tauri v1 logs go to `src-tauri/target/release/.tauri-session/`

**Icon missing in tray**
Tauri on Windows converts `icon.ico` to template; ensure
`src-tauri/icons/icon.ico` exists inside `src-tauri/icons/`.

**Build fails with CSS / WebKit errors**
The Tauri shell does NOT bundle web assets. The `distDir` is `../webui`,
so the web server must be present and running for `cargo tauri dev`.
`cargo tauri build` in `custom-protocol` mode would need an extra build step;
until then, release mode loads from the running server.

**NSIS bundle not produced**
Install Inno Setup or NSIS, or run:
```
cargo install tauri-cli --features=native-tls
```
Tauri's NSIS bundler ships pre-built; bunlde failures usually mean
Visual Studio C++ build tools are missing.

---
## 8 · Updating the branch

From the repo root:
```
git pull origin spiral
cd webui && git pull && cd ..
cd src-tauri && cargo tauri build && cd ..
```

Commit only to the `spiral` branch from your fork;
push to your own remote and open a PR against `shuwalker/ARES:spiral`.

---
Last updated: 2026-07-05
Product: ARES 0.1.0 (Tauri wrapper, Windows skeleton)
