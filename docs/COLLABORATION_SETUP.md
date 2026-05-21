# Claude + Hermes Collaboration Hub — Implementation Status

## ✅ What's Done (Claude's Side)

### 1. **ARES Collaboration Hub** (Backend)
**Location:** `ares/runtime/collaboration.py` + `ares/api.py`

- ✅ Central state management (`CollaborationSession`, `CollaborationHub`)
- ✅ WebSocket endpoint: `ws://localhost:8000/ws/collaborate`
- ✅ REST endpoints for coordination:
  - `POST /api/collaboration/session` — Create session
  - `GET /api/collaboration/session` — Get state
  - `POST /api/collaboration/request` — Request help
  - `POST /api/collaboration/complete` — Report completion
  - `WS /ws/collaborate` — Real-time bidirectional updates

### 2. **Claude Code Client** (Frontend)
**Location:** `~/.claude/collaboration_client.py`

- ✅ WebSocket listener (async/await)
- ✅ Methods:
  - `await init_collaboration(agent_name, goal)` — Start session
  - `await client.request_help(task, to_agent, context)` — Ask Hermes
  - `await client.report_completion(task_id, result)` — Report done
  - `client.on("task_request", handler)` — Handle incoming requests
  - `await client.disconnect()` — Clean shutdown

### 3. **Test Script**
**Location:** `~/.claude/test_collaboration.py`

```bash
python3 ~/.claude/test_collaboration.py
```

---

## 🔄 What Hermes Needs to Implement

### Hermes Collaboration Worker Skill

Create this file and register as a Hermes skill:

**`~/.hermes/skills/collaboration_worker.py`**

```python
import asyncio
import json
import websockets
import subprocess
from datetime import datetime

async def hermes_collaboration_worker():
    """
    Hermes listens for Claude's requests and responds.
    """
    hub_url = "ws://localhost:8000/ws/collaborate"
    
    async with websockets.connect(hub_url) as ws:
        print("✓ Hermes collaboration worker connected")
        
        # Tell hub that Hermes is online
        await ws.send(json.dumps({
            "agent": "hermes",
            "action": "heartbeat",
            "session_id": None  # Will be set by hub
        }))
        
        async for message in ws:
            data = json.loads(message)
            msg_type = data.get("type")
            session_id = data.get("session_id")
            
            # Check if Claude requested something
            if msg_type == "task_request":
                from_agent = data.get("from_agent")
                task_id = data.get("task_id")
                task = data.get("task")
                context = data.get("context", {})
                
                if from_agent == "claude":
                    print(f"\n📥 Claude requested: {task[:60]}...")
                    
                    # Execute the task
                    try:
                        result = await execute_task(task, context)
                        status = "success"
                    except Exception as e:
                        result = str(e)
                        status = "error"
                    
                    # Report back to hub
                    await ws.send(json.dumps({
                        "type": "task_completed",
                        "session_id": session_id,
                        "task_id": task_id,
                        "agent": "hermes",
                        "result": result
                    }))
                    print(f"✅ Reported to Claude")


async def execute_task(task: str, context: dict) -> str:
    """
    Execute what Claude asked.
    Implement task types here.
    """
    
    if "pytest" in task.lower() or "test" in task.lower():
        # Run tests
        test_dir = context.get("test_dir", "tests/")
        result = subprocess.run(
            ["pytest", test_dir, "-v", "--tb=short"],
            capture_output=True,
            text=True,
            timeout=60
        )
        return f"Tests: {result.stdout[-200:]}\nErrors: {result.stderr[-100:]}"
    
    elif "lint" in task.lower():
        # Run linter
        result = subprocess.run(
            ["ruff", "check", "."],
            capture_output=True,
            text=True
        )
        return result.stdout
    
    elif "deploy" in task.lower():
        # Simulate deployment
        return "Deployment process initiated..."
    
    else:
        # Generic task — just echo it
        return f"Hermes processed: {task}"


# To integrate with Hermes daemon:
# Add to ~/.hermes/config.yaml under `skills`:
#   - collaboration_worker
#
# Or run as a background skill:
#   hermes -p "run collaboration_worker"
```

---

## 📋 Integration Checklist for Hermes

- [ ] Create `collaboration_worker.py` in `~/.hermes/skills/`
- [ ] Install websockets: `pip install websockets` (in Hermes venv)
- [ ] Register skill in Hermes config or start it manually
- [ ] Test connection: 
  ```bash
  python3 ~/.claude/test_collaboration.py
  ```
- [ ] Verify bidirectional flow:
  1. Claude requests help
  2. Hermes receives request
  3. Hermes executes task
  4. Hermes reports completion
  5. Claude receives result

---

## 🧪 Testing Sequence

### Step 1: Start ARES backend
```bash
# Terminal 1
cd ~/GitHub/ARES-Autonomous-Reasoning-Execution-System
source .venv/bin/activate
ares start --daemon
```

### Step 2: Start Hermes collaboration worker
```bash
# Terminal 2 (as Hermes)
# Either add to ~/ .hermes/config.yaml and restart daemon
# Or run manually:
python3 ~/.hermes/skills/collaboration_worker.py
```

### Step 3: Run Claude test
```bash
# Terminal 3
python3 ~/.claude/test_collaboration.py
```

Expected output:
```
============================================================
CLAUDE CODE ↔ HERMES COLLABORATION TEST
============================================================

[1] Initializing collaboration session...
✓ Session created: session_1726234567

[2] Claude requesting help from Hermes...
✓ Task queued: a1b2c3d4

[2.5] Checking collaboration state...
Agents: ['claude', 'hermes']
Pending tasks: 1

[4] Waiting for Hermes to execute task (30 seconds timeout)...

✓ SUCCESS: Hermes completed task
   Result: Tests: PASSED 45/45...
```

---

## 🔧 Architecture (From User's Perspective)

```
Claude Code (Terminal/IDE)
    │
    ├─ await client.request_help("run tests")
    │   ↓
    └─→ POST /api/collaboration/request
        ↓
    ┌───────────────────────────────────┐
    │  ARES Collaboration Hub (Port 8000)│
    │  - Session state store             │
    │  - Task queue                      │
    │  - Real-time broadcaster           │
    └───────────────────────────────────┘
        ↓
    WS /ws/collaborate (bidirectional)
        ↓
    Hermes Daemon (24/7)
    ├─ Receives: "run tests"
    ├─ Executes: pytest
    ├─ Reports: "45 passed"
    │
    └─→ Sends completion back via WebSocket
        ↓
    Claude receives result
```

---

## 📊 Real-World Scenario

**User Goal:** "Test ARES, fix any failures, deploy"

```
Claude: "Hermes, run the test suite"
  ↓
Hermes: [running pytest...]
  ↓
Claude: [sees tests run in real-time]
  ↓
Hermes: [3 failures found]
  ↓
Claude: "Fix these issues..."
  ↓
Hermes: [running linter on Claude's fixes]
  ↓
Claude: [sees linter output, refines]
  ↓
Hermes: [re-running tests: all pass]
  ↓
Claude: "Deploy"
  ↓
Hermes: [initiates deployment]
  ↓
[History recorded: Claude coded, Hermes validated, both coordinated]
```

---

## 📝 Notes for Hermes

1. **Websockets dependency**: Make sure your venv has `websockets` installed
2. **Session IDs**: Will be passed by the hub, don't hardcode them
3. **Error handling**: Wrap task execution in try/except, report errors to Claude
4. **Heartbeat**: Optional but recommended — send periodic heartbeats to stay connected
5. **Task context**: Claude may pass context (file paths, config) — use it
6. **Logging**: Log all requests/completions for debugging

---

## 🎯 What This Achieves

- ✅ **Office-like experience**: Both agents see each other's work
- ✅ **Bidirectional**: Claude ↔ Hermes (not one-way delegation)
- ✅ **Real-time**: WebSocket updates (not polling)
- ✅ **Persistent**: Hermes daemon + history tracking
- ✅ **Natural**: Just ask, no API boilerplate
- ✅ **Observable**: Dashboard ready for next phase

Ready when you are! Let me know when Hermes skill is ready, and we'll test the full system.
