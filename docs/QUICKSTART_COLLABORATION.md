# Quick Start: See Both Agents Working Together

This is the fastest way to get the Word document experience — two agents coordinating in real-time with all messages, tool use, and decisions visible.

## 3-Window Setup (5 minutes)

### Window 1: Start ARES Backend

```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System

# Start the daemon (runs the collaboration hub)
ares start --daemon
```

Expected output:
```
✓ ARES daemon starting
✓ Collaboration hub initialized
✓ WebSocket endpoints ready at ws://localhost:8000/ws/collaborate
✓ Activity stream endpoint ready at ws://localhost:8000/ws/activity-stream
```

### Window 2: Open TUI Dashboard

In a **new terminal** (tmux/split pane recommended):

```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System

# Watch both agents in real-time
python tools/tui_dashboard.py
```

Expected output:
```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[Waiting for activity...]
```

The dashboard is now **watching** the collaboration hub. When agents communicate, you'll see it here.

### Window 3: Trigger Collaboration

In a **third terminal**, run the test:

```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System

# Claude sends work to Hermes
python tools/test_collaboration.py
```

## Watch It Happen

As `test_collaboration.py` runs, **Window 2 (TUI Dashboard) updates in real-time**:

```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[14:23:45] ℹ️  CLAUDE: thinking
[14:23:45] 📤 CLAUDE → HERMES (action: echo)
[14:23:46] 📨 HERMES ← CLAUDE (task: echo)
[14:23:46] ℹ️  CLAUDE: thinking
[14:23:46] ✅ HERMES completed echo: {'output': 'Hello from Claude!'}...
[14:23:47] 📤 CLAUDE → HERMES (action: terminal)
[14:23:47] 📨 HERMES ← CLAUDE (task: terminal)
[14:23:48] ✅ HERMES completed terminal: {'output': "Hermes executed this"}...
[14:23:49] 📤 CLAUDE → HERMES (action: file_read)
[14:23:50] 📨 HERMES ← CLAUDE (task: file_read)
[14:23:50] ✅ HERMES completed file_read: {'output': '127.0.0.1  localhost...'}...
[14:23:51] ℹ️  CLAUDE: thinking

Watching 10 activities | q to quit
```

**This is exactly like the Word document** — you can see:
- ✅ Claude thinking about what to ask
- 📤 Claude sending a request
- 📨 Hermes receiving it
- ✅ Hermes completing the work
- Both agents' activities visible simultaneously

## What Each Symbol Means

| Symbol | Meaning |
|--------|---------|
| 📤 | Claude/Hermes sent a message |
| 📨 | Claude/Hermes received a message |
| ✅ | Task completed successfully |
| ❌ | Task failed with error |
| ℹ️  | Thinking/reasoning/logging |

## It's All Automatic

You don't need to do anything special. The system automatically logs:

1. **When Claude requests a task** → `message_sent` activity
2. **When Hermes receives it** → `message_received` activity  
3. **When Hermes completes** → `task_completed` activity
4. **Each thinking step** → `thinking` activities

The TUI dashboard displays all of these **in real-time** as they happen.

## Next: Integrate Into Your Code

Once you see this working, you can integrate into your own workflows:

```python
from tools.collaboration_client import init_collaboration

# 1. Initialize
client = await init_collaboration("claude")

# 2. Log what you're thinking (appears in TUI as "ℹ️  CLAUDE: thinking")
await client.log_activity(
    activity_type="thinking",
    data={"thought": "I'm about to run a test"}
)

# 3. Request work (appears in TUI as "📤 CLAUDE → HERMES")
result = await client.request_task(
    action="terminal",
    params={"command": "pytest tests/ -q"},
    target="hermes"
)

# 4. See response in TUI (appears as "✅ HERMES completed terminal")
print(f"Tests passed: {result['output']}")
```

Everything you see in the TUI happens **automatically** — you don't need to manage the logging yourself (but you can add custom activities).

## Troubleshooting

**TUI shows "Waiting for activity..."**
- Make sure `test_collaboration.py` is running in Window 3
- Or run any other Python code that calls `client.request_task()`

**"Connection failed: HTTP 401"**
- Daemon crashed. Restart with: `ares start --daemon`
- Check status: `ares status`

**No activity appears**
- TUI may not be connected. Restart it: `python tools/tui_dashboard.py`
- Make sure all three windows are in the same ARES repo directory

## See Also

- **Full guide**: `docs/BIDIRECTIONAL_COLLABORATION.md` — detailed architecture and protocol
- **API reference**: `docs/COLLABORATION_SETUP.md` — protocol specification
- **Activity logging**: `tools/hermes_activity_logger.py` — helper for Hermes to log activities
