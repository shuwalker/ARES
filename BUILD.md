# Building ARES-Desktop

## On Your Mac Studio

### Prerequisites
- macOS 13+ (Ventura or later)
- Xcode 15+
- ARES daemon must be running

### Build Steps

```bash
cd ARES-Desktop

# Build for Release
xcodebuild -scheme HermesDesktop -configuration Release build

# Or build directly with Xcode
open Package.swift
# Then in Xcode: Product > Build
```

### Run the App

After building, the app is at:
```
build/Release/HermesDesktop.app
```

Or run directly from Xcode:
```bash
xcodebuild -scheme HermesDesktop -configuration Release run
```

### Add to Dock (Permanent Installation)

```bash
# Copy to Applications
cp -r build/Release/HermesDesktop.app /Applications/ARES.app

# Right-click app in Applications > Options > Keep in Dock
```

---

## Before You Launch the App

Make sure the ARES daemon is running:

```bash
# Terminal 1: Start ARES daemon
ares start

# Terminal 2: Start Hermes bridge (if not running)
python3 ares/runtime/ares_bridge_minimal.py &

# Terminal 3: Check health
ares doctor
```

The app will show an error if the daemon isn't reachable at `http://localhost:7860`.

---

## What the App Does

**Status Tab** — Shows ARES identity and system state
**Chat Tab** — Send messages to ARES and see responses
**Memory Tab** — Browse ARES's episodic memory entries

---

## Troubleshooting

### App shows "ARES Daemon Not Running"
- Make sure `ares start` is running
- Check: `ares status` (should show "RUNNING")
- Check logs: `ares log -f`

### Chat not responding
- Check Hermes bridge is running: `lsof -i :9876`
- If missing, start: `python3 ares/runtime/ares_bridge_minimal.py`
- Check bridge logs in `~/.ares/logs/bridge.log`

### Build fails
- Update Xcode: `xcode-select --install`
- Check Swift version: `swift --version` (should be 5.9+)
- Clean build: `xcodebuild clean && xcodebuild build`

---

## Development

To iterate on the app:

```bash
# Edit Swift files in Sources/HermesDesktop/App/
# - AresAPI.swift: HTTP client
# - AresAppState.swift: State management
# - ContentView.swift: UI

# Rebuild:
xcodebuild -scheme HermesDesktop -configuration Release build

# Or use Xcode IDE for interactive development
open Package.swift
```

---

## Architecture

The app connects to the ARES daemon at `http://localhost:7860` via these endpoints:

- `GET /api/status` — System status
- `GET /api/identity` — ARES's name/role
- `GET /api/face` — Current face state
- `POST /api/chat` — Send a message
- `GET /api/memory/episodics` — Memory entries

See `ares/api.py` for full API reference.
