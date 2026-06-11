# Visual Example: What You'll See

This shows exactly what appears in each window when running the three-window setup.

## Full Screen Layout

### Recommended: 3 Panes in tmux/iTerm

```
┌─────────────────────────────────────────────────────────────┐
│ LEFT: ARES Daemon          │ RIGHT: TUI Dashboard            │
│                            │                                 │
│ $ ares start --daemon      │ $ python tools/tui_dashboard.py │
│                            │                                 │
│ ✓ ARES daemon starting     │ ════════════════════════════   │
│ ✓ Collaboration hub        │ CLAUDE ↔ HERMES COLLABORATION   │
│ ✓ Service manager ready    │ ════════════════════════════   │
│                            │                                 │
│                            │ [Waiting for activity...]       │
│                            │                                 │
│                            │ (Updates in real-time below)    │
│                            │                                 │
│                            │                                 │
├─────────────────────────────────────────────────────────────┤
│ BOTTOM: Claude Test                                         │
│                                                              │
│ $ python tools/test_collaboration.py                        │
│ [Running...]                                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Window 1: ARES Daemon (Backend)

```bash
$ cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
$ ares start --daemon
```

Output (stays running):
```
[2025-05-21 14:23:40] INFO ares.api: ARES API starting — initializing all services
[2025-05-21 14:23:40] INFO ares.runtime.collaboration: ✓ Collaboration hub initialized
[2025-05-21 14:23:40] INFO ares.api: ✓ ARES API server ready on http://localhost:8000
[2025-05-21 14:23:40] INFO ares.runtime.daemon: ✓ Daemon healthy, press Ctrl+C to stop
```

That's it. This window just runs in the background.

## Window 2: TUI Dashboard (Observable)

```bash
$ cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
$ python tools/tui_dashboard.py
```

**Before test starts:**
```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[Waiting for activity...]

────────────────────────────────────────────────────────────────────────────────
Watching 0 activities | q to quit
```

**As test runs (real-time updates):**

```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[14:23:45] ℹ️  CLAUDE: thinking
[14:23:45] 📤 CLAUDE → HERMES (action: echo)
[14:23:45] 📨 HERMES ← CLAUDE (task: echo)
[14:23:46] ℹ️  CLAUDE: thinking
[14:23:46] ✅ HERMES completed echo: {'output': 'Hello from Claude!'}...

────────────────────────────────────────────────────────────────────────────────
Watching 5 activities | q to quit
```

**Continuing as more tasks complete:**

```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[14:23:45] ℹ️  CLAUDE: thinking
[14:23:45] 📤 CLAUDE → HERMES (action: echo)
[14:23:45] 📨 HERMES ← CLAUDE (task: echo)
[14:23:46] ℹ️  CLAUDE: thinking
[14:23:46] ✅ HERMES completed echo: {'output': 'Hello from Claude!'}...
[14:23:47] 📤 CLAUDE → HERMES (action: terminal)
[14:23:47] 📨 HERMES ← CLAUDE (task: terminal)
[14:23:48] ℹ️  HERMES: thinking
[14:23:49] ✅ HERMES completed terminal: {'output': "Hermes executed this..."}...
[14:23:50] 📤 CLAUDE → HERMES (action: file_read)
[14:23:50] 📨 HERMES ← CLAUDE (task: file_read)
[14:23:51] ✅ HERMES completed file_read: {'output': '127.0.0.1  localhost...'}...
[14:23:52] ℹ️  CLAUDE: thinking

────────────────────────────────────────────────────────────────────────────────
Watching 12 activities | q to quit
```

**When test completes:**

```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[14:23:45] ℹ️  CLAUDE: thinking
[14:23:45] 📤 CLAUDE → HERMES (action: echo)
[14:23:45] 📨 HERMES ← CLAUDE (task: echo)
[14:23:46] ℹ️  CLAUDE: thinking
[14:23:46] ✅ HERMES completed echo: {'output': 'Hello from Claude!'}...
[14:23:47] 📤 CLAUDE → HERMES (action: terminal)
[14:23:47] 📨 HERMES ← CLAUDE (task: terminal)
[14:23:48] ℹ️  HERMES: thinking
[14:23:49] ✅ HERMES completed terminal: {'output': "Hermes executed this..."}...
[14:23:50] 📤 CLAUDE → HERMES (action: file_read)
[14:23:50] 📨 HERMES ← CLAUDE (task: file_read)
[14:23:51] ✅ HERMES completed file_read: {'output': '127.0.0.1  localhost...'}...
[14:23:52] ℹ️  CLAUDE: thinking

────────────────────────────────────────────────────────────────────────────────
Watching 12 activities | q to quit
```

**Dashboard stays open** and keeps the full activity history visible. You can leave it running and it shows all future collaboration activity.

## Window 3: Claude Test (Trigger)

```bash
$ cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
$ python tools/test_collaboration.py
```

**Full output:**

```
============================================================
CLAUDE ↔ HERMES COLLABORATION TEST
============================================================

[1] Connecting to hub...
✓ claude connected to hub
✓ claude registered with hub

[2] Test 1: Echo
📤 Requesting echo from hermes (task: abc12345)
    Result: {'output': 'Hello from Claude!', 'code': 0}
    ✓ PASSED

[3] Test 2: Terminal Command
📤 Requesting terminal from hermes (task: def67890)
    Result: {'output': "Hermes executed this\n", 'code': 0}
    ✓ PASSED

[4] Test 3: File Read
📤 Requesting file_read from hermes (task: ghi11111)
    Result: {'output': '127.0.0.1\tlocalhost\n...', 'code': 0}
    ✓ PASSED

============================================================
✅ ALL TESTS PASSED
============================================================

Bidirectional Claude ↔ Hermes collaboration is working!
Hub is routing tasks correctly.
```

## Key Observations

### Timing
- **[14:23:45]** — Claude logs "thinking"
- **[14:23:45]** — Claude sends request (📤)
- **[14:23:45]** — Hub logs receive (📨)
- **[14:23:46]** — Hermes logs thinking
- **[14:23:46]** — Hub logs completion (✅)
- **Elapsed: 1 second** for the full cycle

### What's Visible
- ✅ **Claude's thinking** — "Testing echo with Hermes"
- ✅ **Claude's request** — Action and target visible
- ✅ **Hermes receiving** — Task ID and action shown
- ✅ **Hermes completing** — Result preview in activity
- ✅ **Round trip** — Message sent, received, completed

### Real-Time
- Activities appear in TUI **immediately** as they happen
- No delay between Claude's action and TUI display
- Perfect for watching agent coordination live

## Multiple Integrations

If you have **multiple Claude processes** requesting work:

```bash
# Terminal 3a
$ python tools/test_collaboration.py

# Terminal 3b (in parallel)
$ python other_script.py  # Also uses client.request_task()
```

TUI shows both:
```
[14:23:45] 📤 CLAUDE → HERMES (action: echo)
[14:23:45] 📤 CLAUDE → HERMES (action: terminal)      # Different task
[14:23:46] 📨 HERMES ← CLAUDE (task: echo)
[14:23:46] 📨 HERMES ← CLAUDE (task: terminal)       # Hermes queues both
[14:23:47] ✅ HERMES completed echo
[14:23:48] ✅ HERMES completed terminal
```

The hub automatically handles queueing and routing.

## Symbol Legend

| Symbol | Meaning | Example |
|--------|---------|---------|
| 📤 | Message sent from one agent | `CLAUDE → HERMES` |
| 📨 | Message received by agent | `HERMES ← CLAUDE` |
| ✅ | Task completed successfully | `HERMES completed terminal` |
| ❌ | Task failed with error | `HERMES failed terminal: timeout` |
| ℹ️ | Information/thinking logged | `CLAUDE: thinking` |
| 🔨 | Tool invoked | `HERMES used pytest` |

## Closing

**Quit TUI Dashboard** (Window 2):
```
q (or Ctrl+C)
```

Output:
```
Dashboard closed.
```

**Stop ARES Daemon** (Window 1):
```
Ctrl+C
```

Output:
```
^C
[2025-05-21 14:23:52] INFO ares.runtime.daemon: ✓ Daemon shutdown gracefully
```

---

That's the full experience. Three terminals, watching both agents coordinate in real-time, exactly like the Word document collaboration view.
