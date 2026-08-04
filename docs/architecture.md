# ARES Architecture

## Process topology

```
Browser / Native App
  │  HTTP + SSE
  ▼
FastAPI Controller (services/controller/fastapi_app/)
  │  routers → api/ business logic
  ▼
Worker Adapters (integrations/workers/)
  │  subprocess per turn
  ▼
Worker processes: Jaeger AI · Hermes · Claude Code · Codex · Ollama · cloud APIs
```

Three layers, one product:

| Layer | Owns |
|-------|------|
| Client (`apps/web/`, `apps/macos/`) | Presentation, navigation, user interaction |
| Controller (`services/controller/`) | Sessions, identity, auth, context assembly, streaming |
| Workers (`integrations/workers/`) | Model inference, tool execution, code loops |

## Dispatch model

ARES dispatches work to agents through a planner → orchestrator → worker pipeline:

1. **User sends a message** in the Agent conversation
2. **ARES classifies the request** — simple (direct response) or complex (needs a plan)
3. **For complex requests:** the planner decomposes into steps with dependencies, the orchestrator assigns steps to workers by capability/privacy/cost, and steps execute sequentially or in parallel
4. **Each worker** receives a filtered context briefing (not the full journal), executes in an isolated subprocess, and returns a structured result
5. **The evaluator** checks every result before the response composer presents it to the user
6. **Control Center** shows live plans, active workers, progress, approvals, and provenance

### Simple tasks
```
User message → classify intent → pick worker → send briefing → get result → verify → respond
```

### Complex tasks
```
User message → create plan → execute step 1 → verify → execute step 2 → verify → ... → synthesize → respond
```

### Parallel execution
Independent steps run concurrently. Dependent steps run sequentially. Concurrency limits are configurable.

## Paperclip parity (first principles)

Paperclip is a functional multi-agent framework. From its source (`SPEC-implementation.md`, `PRODUCT.md`, `docs/start/architecture.md`), its core loop is:

```
Board defines goals → org tree of agents → heartbeat scheduler fires
  → adapter execute() spawns agent → agent works via REST API
  → result + cost captured → run recorded → budget checked → audit logged
```

Comparing against ARES's actual code (`core/si/`), first principles:

| Paperclip capability | ARES equivalent (verified in code) | Status |
|---|---|---|
| Task hierarchy → goal | `planner.py` Plan/Step model with dependencies | ✅ exists |
| Task assignment | `planner.assign_workers`, `worker_registry.find_eligible` | ✅ exists |
| Agent registry + capabilities | `worker_registry.py` (register, find_by_capability, availability) | ✅ exists |
| Adapters (any runtime) | `integrations/workers/` + `ReasoningProvider` protocol | ✅ exists |
| Approval gates | `core/authority/route_approvals.py`, `os_automation_consent.py`, trust_engine approval checks | ✅ exists |
| Audit trail | `core/events/turn_journal.py`, `run_journal.py`, disclosure ledger | ✅ exists |
| Verification of results | `evaluator.py` (6 checks) + `response_composer.py` | ✅ exists |
| **Heartbeat scheduler** | `api/schedule_scheduler.py`, `schedules_store.py` | ⚠️ exists but not wired to plans/runs |
| **Run records + session resume across runs** | `run_journal.py` + session lifecycle | ⚠️ partial |
| **Budget enforcement (hard stop)** | none | ❌ missing |
| **Board/org chart/companies** | — | N/A by design (one assistant, no org — see vision.md) |

**Verdict: yes — ARES's core is capable of what Paperclip does, minus the company layer (deliberately rejected).** The primitives exist: plan, assign, dispatch, verify, approve, audit. The missing loop is the **heartbeat → run → budget cycle** that makes work happen unattended:

1. **Heartbeat scheduler** wakes a plan on timer / assignment / on-demand
2. **Run executor** dispatches via adapters, records the run in `run_journal`
3. **Budget meter** checks spend against limits — soft alert, then hard pause
4. **Session resume** continues the worker's session across heartbeats (Paperclip's session state capture → next heartbeat)

That closes the parity gap without copying Paperclip's org chart. Steal the engine, skip the company (per vision.md).

## Delegation design (target)

The dispatch path ARES is building, shaped by the Claude Code and Hermes source research:

1. **Model-tool delegation** — delegation is a tool the model can call, same shape as Claude's `Agent` tool and Hermes `delegate_task`. The model decides when to delegate; the system executes. No separate dispatcher service.
2. **Isolated child context** — each delegated task runs in an isolated context (clone parent state, child abort, no state write-back). Only the final summary returns to the parent conversation.
3. **Async completion** — long tasks register in a task registry and notify back into the main loop when finished, so the parent conversation is not blocked (Claude's `LocalAgentTask` pattern).
4. **Context slimming** — read-only specialists get a slim briefing: no repo context, no write tools (Claude's Explore/Plan pattern). Saves tokens, prevents side effects.
5. **Depth and concurrency limits** — separate knobs: max nesting depth, max parallel children, total task budget. Claude defaults: depth 3, concurrent 20. ARES: configurable, conservative default.
6. **Durable swarm topology** — multi-step unattended work runs as planning root → parallel workers → verifier → synthesizer with results on a shared blackboard (Hermes Kanban Swarm pattern). Every handoff is a durable row; the run survives restarts.
7. **Heartbeat loop** (Paperclip pattern) — scheduler wakes work on timer/assignment/on-demand; run executor dispatches via adapters and records the run; budget meter checks spend (soft alert → hard pause); session state resumes across heartbeats. This is the unattended-work loop that Paperclip ships and ARES is missing.

Reference: `claude-code-dispatch-research.md` (GitHub + analysis folders), `ares-jaeger-lessons.md`.

## Guard and verification

ARES enforces a hard boundary between *the model proposes* and *the system acts*:

1. **Trust Engine** — classifies data sensitivity (public/personal/private/sensitive/secret), gates provider eligibility, enforces local-only mode
2. **Evaluator** — checks worker output against expectations before presenting to user (6 checks: completeness, consistency, safety, accuracy, format, policy)
3. **Approval gates** — shell commands, file deletion, external API calls, spending above threshold, sending sensitive data all require explicit user approval
4. **Response Composer** — assembles verified results into one coherent answer with provenance

### Data classification

| Class | Who can see | Rule |
|-------|------------|------|
| Public | Any worker | Include freely |
| Personal | Approved providers | Include with disclosure tracking |
| Private | Local workers only | Redact from cloud briefings |
| Sensitive | Explicit approval per task | Redact by default |
| Secret | Never leaves device | Never include in any briefing |

## Memory and state

### Two stores, one direction

```
ARES_HOME/          ARES-owned state (read + WRITE)
Worker stores       Worker-owned state (read ONLY)
```

ARES never writes another app's store. When a worker session needs a new turn, ARES asks the worker to write it. This is a deliberate boundary.

### Memory types

| Type | What | Lifecycle |
|------|------|-----------|
| Episodic | Conversations, events, actions | Permanent, searchable |
| Semantic | Facts, preferences, decisions | Permanent, searchable |
| Working | Current task state, active plan | Cleared when task completes |
| Scratchpad | Worker temporary state | Cleared when worker task completes |

### Context assembly

Workers never see the full journal. The context compiler assembles a filtered, token-budgeted briefing per task: identity, relevant user context, project context, recent conversation, relevant memories, constraints, privacy policy, available tools, and output requirements.

## System boundaries

### What ARES owns

| Subsystem | Owns |
|-----------|------|
| Identity | Name, persona, behavioral principles |
| Memory | Journal, user model, preferences, decisions |
| Context | What to send, what to redact, what budget |
| Trust | Data classification, provider eligibility, approval gates |
| Planning | Task decomposition, step ordering, dependencies |
| Routing | Which worker for which task |
| Verification | Checking worker output against expectations |
| Response | Final voice, uncertainty framing, activity summary |
| Policy | What requires approval, what data can leave the device |

### What workers own

Workers own execution. They do NOT own identity, memory, policy, or the user relationship.

| Worker | Owns |
|--------|------|
| Hermes | Tool execution, terminal ops, file ops, agent loops |
| Claude Code | Code generation, reasoning |
| Codex | Code generation, general reasoning |
| Ollama | Local inference, privacy-safe computation |
| Jaeger AI | Local companion, macOS control, voice |

### Boundary enforcement

1. Workers cannot directly mutate permanent memory — only ARES writes to the journal
2. Workers cannot bypass trust policy — the trust engine gates all data
3. Workers cannot access secrets — API keys are injected by ARES, never in briefings
4. Workers cannot initiate actions — ARES dispatches all tasks
5. Worker outputs are untrusted input — the evaluator checks all results

## Worker adapter contract

All workers are accessed through a common interface:

```python
class ReasoningProvider(Protocol):
    worker_id: str
    provider: str
    capabilities: list[str]
    data_location: str      # "local" | "cloud"
    privacy_class: str      # "local_only" | "external_provider" | "approved_provider"

    async def generate(self, briefing: ContextBriefing, message: str) -> WorkerResult: ...
    async def check_availability(self) -> AvailabilityStatus: ...
```

### ContextBriefing (what ARES sends to workers)

Filtered, budgeted context per task: identity, user context, project context, recent conversation, relevant memories, constraints, privacy policy, available tools, output requirements, and a manifest of what was included/excluded/redacted.

### WorkerResult (what workers return)

Structured result: content, artifacts, tool calls, confidence, cost report, metadata, and verification evidence.

## Worker integration (what each backend needs in code)

### Jaeger AI (`jaeger_local`)
- **Bridge protocol v1** over stdio (NDJSON) — ARES sends a turn, Jaeger resumes its own session, streams output back
- `save_identity` / `select_character` / `make_default` commands for assistant name/persona projection
- Gateway mode: HTTP to Jaeger gateway at `ARES_JAEGER_GATEWAY_URL` with `ARES_JAEGER_GATEWAY_KEY`
- Validation: discover a real JaegerAI product root; reject legacy JROS installs
- Contract: `/api/companion` normalized client surface

### Hermes (`hermes_local`)
- Hermes CLI as subprocess: `hermes --session <id> --prompt "<turn>"` (or `hermes run`)
- Or gateway mode: HTTP to Hermes gateway, session resume via session ID
- Skills live in Hermes profiles (`~/.hermes/profiles/<name>/skills/`) — ARES does not duplicate them
- Delegation inside Hermes uses `delegate_task` (max_concurrent_children 3, max_spawn_depth 1 on this machine)

### Claude Code (`claude_local`)
- CLI subprocess: `claude -p "<prompt>" --resume <session_id>` or `claude --fork-session` for a new branch
- Read-only transcript import from `~/.claude/projects/**/*.jsonl` (mode=ro, never write)
- Built-in subagents (Explore/Plan/general) available inside the CLI; ARES does not reimplement them
- Disallow write tools for read-only tasks via `--disallowedTools`

### Codex (`codex_local`)
- CLI subprocess: `codex exec --session <id> "<prompt>"` (or `codex resume`)
- Session store at `~/.codex/sessions/**` — detect, not parse

### Ollama (`ollama_local`)
- HTTP API: `POST /api/chat` with model name, streaming
- Local-only data class: never receives private/sensitive data from cloud-capable path

### Common adapter contract
Every backend implements the `ReasoningProvider` protocol (worker_id, provider, capabilities, data_location, privacy_class, health check, generate). ARES never imports a worker's execution loop — subprocess or network adapter only.

## Runtime invariants

- ARES never silently selects a worker on a new profile
- Profile readiness and execution readiness are reported separately
- Backend selection, model selection, and tool selection remain distinct
- Every completed turn retains worker and model provenance
- External stores are opened read-only
- Worker failure degrades a capability; it must not erase the ARES session

## Extensions

ARES WebUI supports an opt-in extension surface for self-hosted installs. Extensions can serve static assets and inject same-origin CSS/JS. They execute with full WebUI session authority — only enable extensions you wrote yourself or from sources you trust.

## Contracts

For contract-affecting changes, see `services/controller/docs/CONTRACTS.md` for the full contract index, RFCs, and review expectations. Key contracts:

- Session resolution: `services/controller/docs/rfcs/canonical-session-resolution.md`
- Run adapter: `services/controller/docs/rfcs/ares-run-adapter-contract.md`
- Agent source boundary: `services/controller/docs/rfcs/agent-source-boundary.md`
- Turn journal: `services/controller/docs/rfcs/turn-journal.md`
