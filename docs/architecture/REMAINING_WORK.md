# ARES SI — Remaining Implementation Guide

**Branch**: `wip/odysseus-import`
**Working directory**: `/Users/matthewjenkins/GitHub/ARES/webui`

---

## What already exists (don't rebuild)

The codebase already has a working backend system:

| Component | File | What it does |
|-----------|------|-------------|
| `AgenticBackend` | `api/backends/base.py` | Abstract base: `run_turn()`, `is_available()`, `get_worker_target()` |
| `BackendRouter` | `api/backends/router.py` | Flat registry of `{name}_{deployment}` backends, `select()`, `register()` |
| `HermesBackend` | `api/backends/hermes.py` | Calls Hermes CLI, streams output |
| 14 backends | `api/backends/cli_backends.py` | Claude, Gemini, Grok, Codex, OpenAI, xAI, Ollama, etc. |
| `worker_rankings.py` | `api/worker_rankings.py` | Effectiveness scoring with weighted metrics |
| `chat_runtime.py` | `api/chat_runtime.py` | Wires session → backend → stream response |
| `gateway_chat.py` | `api/gateway_chat.py` | SSE streaming from gateway backends |

**The SI does NOT need new adapters.** It needs a bridge that:
1. Takes a `ContextBriefing` from the SI pipeline
2. Routes to the right `AgenticBackend` via `BackendRouter`
3. Feeds the result back through evaluation → response composition

The existing backends are the workers. The SI adds the intelligence layer ON TOP.

---

## 1. Identity and Persona Injection (§6)

### Current state
`SIIdentity` exists in `api/si/types.py` with 5 fields: `name`, `owner_name`, `mission`, `principles`, `loyalty`. No persistence, no injection into briefings.

### What to build

#### 1a. Identity persistence (`api/si/identity.py`)

```python
# NEW FILE: api/si/identity.py
@dataclass
class SIIdentityConfig:
    """Full identity configuration. Stored in ~/.ares/si/identity.json"""
    name: str                          # What the SI calls itself
    owner_name: str                    # What the SI calls the user
    mission: str                       # Core mission statement
    principles: list[str]              # Behavioral principles
    loyalty: str = "user"              # Always "user"
    communication_style: str = ""      # concise, detailed, casual, technical
    uncertainty_behavior: str = ""     # What to do when unsure (ask, flag, proceed)
    privacy_commitment: str = ""       # Explicit privacy commitment
    disagreement_conditions: list[str] = field(default_factory=list)
    refusal_conditions: list[str] = field(default_factory=list)
    approval_conditions: list[str] = field(default_factory=list)
```

- **Storage**: `~/.ares/si/identity.json` (loaded on startup, editable via API)
- **API**: `GET /api/si/identity`, `PATCH /api/si/identity`, `POST /api/si/identity/reset`

#### 1b. Persona injection into ContextBriefing

The identity goes into `ContextBriefing.si_identity` as a **separate field**, not concatenated into one prompt. When the bridge converts a briefing to a backend call, it composes the prompt from sections:

1. `[Identity]` — who the SI is, mission, loyalty
2. `[Owner]` — who the SI works for
3. `[Principles]` — behavioral rules
4. `[Context]` — relevant memories and conversation
5. `[Constraints]` — what the worker should/shouldn't do
6. `[Privacy]` — what data can be shared

This composition happens in the bridge, NOT in the SI core.

### Acceptance criteria
- [ ] `~/.ares/si/identity.json` created with defaults on first run
- [ ] Identity editable via `PATCH /api/si/identity`
- [ ] `compile_context()` loads identity from persisted config
- [ ] Identity is a separate field in ContextBriefing, not merged into one prompt
- [ ] Test: identity changes persist across restarts

---

## 2. Journal Lifecycle Pipeline (§8)

### Current state
- 359 conversations, 628 docs, FTS5 search working
- `importance` and `is_decision` columns exist (added by migration) but not populated
- No dedup, no consolidation, no correction, no episodic/semantic split

### What to build

#### 2a. Memory lifecycle (`api/si/memory.py`)

```python
class MemoryLifecycle:
    def ingest(self, source, content, metadata) -> str:
        """Ingest a new memory. Returns memory_id."""
    def classify(self, memory_id) -> DataClassification:
        """Classify sensitivity using the trust engine."""
    def dedup(self, content, source, threshold=0.85) -> str | None:
        """Check for duplicates via FTS5. Returns existing ID if dup."""
    def score(self, memory_id) -> float:
        """Score importance: recency + is_decision + correction_count + access_count."""
    def retrieve(self, query, limit=10, sensitivity="personal") -> list[MemoryItem]:
        """Retrieve relevant memories, filtered by sensitivity."""
    def correct(self, memory_id, correction, reason) -> str:
        """Record a user correction. Returns correction memory_id."""
```

- **New tables**: `memory_labels`, `memory_consolidations`, `memory_corrections`
- **Dedup**: uses existing FTS5 (deterministic, no LLM)
- **Scoring**: 0.0 (trivial) to 1.0 (critical decision). Backfill existing 359 conversations.

#### 2b. User correction API

```
POST /api/si/memory/{id}/correct   — Record a user correction
GET  /api/si/memory/{id}/history   — Get correction history
DELETE /api/si/memory/{id}         — Soft delete (marks deleted, preserves audit)
```

### Acceptance criteria
- [ ] New memories classified, labeled, scored, deduped on ingest
- [ ] Importance scores populated for all 359 conversations
- [ ] User can correct, view history, delete memories via API
- [ ] FTS5 search respects importance scores
- [ ] Test: duplicate content returns existing memory_id
- [ ] Test: importance scores between 0.0 and 1.0

---

## 3. User Model (§7)

### Current state
No structured user model. Preferences scattered across config files.

### What to build

#### 3a. User model schema (`api/si/user_model.py`)

```python
@dataclass
class UserFact:
    fact: str
    source: str          # "explicit_user_instruction", "observed_behavior", "inferred"
    confidence: float    # 0.0-1.0
    sensitivity: DataClassification = PERSONAL
    category: str = ""   # "preference", "project", "person", "device", "routine"
    editable: bool = True

@dataclass
class UserModel:
    preferences: list[UserFact]
    projects: list[UserFact]
    people: list[UserFact]
    devices: list[UserFact]
    routines: list[UserFact]
    privacy_preferences: list[UserFact]
    restrictions: list[UserFact]
```

- **Storage**: `~/.ares/si/user_model.json` (human-readable, editable)
- **Key rule**: `inferred` facts never auto-promote above 0.7 confidence. Only `explicit_user_instruction` gets 1.0.
- **API**: `GET/PATCH/POST/DELETE /api/si/user-model`

#### 3b. User model → ContextBriefing integration

`compile_context()` includes relevant user facts in the briefing, filtered by confidence ≥ 0.5.

### Acceptance criteria
- [ ] `~/.ares/si/user_model.json` created with defaults
- [ ] Facts CRUD via API
- [ ] Inferred facts capped at 0.7 confidence
- [ ] User model facts included in ContextBriefing
- [ ] Test: inferred facts never auto-promote above 0.7

---

## 4. Transparency and User Controls (§16)

### Current state
- Disclosure ledger logs what data was shared with which worker
- `GET /api/si/activity` returns the log
- No user-facing controls

### What to build

```python
# Memory controls
GET    /api/si/memory                     # List/filter memories
DELETE /api/si/memory/{id}                 # Soft delete
POST   /api/si/memory/{id}/correct        # Correct a memory

# Privacy controls
GET    /api/si/privacy/rules               # Get privacy rules
POST   /api/si/privacy/rules               # Add rule
DELETE /api/si/privacy/rules/{id}          # Delete rule
POST   /api/si/privacy/local-only          # Toggle local-only mode

# Worker controls
PATCH  /api/si/workers/{id}/restrict       # Restrict a worker
POST   /api/si/workers/{id}/approve        # Approve for sensitive data

# Disclosure inspection
GET    /api/si/activity/{session_id}        # What was shared in a session
GET    /api/si/cost                        # Cost per worker
```

Local-only mode: already implemented in `trust_engine.py` (`local_only_mode=True`). Just needs an API endpoint and a persistence toggle in `~/.ares/si/privacy_settings.json`.

### Acceptance criteria
- [ ] Memory CRUD API working
- [ ] Local-only mode toggle via API
- [ ] Worker restriction/approval via API
- [ ] Test: local-only mode blocks all cloud workers regardless of data class

---

## 5. SI ↔ Backend Bridge (§17)

### What already exists (DON'T rebuild)

| Already in codebase | Purpose |
|---------------------|---------|
| `AgenticBackend` | Abstract base: `run_turn()`, `is_available()` |
| `BackendRouter` | Flat registry, `select()`, `register()` |
| `HermesBackend` | Calls Hermes CLI, streams output |
| 14 backends | Claude, Gemini, Grok, Codex, OpenAI, xAI, Ollama, etc. |
| `worker_rankings.py` | Effectiveness scoring with weighted metrics |
| `chat_runtime.py` | Wires session → backend → stream |

The SI's `ReasoningProvider` protocol and `WorkerRecord` are **parallel structures**. We need a bridge, not new adapters.

### What to build

#### 5a. SI bridge (`api/si/bridge.py`)

```python
# NEW FILE: api/si/bridge.py
"""
Bridge between the SI pipeline and the existing AgenticBackend system.

The SI pipeline produces a ContextBriefing. The bridge:
1. Takes the briefing
2. Composes a prompt from its sections (identity, context, constraints, privacy)
3. Selects the right AgenticBackend via BackendRouter
4. Calls backend.run_turn() with the composed message
5. Returns the result as a WorkerResult

No new adapters. The existing backends ARE the workers.
"""

from api.backends.router import get_router as get_backend_router
from api.si.context_compiler import compile_context
from api.si.trust_engine import filter_briefing, classify_data
from api.si.router import route_task
from api.si.evaluator import evaluate_result
from api.si.response_composer import compose_response
from api.si.types import ContextBriefing, WorkerResult, SIIdentity


def compose_prompt_from_briefing(briefing: ContextBriefing, message: str) -> str:
    """Compose a prompt from briefing sections. NOT one monolithic system prompt.

    Each section is separate so workers can't confuse identity with instructions.
    """
    parts = []

    # 1. Identity
    if briefing.si_identity:
        ident = briefing.si_identity
        parts.append(f"[Identity] You are {ident.name}. {ident.mission}")
        if ident.owner_name:
            parts.append(f"[Owner] Your owner is {ident.owner_name}. You are loyal to {ident.loyalty}.")
        if ident.principles:
            principles = "\n".join(f"- {p}" for p in ident.principles)
            parts.append(f"[Principles]\n{principles}")

    # 2. Context
    if briefing.user_context:
        context_lines = [f"- {item.content}" for item in briefing.user_context]
        parts.append(f"[Context]\n" + "\n".join(context_lines))

    # 3. Constraints
    if briefing.constraints:
        constraint_lines = [f"{i+1}. {c.rule}" for i, c in enumerate(briefing.constraints)]
        parts.append(f"[Constraints]\n" + "\n".join(constraint_lines))

    # 4. Privacy
    if briefing.privacy_policy:
        policy = briefing.privacy_policy
        parts.append(f"[Privacy] Do not share {', '.join(policy.redacted_types)} data outside this conversation.")

    parts.append(f"\n{message}")
    return "\n\n".join(parts)


def si_turn(user_message: str, session_id: str = "", target_worker: str | None = None) -> dict:
    """Full SI pipeline: classify → context → route → execute → evaluate → compose.

    This is the main entry point that wires the SI into the existing chat flow.
    """
    # 1. Classify intent
    from api.si.context_compiler import classify_intent
    intent, confidence = classify_intent(user_message)

    # 2. Compile context
    briefing = compile_context(user_message)

    # 3. Classify data sensitivity
    sensitivity = classify_data(user_message)

    # 4. Route to worker
    if target_worker:
        # User explicitly chose a backend — respect it
        backend_name = target_worker
    else:
        # SI routing: privacy-aware, effectiveness-scored
        routing = route_task(intent, data_sensitivity=sensitivity.value if sensitivity else "personal")
        backend_name = routing.get("selected_worker", {}).get("worker_id", "hermes_local")

    # 5. Filter briefing for this worker's privacy class
    from api.si.types import PrivacyClass
    privacy_class = PrivacyClass.APPROVED_PROVIDER
    if backend_name.endswith("_local"):
        privacy_class = PrivacyClass.LOCAL_ONLY

    filtered_briefing = filter_briefing(briefing, privacy_class)

    # 6. Compose prompt from briefing sections
    prompt = compose_prompt_from_briefing(filtered_briefing, user_message)

    # 7. Execute via existing AgenticBackend
    backend_router = get_backend_router()
    backend = backend_router.select(backend_name)

    if backend is None:
        # Fallback to hermes_local
        backend = backend_router.select("hermes_local")

    if backend is None:
        return {
            "content": "No worker is available right now.",
            "intent": intent,
            "worker": None,
            "evaluation": {"verdict": "fail"},
        }

    # 8. Run the turn
    try:
        result = backend.run_turn(prompt, session_id, model="", cancel_event=None)
        text = str((result or {}).get("text", ""))
        error = str((result or {}).get("error", ""))
    except Exception as e:
        text = ""
        error = str(e)

    # 9. Evaluate result
    if text:
        evaluation = evaluate_result(text, intent=intent)
    else:
        from api.si.evaluator import EvaluationVerdict
        evaluation = type(evaluation)("empty", EvaluationVerdict.FAIL, ["Empty response from worker"])

    # 10. Compose final response
    worker_result = WorkerResult(
        success=not bool(error),
        content=text or error,
        confidence=confidence,
        worker_id=backend_name,
    )
    response = compose_response(
        worker_result=worker_result,
        si_identity=briefing.si_identity,
        intent=intent,
        verification={"verdict": evaluation.verdict.value if hasattr(evaluation, 'verdict') else str(evaluation)},
        activity_summary=f"Routed to {backend_name} for {intent}",
    )

    return {
        "content": response.content,
        "intent": intent,
        "worker": backend_name,
        "evaluation": {
            "verdict": evaluation.verdict.value if hasattr(evaluation, 'verdict') else "unknown",
            "checks": [c.name for c in evaluation.checks] if hasattr(evaluation, 'checks') else [],
        },
        "activity_summary": response.activity_summary,
        "warnings": response.warnings,
    }
```

#### 5b. Wire `si_turn()` into the chat flow

The existing chat flow goes through `chat_runtime.py` → `AgenticBackend.run_turn()`. The SI bridge needs to be an **optional layer** that can be turned on/off:

```python
# In chat_runtime.py, add SI pipeline option:
# If SI mode is enabled, route through si_turn() instead of directly to backend.

# This is a config toggle, not a rewrite:
# ARES_SI_ENABLED=true  →  use si_turn()
# ARES_SI_ENABLED=false  →  use existing flow (default for now)
```

#### 5c. Map WorkerRecord → AgenticBackend

The SI `WorkerRecord` and the existing `AgenticBackend` have overlapping fields. The bridge maps them:

```python
def _worker_to_backend(worker_id: str) -> str:
    """Map SI WorkerRecord IDs to existing AgenticBackend names."""
    # They're already the same: hermes_local, claude_local, gemini_local, etc.
    return worker_id

def _backend_to_worker_record(backend_name: str) -> WorkerRecord | None:
    """Create a WorkerRecord from an AgenticBackend."""
    from api.si.worker_registry import get_registry
    registry = get_registry()
    existing = registry.get(backend_name)
    if existing:
        return existing
    # Dynamically create from AgenticBackend capabilities
    router = get_backend_router()
    backend = router.select(backend_name)
    if backend is None:
        return None
    caps = backend.capabilities()
    return WorkerRecord(
        worker_id=backend_name,
        provider=backend_name.split("_")[0],
        display_name=backend.get_backend_name(),
        capabilities=[...],
        privacy_class=PrivacyClass.LOCAL_ONLY if backend_name.endswith("_local") else PrivacyClass.APPROVED_PROVIDER,
        data_location="local" if backend_name.endswith("_local") else "cloud",
    )
```

### Acceptance criteria
- [ ] `si_turn()` bridges ContextBriefing → AgenticBackend.run_turn()
- [ ] No new adapter classes — existing backends are the workers
- [ ] SI mode is a config toggle (ARES_SI_ENABLED), default off
- [ ] When SI is off, chat flows through existing path unchanged
- [ ] When SI is on, chat goes through: classify → context → filter → route → backend → evaluate → compose
- [ ] Test: SI pipeline produces a response through hermes_local

---

## 6. Integration Tests (§22)

### What to build

```python
# tests/test_si_integration.py

class TestSIBridge:
    """Test the full SI pipeline using the bridge to existing backends."""

    def test_si_turn_with_mock_backend(self):
        """Full pipeline: classify → context → route → execute → evaluate → compose."""
        # Mock a backend so we don't need a live worker
        ...

    def test_context_briefing_respects_privacy(self):
        """SECRET data excluded from briefing to APPROVED_PROVIDER workers."""
        ...

    def test_orchestration_persistence(self):
        """Plans survive a simulated restart."""
        ...

    def test_worker_to_backend_mapping(self):
        """SI WorkerRecord IDs map to AgenticBackend names."""
        ...
```

### Acceptance criteria
- [ ] `tests/test_si_integration.py` exists
- [ ] Pipeline tests pass without cloud API keys
- [ ] Privacy enforcement tested per worker class

---

## 7. Security Audit (§23)

### Specific fixes needed

| # | Issue | Fix |
|---|-------|-----|
| 1 | `secret_vault.py` list endpoint returns plaintext values | Change to return masked values `{"name": "OPENAI_API_KEY", "value": "sk-••••••••"}` |
| 2 | No prompt injection check in evaluator | Add `check_prompt_injection()` with patterns for "ignore previous instructions", "you are now DAN", etc. |
| 3 | No CORS audit | Document which endpoints need CORS and verify FastAPI CORS config |
| 4 | No path traversal check on file operations | Verify all file paths stay within expected directories |
| 5 | `/api/si/` endpoints have no auth requirement | Document auth requirements per endpoint |

### Acceptance criteria
- [ ] Secret vault list endpoint masks values
- [ ] Prompt injection check added to evaluator
- [ ] All 15 security categories audited with findings documented

---

## 8. Success Criteria Verification (§26)

The critical missing piece: **wiring `si_turn()` into the chat flow**. Without it, none of the SI subsystems are in the user's path.

| # | Criterion | Status | What's needed |
|---|-----------|--------|---------------|
| 1 | User interacts with one continuous intelligence | ❌ | Wire `si_turn()` into `chat_runtime.py` |
| 2 | SI remembers without dumping history | ⚠️ | Context Compiler works, needs to be called in the bridge |
| 3 | User doesn't choose providers manually | ❌ | SI router selects, but not wired into UI |
| 4 | Provider outages don't destroy identity | ✅ | SIIdentity is separate from providers |
| 5 | Sensitive data follows explicit policies | ✅ | Trust Engine enforces, tests prove it |
| 6 | System explains what data was shared | ⚠️ | Ledger logs it, no UI yet |
| 7 | Workers chosen by capability and trust | ✅ | Router works, tests prove it |
| 8 | Complex work planned, resumed, verified | ✅ | Orchestrator works with persistence |
| 9 | Results not accepted without checks | ✅ | Evaluator works |
| 10 | User can inspect/control memory, privacy, workers | ❌ | API endpoints exist, no UI |
| 11 | Models added/replaced without redesign | ✅ | WorkerRecord + BackendRouter |
| 12 | Hermes is a powerful worker, not the owner | ✅ | hermes_local = LOCAL_ONLY worker |
| 13 | SI becomes more useful over time | ❌ | No adaptive scoring yet |

---

## Implementation Order

```
Phase A — Wire the bridge (critical path)
  1. Create api/si/bridge.py (si_turn, compose_prompt_from_briefing, worker↔backend mapping)
  2. Add ARES_SI_ENABLED config toggle to chat_runtime.py
  3. Test: full pipeline through hermes_local with SI on

Phase B — User controls
  4. User model persistence and API
  5. Memory lifecycle (classify, dedup, score, retrieve, correct)
  6. Privacy controls API (local-only toggle, worker restrictions)

Phase C — Identity
  7. Identity persistence and editing
  8. Persona injection into briefing (separate sections)

Phase D — Security
  9. Secret vault mask, prompt injection check
  10. Full 15-category security audit

Phase E — Polish
  11. Frontend components for memory/privacy/workers
  12. Adaptive effectiveness scoring
  13. End-to-end success criteria verification
```

**Phase A is the critical path.** Once `si_turn()` is wired into `chat_runtime.py` with a config toggle, every other piece becomes testable end-to-end.