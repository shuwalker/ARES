# ARES SI — Remaining Implementation Guide

**Status**: The skeleton, contracts, and deterministic core are built and tested (71 tests, 14 ad-hoc checks). This document covers everything still needed to reach 100% of the directive.

**Branch**: `wip/odysseus-import`
**Working directory**: `/Users/matthewjenkins/GitHub/ARES/webui`

---

## 1. Identity and Persona Injection (§6)

### Current state
`SIIdentity` exists in `api/si/types.py` with 5 fields: `name`, `owner_name`, `mission`, `principles`, `loyalty`. It's a frozen dataclass with no persistence and no injection into worker prompts.

### What needs to be built

#### 1a. Identity persistence (`api/si/identity.py`)

```python
# NEW FILE: api/si/identity.py
"""
SI Identity — persistent, editable identity for the Companion.

The identity is NOT a system prompt. It's structured data that gets
composed into different sections of the worker briefing depending
on what the worker needs to know.
"""

@dataclass
class SIIdentityConfig:
    """Full identity configuration, stored in ~/.ares/si/identity.json"""
    name: str                          # What the SI calls itself
    owner_name: str                    # What the SI calls the user
    mission: str                       # Core mission statement
    principles: list[str]              # Behavioral principles
    loyalty: str = "user"              # Always "user" — the SI works for the owner
    communication_style: str = ""      # concise, detailed, casual, technical
    uncertainty_behavior: str = ""     # What to do when unsure (ask, flag, proceed)
    privacy_commitment: str = ""       # Explicit privacy commitment
    disagreement_conditions: list[str] = field(default_factory=list)  # When to disagree
    refusal_conditions: list[str] = field(default_factory=list)       # When to refuse
    approval_conditions: list[str] = field(default_factory=list)     # When to ask first
```

- **File**: `api/si/identity.py`
- **Storage**: `~/.ares/si/identity.json` (loaded on startup, editable via API)
- **API endpoints**:
  - `GET /api/si/identity` — return current identity
  - `PATCH /api/si/identity` — update individual fields
  - `POST /api/si/identity/reset` — reset to defaults

#### 1b. Persona injection into ContextBriefing (`api/si/context_compiler.py`)

Currently `compile_context()` accepts a `SIIdentity` but the default is minimal:

```python
# CURRENT (minimal):
si_identity = SIIdentity(name="Assistant", owner_name="User")

# TARGET (loaded from persisted config):
from api.si.identity import load_identity
si_config = load_identity()  # from ~/.ares/si/identity.json
si_identity = SIIdentity(
    name=si_config.name,
    owner_name=si_config.owner_name,
    mission=si_config.mission,
    principles=si_config.principles,
    loyalty=si_config.loyalty,
)
```

The identity gets injected into `ContextBriefing.si_identity`, which workers receive. But it must NOT be mixed into one uncontrolled system prompt. The briefing separates:

1. `si_identity` — who the SI is
2. `user_context` — what the SI knows about the user
3. `relevant_memories` — relevant history
4. `constraints` — what the worker should/shouldn't do
5. `privacy_policy` — what data can be shared

Each section is a separate field in `ContextBriefing`, not concatenated.

#### 1c. Adapter-side composition

When a worker adapter (e.g., Hermes, Claude) converts a `ContextBriefing` into its native format, it should compose the prompt from these sections in order:

```
[Identity] You are {si_identity.name}. {si_identity.mission}
[Owner] Your owner is {si_identity.owner_name}. You are loyal to {si_identity.loyalty}.
[Principles] {principles joined as bullet points}
[Context] {relevant memories and conversation}
[Constraints] {constraints as numbered rules}
[Privacy] Do not share {privacy_policy.redacted_types} data outside this conversation.
```

This composition happens in each adapter's `generate()` method, NOT in the SI core.

### Acceptance criteria
- [ ] `~/.ares/si/identity.json` is created with sensible defaults on first run
- [ ] Identity is editable via `PATCH /api/si/identity`
- [ ] `compile_context()` loads identity from persisted config
- [ ] No single monolithic system prompt — identity, context, constraints, and privacy are separate briefing sections
- [ ] Test: identity changes persist across app restarts

---

## 2. Journal Lifecycle Pipeline (§8)

### Current state
- 359 conversations, 628 docs, FTS5 search working
- `importance` column exists in schema (added by migration) but not populated
- `is_decision` column exists but not populated
- No dedup, no consolidation, no correction, no episodic/semantic split

### What needs to be built

#### 2a. Memory lifecycle (`api/si/memory.py`)

```python
# NEW FILE: api/si/memory.py

class MemoryLifecycle:
    """
    Ingest → Classify → Label → Dedup → Score → Store → Consolidate → Retrieve → Correct

    Each stage is a separate function that can be called independently.
    """

    def ingest(self, source: str, content: str, metadata: dict) -> str:
        """Ingest a new memory. Returns memory_id."""

    def classify(self, memory_id: str) -> DataClassification:
        """Classify sensitivity using the trust engine."""

    def label(self, memory_id: str, labels: list[str]) -> None:
        """Add semantic labels (project, topic, entity)."""

    def dedup(self, memory_id: str) -> str | None:
        """Check for duplicates. Returns existing memory_id if duplicate, None if new."""

    def score(self, memory_id: str) -> float:
        """Score importance (0-1) based on recency, frequency, decision weight."""

    def consolidate(self, memory_ids: list[str]) -> str:
        """Consolidate multiple memories into a summary. Returns summary memory_id."""

    def retrieve(self, query: str, limit: int = 10, sensitivity: str = "personal") -> list[MemoryItem]:
        """Retrieve relevant memories, filtered by sensitivity."""

    def correct(self, memory_id: str, correction: str, reason: str) -> str:
        """Record a user correction. Returns correction memory_id."""
```

- **Storage**: SQLite tables in `~/.ares/journal/journal.db`
- **New tables needed**:
  - `memory_labels` (memory_id, label, source, created_at)
  - `memory_consolidations` (summary_id, source_ids_json, created_at)
  - `memory_corrections` (original_id, correction_id, reason, created_at)

#### 2b. Importance scoring

The `importance` column was added by the migration but never populated. Need:

```python
def score_importance(memory_id: str) -> float:
    """Score importance based on:
    - Recency (newer = more important)
    - Is it a decision? (decisions = more important)
    - Was it corrected by the user? (corrections = very important)
    - How often is it retrieved? (frequently accessed = more important)
    - Source type (conversation > document)
    """
```

Score range: 0.0 (trivial) to 1.0 (critical decision).

Run a one-time backfill: `UPDATE conversations SET importance = 0.3 WHERE importance IS NULL` then score each memory on next access.

#### 2c. Deduplication

```python
def dedup(content: str, source: str, threshold: float = 0.85) -> str | None:
    """Check if this content is a near-duplicate of an existing memory.

    Uses FTS5 search with content as query. If the top result
    has similarity above threshold, return its memory_id.
    """
```

This is deterministic — no LLM needed. FTS5 handles fuzzy matching.

#### 2d. User correction API

```python
# NEW ENDPOINTS in si.py:
@router.post("/memory/{memory_id}/correct")
def si_correct_memory(memory_id: str, correction: str, reason: str):
    """Record a user correction to a memory."""

@router.get("/memory/{memory_id}/history")
def si_memory_history(memory_id: str):
    """Get the full correction history for a memory."""

@router.delete("/memory/{memory_id}")
def si_delete_memory(memory_id: str):
    """Delete a memory (soft delete — marks as deleted, preserves audit trail)."""
```

### Acceptance criteria
- [ ] New memories are classified, labeled, scored, and deduped on ingest
- [ ] Importance scores are populated for all 359 conversations
- [ ] User can correct, view history of, and delete memories via API
- [ ] FTS5 search respects importance scores (higher importance = higher rank)
- [ ] Test: duplicate content returns existing memory_id instead of creating a new one
- [ ] Test: importance scoring produces values between 0.0 and 1.0

---

## 3. User Model (§7)

### Current state
No structured user model exists. User preferences are scattered across config files.

### What needs to be built

#### 3a. User model schema (`api/si/user_model.py`)

```python
# NEW FILE: api/si/user_model.py

@dataclass
class UserFact:
    """A single fact about the user, with provenance and confidence."""
    fact: str
    source: str          # "explicit_user_instruction", "observed_behavior", "inferred"
    confidence: float    # 0.0-1.0
    created_at: float
    last_confirmed_at: float | None
    sensitivity: DataClassification = PERSONAL
    editable: bool = True
    category: str = ""   # "preference", "project", "person", "device", "routine"


@dataclass
class UserModel:
    """Structured, editable model of the user."""
    preferences: list[UserFact]       # communication style, providers, formats
    projects: list[UserFact]          # active projects, repos, goals
    people: list[UserFact]            # people they mention, relationships
    devices: list[UserFact]           # devices, accounts, services
    routines: list[UserFact]          # daily patterns, habits
    privacy_preferences: list[UserFact]  # what to keep local, what to share
    restrictions: list[UserFact]      # provider restrictions, cost limits
```

- **Storage**: `~/.ares/si/user_model.json` (editable, human-readable)
- **Key rule**: No model-generated assumptions become permanent facts. Only `explicit_user_instruction` facts get `confidence=1.0`. `observed_behavior` starts at `0.5`. `inferred` starts at `0.3` and must never auto-promote above `0.7`.

#### 3b. User model API

```python
# ENDPOINTS:
GET    /api/si/user-model          # Get all facts
GET    /api/si/user-model/{category}  # Get facts by category
POST   /api/si/user-model          # Add a fact
PATCH  /api/si/user-model/{fact_id}   # Update a fact
DELETE /api/si/user-model/{fact_id}   # Delete a fact
POST   /api/si/user-model/{fact_id}/confirm  # Confirm a fact (bumps confidence)
```

#### 3c. User model → ContextBriefing integration

The Context Compiler should include relevant user facts in the briefing:

```python
# In context_compiler.py, compile_context():
from api.si.user_model import load_user_model

user_model = load_user_model()
user_context = [
    ContextItem(
        source="user_model",
        source_id=fact.id,
        content=f"{fact.category}: {fact.fact}",
        sensitivity=fact.sensitivity,
        relevance=fact.confidence,
        is_decision=fact.source == "explicit_user_instruction",
    )
    for fact in user_model.preferences + user_model.projects + user_model.privacy_preferences
    if fact.confidence >= 0.5  # Only include reasonably confident facts
]
briefing.user_context = user_context
```

### Acceptance criteria
- [ ] `~/.ares/si/user_model.json` is created with empty defaults on first run
- [ ] Facts can be added, updated, deleted, and confirmed via API
- [ ] `confidence` cannot exceed 0.7 for `inferred` facts
- [ ] `confidence` is 1.0 only for `explicit_user_instruction` facts
- [ ] User model facts are included in ContextBriefing
- [ ] Test: inferred facts never auto-promote above 0.7

---

## 4. Transparency and User Controls (§16)

### Current state
- Disclosure ledger logs what data was shared with which worker
- `GET /api/si/activity` returns the disclosure log
- No UI controls to inspect, correct, restrict, or delete

### What needs to be built

#### 4a. User control API endpoints

```python
# NEW ENDPOINTS in si.py:

# Memory controls
GET    /api/si/memory                           # List memories with filtering
GET    /api/si/memory/{memory_id}               # Get specific memory
DELETE /api/si/memory/{memory_id}               # Delete a memory (soft delete)
POST   /api/si/memory/{memory_id}/correct       # Correct a memory

# Privacy controls
GET    /api/si/privacy/rules                    # Get all privacy rules
POST   /api/si/privacy/rules                    # Add a privacy rule
DELETE /api/si/privacy/rules/{rule_id}          # Delete a privacy rule
POST   /api/si/privacy/local-only               # Enable/disable local-only mode

# Worker controls
GET    /api/si/workers                           # List all workers
PATCH  /api/si/workers/{worker_id}/restrict      # Restrict a worker
POST   /api/si/workers/{worker_id}/approve       # Approve a worker for sensitive data

# Disclosure inspection
GET    /api/si/activity                           # Disclosure log (exists)
GET    /api/si/activity/{session_id}              # What was shared in a session
GET    /api/si/cost                               # Cost tracking per worker
```

#### 4b. Local-only mode

When the user enables local-only mode, ALL data above PUBLIC goes to LOCAL_ONLY workers only:

```python
# Already implemented in trust_engine.py filter_briefing():
# local_only_mode=True forces all data above PUBLIC to local-only workers

# Need API endpoint:
@router.post("/api/si/privacy/local-only")
def si_set_local_only(enabled: bool):
    """Toggle local-only mode. When enabled, no data leaves the device."""
```

Store preference in `~/.ares/si/privacy_settings.json`.

#### 4c. Frontend components (WebUI)

These are React components that need to be added to the existing WebUI:

1. **MemoryInspector** — Browse, search, edit, delete memories
2. **DisclosureLog** — Show what data was shared with which worker and why
3. **WorkerPermissions** — List workers, toggle restrictions, approve for sensitive data
4. **PrivacySettings** — Toggle local-only mode, set data classification overrides

File locations: `webui/frontend/src/components/si/`

### Acceptance criteria
- [ ] `GET /api/si/activity` returns disclosure entries with worker, data class, and reason
- [ ] `DELETE /api/si/memory/{id}` soft-deletes a memory (marks deleted, preserves audit)
- [ ] `POST /api/si/privacy/local-only` toggles local-only mode
- [ ] `PATCH /api/si/workers/{id}/restrict` restricts a worker
- [ ] Test: local-only mode blocks all cloud workers regardless of data class
- [ ] Frontend components exist (even if minimal) for memory inspection, disclosure log, worker permissions

---

## 5. Hermes Adapter Contract (§17)

### Current state
`ReasoningProvider` protocol is defined in `api/si/protocols.py` with `generate()`, `supports_streaming()`, `check_availability()`, etc. No actual adapter implements it.

### What needs to be built

#### 5a. Base adapter (`api/si/adapters/base.py`)

```python
# NEW FILE: api/si/adapters/base.py

class BaseAdapter:
    """Base class for worker adapters.

    Subclasses must implement generate() and declare their worker_id,
    provider, capabilities, etc.
    """

    def __init__(self, worker_record: WorkerRecord):
        self.record = worker_record

    async def generate(self, briefing: ContextBriefing, message: str, **kwargs) -> WorkerResult:
        """Execute a task. Must be implemented by each adapter."""
        raise NotImplementedError

    async def check_availability(self) -> AvailabilityStatus:
        """Check if this worker is reachable. Default: try a lightweight call."""
        return AvailabilityStatus(worker_id=self.record.worker_id, available=True)

    def supports_streaming(self) -> bool:
        return self.record.supports_streaming

    def supports_files(self) -> bool:
        return self.record.supports_files

    def supports_images(self) -> bool:
        return self.record.supports_images

    def supports_tools(self, tool_ids: list[str]) -> bool:
        return False  # Override in subclasses that support tool use

    def estimated_cost(self, tokens: int) -> CostEstimate:
        return self.record.estimated_cost or CostEstimate(0, 0)

    def estimated_latency(self) -> LatencyProfile:
        return self.record.latency_profile or LatencyProfile()
```

#### 5b. Hermes adapter (`api/si/adapters/hermes.py`)

```python
# NEW FILE: api/si/adapters/hermes.py

class HermesAdapter(BaseAdapter):
    """
    Adapter for Hermes Agent (local).

    Hermes is a local worker. It can execute terminal commands,
    manage files, run code, and use web search. It never sends
    data to cloud providers.
    """

    worker_id = "hermes_local"
    provider = "nous"
    privacy_class = PrivacyClass.LOCAL_ONLY
    data_location = "local"

    async def generate(self, briefing: ContextBriefing, message: str, **kwargs) -> WorkerResult:
        # Compose prompt from briefing sections
        prompt = compose_prompt_from_briefing(briefing, message)
        # Call Hermes via its local API (http://127.0.0.1:8765 or similar)
        # For now, use the existing AresWorkerAdapter in adapters/
        from api.adapters.ares import AresWorkerAdapter
        # ... bridge to existing adapter
```

The key insight: **don't rewrite the existing adapters**. Wrap them. The existing `api/adapters/ares.py`, `api/adapters/claude.py`, etc. already work. The new SI adapters are thin wrappers that:
1. Receive a `ContextBriefing` (filtered by trust engine)
2. Compose a prompt from the briefing sections
3. Call the existing adapter
4. Return a `WorkerResult`

#### 5c. Registration

```python
# In api/si/worker_registry.py, add a registry method:

def register_adapters(self) -> None:
    """Auto-discover and register available adapters."""
    from api.si.adapters.hermes import HermesAdapter
    from api.si.adapters.claude import ClaudeAdapter
    # ... etc

    for AdapterClass in [HermesAdapter, ClaudeAdapter, ...]:
        try:
            adapter = AdapterClass()
            if adapter.check_availability().available:
                self.register(adapter.record)
                self.set_availability(adapter.record.worker_id, True)
        except Exception:
            pass  # Worker not available, skip
```

### Acceptance criteria
- [ ] `BaseAdapter` class exists in `api/si/adapters/base.py`
- [ ] `HermesAdapter` exists and can call the existing Ares adapter
- [ ] `ClaudeAdapter` exists as a stub (calls Claude API when available)
- [ ] Adapters receive `ContextBriefing`, NOT raw conversation history
- [ ] Test: Hermes adapter can generate a response through the SI pipeline
- [ ] Test: Adapter composition separates identity, context, constraints, and privacy

---

## 6. Integration Tests (§22)

### Current state
71 architecture/unit tests pass. No live integration tests against actual workers.

### What needs to be built

#### 6a. Integration test structure

```python
# NEW FILE: tests/test_si_integration.py

class TestHermesIntegration:
    """Test the full SI pipeline with Hermes as the worker."""

    def test_simple_conversation_through_si(self):
        """User message → classify intent → compile context →
        route to hermes_local → execute → evaluate → compose response."""
        from api.si.orchestrator import orchestrate_request
        from api.si.evaluator import evaluate_result
        from api.si.response_composer import compose_response

        result = orchestrate_request("hello, what is 2+2?")
        assert result["status"] == "ready"
        # If Hermes is available, execute and evaluate
        # ...

    def test_context_briefing_respects_privacy(self):
        """SECRET data should be excluded from the briefing sent to hermes."""
        from api.si.context_compiler import compile_context
        briefing = compile_context("my bank account is 1234", target_worker_id="hermes_local")
        # hermes_local is LOCAL_ONLY, but SENSITIVE data should still be noted
        # Check that the manifest explains what was included/excluded
        assert len(briefing.context_manifest) > 0

    def test_orchestration_persistence(self):
        """Plans should survive a simulated restart."""
        from api.si.orchestrator import orchestrate_request, load_plan, cancel_plan
        result = orchestrate_request("write a hello world script")
        plan_id = result["plan_id"]
        # Simulate restart by loading from DB
        plan = load_plan(plan_id)
        assert plan is not None
        cancel_plan(plan_id)
```

#### 6b. Mock integration tests

For workers that aren't available in the test environment (Claude, Gemini, Grok):

```python
class TestMockWorkerIntegration:
    """Test the SI pipeline with mock workers."""

    def test_mock_worker_through_orchestration(self):
        """Create a mock worker, route to it, verify the pipeline."""
        from api.si.worker_registry import get_registry
        from api.si.types import WorkerRecord, WorkerCapability, PrivacyClass

        registry = get_registry()
        mock_worker = WorkerRecord(
            worker_id="mock_test",
            provider="test",
            display_name="Mock Worker",
            capabilities=[WorkerCapability("conversation", "Mock for testing", 1.0)],
            privacy_class=PrivacyClass.LOCAL_ONLY,
            data_location="local",
        )
        registry.register(mock_worker)
        assert registry.get("mock_test") is not None
```

### Acceptance criteria
- [ ] `tests/test_si_integration.py` exists with pipeline tests
- [ ] Test: full pipeline from user message → orchestrate → evaluate → compose
- [ ] Test: context briefing respects privacy for each worker class
- [ ] Test: plan persistence across simulated restart
- [ ] Test: mock worker registration and routing
- [ ] Tests can run without any cloud API keys (use mocks)

---

## 7. Security Audit (§23)

### Current state
No security audit has been done. The `secret_vault.py` stores secrets in OS keychain (good), but there are known issues:

- Secrets list API returns plaintext values
- No CORS configuration audit
- No path traversal check
- No prompt injection defense
- No rate limiting on SI endpoints

### What needs to be built

#### 7a. Security audit pass

Go through each of the 15 categories from the directive:

| # | Category | Action |
|---|----------|--------|
| 1 | Exposed API keys | Audit all endpoints for accidental key exposure. Remove the `list` endpoint from secret_vault or make it return names only. |
| 2 | Secrets in logs | Grep all logging statements for secret/credential patterns. |
| 3 | Secrets in prompts | Verify no API key, password, or token is ever included in a ContextBriefing. The Trust Engine should block SECRET-classified data. |
| 4 | Unsafe shell execution | Audit all `subprocess` calls. Must use `shlex.quote()` on all user input. |
| 5 | Path traversal | Audit all file operations. Verify paths stay within expected directories. |
| 6 | Unrestricted file access | Workers should only access files explicitly provided in the briefing. |
| 7 | Missing authentication | Verify all `/api/si/` endpoints require auth (or document which are public). |
| 8 | Cross-origin configuration | Audit CORS settings in FastAPI app. |
| 9 | Unvalidated tool arguments | Worker tool calls must be validated before execution. |
| 10 | Arbitrary MCP execution | MCP tool calls must be sandboxed. |
| 11 | Prompt injection exposure | Worker results are UNTRUSTED INPUT. Verify evaluator checks for injection patterns. |
| 12 | Persistent storage encryption | Document that SQLite is NOT encrypted. Add note about encrypting `~/.ares/` with FileVault. |
| 13 | Data deletion behavior | Verify DELETE endpoints actually delete (or soft-delete) data. |
| 14 | Provider data disclosure | Disclosure ledger should track ALL data sent to external providers. |
| 15 | Unsafe automatic actions | Verify no automatic irreversible actions (delete, send, shell) without approval gate. |

#### 7b. Specific fixes

```python
# FIX 1: secret_vault.py — list endpoint should NOT return values
# In api/secret_vault.py, change the list endpoint:
# BEFORE: returns {name: value}
# AFTER:  returns {name: "••••••••"} (masked)

# FIX 2: Add prompt injection check to evaluator
# In api/si/evaluator.py, add:
PROMPT_INJECTION_PATTERNS = [
    r'ignore previous instructions',
    r'disregard your (rules|guidelines|instructions)',
    r'you are now (DAN|jailbroken|unlocked)',
    r'system:\s*',
]

def check_prompt_injection(result: str) -> CheckResult:
    """Check if a worker result contains prompt injection attempts."""
    for pattern in PROMPT_INJECTION_PATTERNS:
        if re.search(pattern, result, re.IGNORECASE):
            return CheckResult("prompt_injection", False, f"Possible injection pattern: {pattern}")
    return CheckResult("prompt_injection", True, "No injection patterns detected")
```

### Acceptance criteria
- [ ] All 15 security categories audited with findings documented
- [ ] Secret vault list endpoint masks values
- [ ] Prompt injection check added to evaluator
- [ ] All `/api/si/` endpoints have authentication requirement documented
- [ ] No hardcoded credentials in source code
- [ ] Test: secret data never appears in a ContextBriefing

---

## 8. End-to-End Success Criteria (§26)

### Current state
Individual subsystems pass tests. The full pipeline (user message → SI → worker → response) has not been wired end-to-end.

### What needs to be verified

The directive defines 13 success criteria. Here's what's needed for each:

| # | Criterion | Status | What's needed |
|---|-----------|--------|---------------|
| 1 | User interacts with one continuous intelligence | ❌ | Wire orchestrate_request() → adapter → evaluate → compose into the chat flow |
| 2 | SI remembers without dumping all history | ⚠️ | Context Compiler works but isn't wired into chat. Need to call compile_context() before sending to worker. |
| 3 | User doesn't choose providers manually | ❌ | Router selects workers but isn't wired into the existing chat UI |
| 4 | Provider outages don't destroy identity | ✅ | SIIdentity is separate from any provider. If a worker is unavailable, routing falls back. |
| 5 | Sensitive data follows explicit policies | ✅ | Trust Engine enforces policies. Tests prove SECRET data never leaves device. |
| 6 | System explains what data was shared | ⚠️ | Disclosure ledger logs it, but no UI to show the user |
| 7 | Workers chosen based on capability and trust | ✅ | Router works. Tests prove eligibility filtering. |
| 8 | Complex work can be planned, resumed, verified | ✅ | Orchestrator works with plans, steps, retries, state persistence. |
| 9 | Results not accepted without checks | ✅ | Evaluator runs deterministic checks on all results. |
| 10 | User can inspect/control memory, tasks, workers, privacy | ❌ | API endpoints exist but no UI |
| 11 | Models can be added/replaced without redesign | ✅ | WorkerRecord + ReasoningProvider protocol. Add new worker to registry. |
| 12 | Hermes is a powerful worker but not the owner | ✅ | Hermes is worker_id="hermes_local", privacy_class=LOCAL_ONLY |
| 13 | SI becomes more useful over time | ❌ | No learning/adaptive scoring yet |

### The critical missing piece

The biggest gap is **wiring the SI pipeline into the existing chat flow**. Right now the SI subsystems exist as standalone modules with API endpoints, but when a user sends a message in the WebUI, it doesn't go through:

```
User message → orchestrate_request() → compile_context() → route_task() → adapter → evaluate_result() → compose_response()
```

It goes directly to the existing chat handler. The wiring needs to happen in `api/chat.py` or wherever the WebUI's chat endpoint is.

**This is the single most important next step** — without it, none of the SI subsystems are actually in the user's path.

### Acceptance criteria
- [ ] Chat flow goes through: intent classify → context compile → privacy filter → route → execute → evaluate → compose
- [ ] User sees one continuous intelligence regardless of which worker executes
- [ ] Provider outages fall back to available workers without breaking the conversation
- [ ] Disclosure ledger records every data sharing event
- [ ] The full pipeline works for at least one worker (Hermes local)

---

## Implementation Order

```
Phase A — Wire the pipeline (most important)
  1. Create BaseAdapter and HermesAdapter
  2. Wire orchestrate_request() into the chat flow
  3. End-to-end test: user message → SI → Hermes → evaluate → compose → response

Phase B — User controls
  4. User model persistence and API
  5. Memory lifecycle (classify, dedup, score, retrieve, correct)
  6. Privacy controls API (local-only toggle, worker restrictions)

Phase C — Identity and persona
  7. Identity persistence and editing
  8. Persona injection into briefing (separate sections, not one prompt)

Phase D — Security
  9. Security audit (15 categories)
  10. Fix secret vault, add prompt injection check

Phase E — Polish
  11. Frontend components for memory/privacy/workers
  12. Adaptive effectiveness scoring
  13. End-to-end success criteria verification
```

Phase A is the critical path. Once the pipeline is wired, every other piece becomes testable end-to-end.