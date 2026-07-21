# ARES Observer Service

Autonomous task discovery for ARES. Watches your work, infers tasks, and creates Kanban items automatically.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Observer Service (this module)                             │
│  - Watches: git, terminal, files, sessions                  │
│  - Infers: Uses local LLM (qwen3.6:35b-mlx) or heuristics   │
│  - Creates: POSTs tasks to ARES Kanban API                  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  ARES Kanban Board                                          │
│  - Receives auto-generated tasks                            │
│  - Filters by confidence threshold                          │
│  - Queues for approval or auto-starts                       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  JaegerAI (Mind)                                            │
│  - Picks up tasks from Kanban                               │
│  - Plans execution via agent loop                           │
│  - Routes to workers (Hermes, Claude, etc.)                 │
└─────────────────────────────────────────────────────────────┘
```

## Installation

### 1. Create virtual environment

```bash
cd ~/GitHub/ARES/observer
python3 -m venv .venv
source .venv/bin/activate
pip install pyyaml requests ollama
```

### 2. Configure

Edit `config.yaml`:
- Set repo paths to watch
- Adjust confidence thresholds
- Configure local model (default: qwen3.6:35b-mlx)

### 3. Test run

```bash
python observer.py --run-once
```

Check logs at `~/.ares/observer/observer.log`

### 4. Install as daemon (macOS)

```bash
# Copy plist to LaunchAgents
cp com.ares.observer.plist ~/Library/LaunchAgents/

# Load and start
launchctl load ~/Library/LaunchAgents/com.ares.observer.plist

# Check status
launchctl list | grep ares
```

### 5. Verify

```bash
# Check logs
tail -f ~/.ares/observer/observer.log

# Check Kanban board
curl http://localhost:8787/api/kanban/tasks | python3 -m json.tool
```

## Configuration

### Confidence Thresholds

```yaml
confidence:
  auto_start: 0.85      # Tasks above this start immediately
  queue_for_approval: 0.60  # Tasks above this queue for approval
  # Below 0.60: shown as suggestions only
```

### Watch Intervals

```yaml
intervals:
  git: 300          # Check git every 5 minutes
  terminal: 120     # Check terminal history every 2 minutes
  files: 600        # Scan files every 10 minutes
  sessions: 300     # Check sessions every 5 minutes
```

### Watch Paths

```yaml
watch:
  repos:
    - ~/GitHub/ARES
    - ~/GitHub/JaegerAI
  terminal_log: ~/.ares/logs/terminal-history.log
  session_db: ~/.ares/journal.db
```

## Watchers

### GitWatcher
- Uncommitted changes
- Failing tests
- Merge conflicts
- Unpushed commits

### TerminalWatcher
- Incomplete work patterns (git stash, vim, etc.)
- Errors (pytest failed, build errors, tracebacks)
- Repeated commands (stuck points)

### FileWatcher
- TODO markers
- FIXME markers
- HACK, XXX, BUG, OPTIMIZE, etc.
- Only scans recently modified files

### SessionWatcher
- Incomplete session titles (WIP, draft, todo)
- Messages ending with questions
- Sessions with pending work

## Inference Engine

Two modes:

1. **LLM mode** (default): Uses local Ollama model to analyze observations and infer tasks
2. **Heuristic mode** (fallback): Rule-based inference if Ollama unavailable

Example LLM prompt:
```
You are an autonomous task discovery agent...
Analyze these observations and infer actionable tasks.

OBSERVATIONS:
- Git: uncommitted changes in ARES repo
- Terminal: pytest FAILED test_auth.py
- Files: FIXME in auth.py line 45
- Sessions: "WIP: auth refactor"

Return JSON array of tasks...
```

## Kanban Integration

Tasks are created via `POST /api/kanban/tasks`:

```json
{
  "title": "Fix failing tests",
  "priority": "high",
  "confidence": 0.85,
  "context": "Repo: ARES\nFailing: test_auth.py::test_login",
  "auto_generated": true,
  "generated_at": "2026-07-21T10:30:00"
}
```

## Troubleshooting

### Observer not creating tasks

1. Check logs: `tail -f ~/.ares/observer/observer.log`
2. Verify Kanban API is running: `curl http://localhost:8787/api/kanban`
3. Check confidence thresholds in config.yaml

### Ollama not available

The observer falls back to heuristic mode. Install Ollama for better inference:
```bash
brew install ollama
ollama pull qwen3.6:35b-mlx
```

### Daemon not starting

1. Check plist syntax: `plutil -lint ~/Library/LaunchAgents/com.ares.observer.plist`
2. Check logs: `tail -f ~/.ares/observer/observer.err`
3. Reload: `launchctl unload ~/Library/LaunchAgents/com.ares.observer.plist && launchctl load ...`

## Development

### Add new watcher

1. Create `watchers/my_watcher.py`
2. Implement `check_*()` method returning list of signals
3. Import in `watchers/__init__.py`
4. Add to `Observer.observe()`

### Test inference

```bash
python -c "
from observer import InferenceEngine
engine = InferenceEngine('qwen3.6:35b-mlx', 'http://localhost:11434')
tasks = engine.infer_tasks({'git': [...], 'terminal': [...]})
print(tasks)
"
```

## Security

- Observer runs locally, no external API calls except to local ARES
- Terminal history read-only
- Git operations are read-only (status, log, diff)
- File scanning respects permissions

## Performance

- Daemon sleeps 30s between checks
- File watcher only scans recently modified files
- LLM inference cached per run
- Typical memory usage: ~50MB
- CPU: <1% when idle, spikes during inference
