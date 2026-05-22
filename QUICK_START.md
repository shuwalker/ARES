# ARES Quick Start — Get It Working in 5 Minutes

## What I Fixed

### 1. Python Daemon & CLI ✅
- Fixed config reference bugs in `ares/cli.py`
- Set up proper Hermes bridge at localhost:9876
- Config file ready at `~/.ares/config/ares.toml`

### 2. ARES-Desktop App ✅
- Completely rebuilt from scratch
- Connects to daemon at `http://localhost:7860`
- New UI: Status, Chat, Memory tabs
- Auto-detects if daemon is running

---

## Your Next Steps (On Mac Studio)

### Step 1: Pull the Latest Code
```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
git fetch origin
git checkout claude/sleepy-maxwell-15R6y
```

### Step 2: Install Python Package
```bash
pip install -e .
ares --help  # Should work
```

### Step 3: Start the Hermes Bridge
Terminal 1:
```bash
python3 ares/runtime/ares_bridge_minimal.py
# Should print: Serving on port 9876...
```

### Step 4: Start ARES Daemon
Terminal 2:
```bash
ares start
# Should print: ARES started (pid XXXX)
```

Verify it's running:
```bash
ares status
# Should show: RUNNING
```

### Step 5: Build the Swift App
Terminal 3:
```bash
cd ARES-Desktop
xcodebuild -scheme HermesDesktop -configuration Release build
```

Wait 2-3 minutes for build to complete...

### Step 6: Run the App
Option A (Easiest):
```bash
xcodebuild -scheme HermesDesktop -configuration Release run
```

Option B (Install to Applications):
```bash
cp -r build/Release/HermesDesktop.app /Applications/ARES.app
# Then launch from Dock
```

---

## Testing

Once the app launches, you should see:

1. **Status Tab** — Shows "ARES" as the name
2. **Chat Tab** — Type a message and hit Send
3. **Memory Tab** — Shows any stored memories

If you see an error, run:
```bash
ares doctor
```

This shows what's connected and what isn't.

---

## Troubleshooting

### App shows "ARES Daemon Not Running"
Make sure all 3 terminals have these running:
```bash
# Terminal 1
python3 ares/runtime/ares_bridge_minimal.py

# Terminal 2
ares start

# Terminal 3
ares status  # Should show RUNNING
```

### Chat not responding
```bash
# Check the bridge is at 9876
lsof -i :9876
# Should show a Python process

# Check daemon
lsof -i :7860
# Should show a Python process
```

### Build fails
```bash
# Make sure you have Swift 5.9+
swift --version

# Clean and retry
xcodebuild clean
xcodebuild -scheme HermesDesktop -configuration Release build
```

---

## What's Different

| Before | After |
|--------|-------|
| Old hermes-desktop SSH code | Clean daemon-focused UI |
| Kanban, cron jobs, sessions | Status, Chat, Memory |
| Requires SSH setup | Works locally out of box |
| Broken on startup | Auto-detects connection |

---

## Next Steps After Getting It Working

1. **Keep it running:** Create launchd services for permanent daemon/bridge startup
2. **Add more features:** Task queue, approvals, memory management
3. **Polish the UI:** Avatar rendering, voice states, animations
4. **Integrate tools:** MCP servers for actual automation

See CLAUDE.md for the full ARES roadmap.

---

## Questions?

Check these files for more details:
- `BUILD.md` — Build instructions and troubleshooting
- `CONNECTION_ISSUES.md` — Why things were broken and how they're fixed
- `CLAUDE.md` — ARES architecture and priorities
