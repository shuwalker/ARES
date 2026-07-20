# ARES Orchestration Model

## Simple vs Complex Tasks

### Simple Tasks (single step)

```
User message → Classify intent → Pick worker → Send briefing → Get result → Verify → Respond
```

No plan needed. The SI handles this in one pass. Most conversations are simple tasks.

### Complex Tasks (multi-step)

```
User message → Create plan → Execute step 1 → Verify → Execute step 2 → Verify → ... → Complete
                                  │                                    │
                                  └──── If step fails: retry/branch/escalate ──┘
```

Plans are created when:
- The user's request implies multiple dependent steps
- The SI determines that verification after step 1 changes the approach for step 2
- The task requires handoffs between workers

## Plan Structure

```python
@dataclass
class Plan:
    plan_id: str
    goal: str                    # What the user wants accomplished
    status: str                  # "pending", "running", "paused", "completed", "failed"
    steps: list[Step]
    created_at: float
    updated_at: float
    conversation_id: str         # Link to the conversation where this was requested

@dataclass
class Step:
    step_id: str
    objective: str               # What this step accomplishes
    dependencies: list[str]     # step_ids that must complete first
    required_capabilities: list[str]  # What the worker must support
    assigned_worker: str | None  # Who will execute (None = SI decides)
    status: str                  # "pending", "running", "completed", "failed", "skipped"
    result: str | None           # What the step produced
    evaluation: str | None       # How the result was evaluated
    retry_count: int             # How many times this step was retried
    max_retries: int             # Default: 2
    requires_approval: bool      # If true, pause for user input before executing
```

## Orchestrator Behavior

### Sequential Tasks

```
Step 1 depends on nothing → execute → verify → 
Step 2 depends on Step 1 → execute → verify →
Step 3 depends on Step 2 → execute → verify → done
```

### Parallel Tasks

```
Step 1 depends on nothing ──┐
Step 2 depends on nothing ──┤→ execute all → verify all → merge results
Step 3 depends on nothing ──┘
```

### Retries

```
Step fails → 
  IF retry_count < max_retries:
    Revise briefing based on failure reason → retry with same or different worker
  ELSE:
    Mark step as failed → mark plan as failed → inform user
```

### Fallback Workers

```
Step assigned to worker "claude" → 
  IF claude is unavailable:
    Check worker registry for workers with same capabilities
    Route to best available fallback
    Log fallback in activity ledger
```

### Branching

```
Step 1 (research) returns 3 possible approaches → 
  Create branch plan:
    Branch A: implement approach 1
    Branch B: implement approach 2
  Execute both branches in parallel →
  Evaluate results → pick best → continue plan
```

### Cancellation

```
User cancels → Mark plan as "cancelled" → Cancel running steps → Clean up
```

### Resumability

All plan state is persisted in the Journal (SQLite). If the app restarts:
1. Load all plans with status "running" or "paused"
2. Check each step: is the assigned worker still available?
3. Resume from the first incomplete step
4. Re-verify completed steps if needed

### Approval Gates

```python
if step.requires_approval:
    # Pause plan
    plan.status = "paused"
    # Present to user: what will happen, what data will be shared, with which worker
    # Wait for approval or modification
    # If approved: continue
    # If denied: mark step as skipped, adjust plan
```

## Storage

```sql
CREATE TABLE plans (
    plan_id TEXT PRIMARY KEY,
    goal TEXT,
    status TEXT,  -- pending, running, paused, completed, failed, cancelled
    conversation_id TEXT,
    created_at REAL,
    updated_at REAL,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE TABLE steps (
    step_id TEXT PRIMARY KEY,
    plan_id TEXT,
    objective TEXT,
    dependencies TEXT,  -- JSON array of step_ids
    required_capabilities TEXT,  -- JSON array of capability strings
    assigned_worker TEXT,
    status TEXT,  -- pending, running, completed, failed, skipped
    result TEXT,
    evaluation TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 2,
    requires_approval INTEGER DEFAULT 0,
    FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
);
```

## Current State

- `delegation_runner.py` and `delegation_tasks.py` exist for background task delegation
- No plan model, no step tracking, no dependency graph
- No state persistence across restarts for running tasks
- No branching, retry, or resumability