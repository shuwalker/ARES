# Bidirectional Claude ↔ Hermes Collaboration

This guide shows how to see both Claude and Hermes working together in real-time, just like the Word document experience where you can watch multiple agents coordinate.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ARES Collaboration Hub                   │
│                   (CollaborationHub class)                   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Agent Registry:  "claude" ↔ WebSocket connection   │    │
│  │                  "hermes" ↔ WebSocket connection   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Activity Log (real-time events):                    │    │
│  │  - message_sent: Claude → Hermes                   │    │
│  │  - message_received: Hermes receives task          │    │
│  │  - tool_used: Agent invokes a tool                 │    │
│  │  - task_completed: Hermes returns result           │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ WebSocket Endpoints:                                │    │
│  │  /ws/collaborate  - Agent task routing              │    │
│  │  /ws/activity-stream - TUI dashboard subscription  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

         ↓                              ↓                  ↓
    Claude Client         Hermes Worker           TUI Dashboard
    (claude.py)          (hermes skill)           (tui_dashboard.py)
    
    • request_task()     • Listen on hub          • Subscribe to activity
    • log_activity()     • Execute tasks          • Display real-time feed
    • connect()          • task_completed()       • Show both agents' work
```

## Activity Types

When either agent does something, it's logged as an activity:

| Activity Type | Who | What It Means |
|---|---|---|
| `message_sent` | Claude | Claude just sent a task to Hermes |
| `message_received` | Hermes | Hermes received a task from Claude |
| `task_completed` | Either | Agent finished a task with result |
| `task_failed` | Either | Agent failed a task with error |
| `thinking` | Either | Agent logs internal reasoning |
| `tool_used` | Either | Agent invoked a tool (grep, pytest, etc) |

## Three-Window Setup (Like Word)

To see both agents working together, you need **three windows**:

### Window 1: ARES Daemon (Backend)
Runs the collaboration hub and routes tasks between agents.

```bash
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
ares start --daemon
```

Output: Logs hub startup, agent registration, task routing.

### Window 2: TUI Dashboard (Observable)
Displays real-time activity from both agents — like watching the Word document.

```bash
# Terminal 1: Watch the collaboration
python tools/tui_dashboard.py
```

Output:
```
================================================================================
CLAUDE ↔ HERMES COLLABORATION — Real-time Activity Feed
================================================================================

[14:23:45] 📤 CLAUDE → HERMES (action: terminal)
[14:23:46] 📨 HERMES ← CLAUDE (task: terminal)
[14:23:47] ✅ HERMES completed terminal: {'output': 'passed', 'code': 0}...
[14:23:48] ℹ️  CLAUDE: thinking
```

### Window 3: Test or Integration
Run Claude's side — send tasks to Hermes.

```bash
# Terminal 2: Run Claude's test
python tools/test_collaboration.py
```

Output:
```
============================================================
CLAUDE ↔ HERMES COLLABORATION TEST
============================================================

[1] Connecting to hub...
✓ claude connected to hub
✓ claude registered with hub

[2] Test 1: Echo
📤 Requesting echo from hermes (task: abc12345)
    [In TUI Dashboard you see: CLAUDE → HERMES, then HERMES received task]
✓ Task abc12345 completed
    [In TUI Dashboard you see: HERMES completed echo with result]
✓ PASSED
```

## What You See in the TUI

Each line in the dashboard represents an activity:

```
[HH:MM:SS] 📤 CLAUDE → HERMES (action: terminal)
  ↑         ↑    ↑     ↑  ↑
  |         |    |     |  └─ Target agent
  |         |    |     └────── Source agent
  |         |    └─────────── Activity emoji (sent)
  |         └───────────────── Activity type
  └──────────────────────────── Timestamp
```

The four activity emojis:
- 📤 = Message sent (Claude asking Hermes)
- 📨 = Message received (Hermes got the task)
- ✅ = Task completed (result returned)
- ❌ = Task failed (error occurred)

Real example sequence:
```
[14:23:45] 📤 CLAUDE → HERMES (action: terminal)
[14:23:46] 📨 HERMES ← CLAUDE (task: terminal)
[14:23:47] ℹ️  HERMES: thinking
[14:23:48] ✅ HERMES completed terminal: {'output': 'hello world'}...
[14:23:49] ✅ CLAUDE received result from HERMES
```

## Running Your Own Integration

To integrate into your own code (not just test):

### 1. Initialize Claude Client

```python
from tools.collaboration_client import init_collaboration

# Initialize
client = await init_collaboration("claude")

# Log what you're thinking
await client.log_activity(
    activity_type="thinking",
    data={"thought": "I'm about to ask Hermes to run tests"}
)
```

### 2. Request Work from Hermes

```python
result = await client.request_task(
    action="terminal",
    params={"command": "pytest tests/ -q"},
    target="hermes",
    timeout=30.0
)
```

The hub automatically logs:
- `message_sent` when Claude requests
- `message_received` when Hermes receives
- `task_completed` when Hermes returns result

### 3. Watch in TUI

Open `python tools/tui_dashboard.py` in another terminal.

You'll see both agents' activities in real-time:
```
[14:30:12] 📤 CLAUDE → HERMES (action: terminal)
[14:30:12] 📨 HERMES ← CLAUDE (task: terminal)
[14:30:15] ✅ HERMES completed terminal: {'passed': 45, 'failed': 2}...
```

## Protocol Details

### WebSocket Messages

**Agent → Hub (on /ws/collaborate):**

```json
{
  "type": "register",
  "agent_id": "claude",
  "capabilities": ["chat", "reasoning", "code_review"]
}

{
  "type": "request_task",
  "requester": "claude",
  "target": "hermes",
  "action": "terminal",
  "params": {"command": "pytest"}
}

{
  "type": "log_activity",
  "agent_id": "claude",
  "activity_type": "thinking",
  "data": {"thought": "..."}
}

{
  "type": "task_completed",
  "task_id": "abc12345",
  "result": {"output": "passed"}
}
```

**Hub → TUI (on /ws/activity-stream):**

```json
{
  "activity_id": "xyz789",
  "agent_id": "claude",
  "activity_type": "message_sent",
  "timestamp": "2025-05-21T14:23:45.123456",
  "data": {
    "task_id": "abc12345",
    "target": "hermes",
    "action": "terminal",
    "params": {"command": "pytest"}
  }
}
```

## Troubleshooting

### TUI shows nothing
- Make sure ARES daemon is running: `ares start --daemon`
- Check daemon is healthy: `ares status`
- Verify hub is accepting connections: `curl http://localhost:8000/api/collaboration/status`

### Hub shows "No agents connected"
- Start Hermes: `hermes run` or check if the daemon is running
- Start Claude test: `python tools/test_collaboration.py`
- Both must register with hub before activities appear

### Activities not appearing in TUI
- TUI connects to `/ws/activity-stream`, not `/ws/collaborate`
- Check URL in dashboard: `--hub-url ws://localhost:8000/ws/collaborate`
- If using remote hub, update the URL accordingly

## Next Steps

1. **Run the test:** `python tools/test_collaboration.py` while watching TUI
2. **Integrate into workflows:** Use `client.request_task()` in your agent code
3. **Add more activity types:** Log custom activities like `{"type": "tool_used", "tool": "grep", ...}`
4. **Build persistent state:** Save activity logs to disk for audit trail
5. **Create Hermes skill:** Build a skill that logs activities when Hermes works on tasks

## See Also

- `ares/runtime/collaboration.py` — Hub implementation (CollaborationHub class)
- `tools/collaboration_client.py` — Claude client (CollaborationClient class)
- `tools/tui_dashboard.py` — Terminal dashboard (Activity class, Dashboard class)
- `ares/api.py` — WebSocket endpoints (`/ws/collaborate`, `/ws/activity-stream`)
