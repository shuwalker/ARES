# ARES Vision

## What ARES is

ARES is one AI assistant backed by multiple agents and a deterministic verification loop. You talk to one thing. Underneath, it dispatches workers — Jaeger, Hermes, Claude Code, Codex, Ollama — verifies their work before acting, and returns one answer. The agents are internals. There is no org chart, no CEO, no hiring.

## The problem it solves

Right now you have five AI tools that don't share memory and can't hand work to each other. You are the integrator — copying results between them, remembering which one knows what, babysitting terminals. That is the job ARES takes over.

## How it works

**One conversation, one memory.** ARES holds the memory, the plans, the history, the decisions. Swap any model underneath and nothing is lost. Every session makes the next one cheaper — it knows your stack, your preferences, your corrections, and it never makes you repeat yourself.

**Agents as hands.** When you ask ARES something, it decides which agent does the work — local, cloud, coding, research — and runs several at once when that's faster. You never operate the agents directly.

**Guard before action.** Nothing acts on a guess. ARES checks readiness, verifies results, and only then answers or acts. The model proposes; the guard verifies; then the system acts. This is what makes autonomy safe.

**Works while you're not there.** ARES can schedule work, run background tasks, and pick up where it left off across sessions.

## What ARES is not

- Not another model, not another CLI, not a chat app
- Not a company of AI employees — no org chart, no CEO, no hiring
- Not an operating system — it's an assistant that runs on one
- Not a wrapper that forwards your question to a better model — the value is everything around the model: memory, judgment, verification, continuity

## Product surfaces

ARES is one product with multiple surfaces over the same controller:

| Surface | What it's for |
|---------|---------------|
| **Agent** | Conversation, sessions, approvals, execution activity |
| **Engineering** | Code, terminal, simulation, design, technical work |
| **Studio** | Image, video, audio, 3D, creative production |
| **Life** | Tasks, routines, goals, schedules, personal organization |
| **Library** | Knowledge, documents, collections, artifacts |
| **Control Center** | Live agents, delegated tasks, tools, services, approvals, memory, activity |
| **Settings** | SI identity, appearance, chat, system configuration |

## Current state

**Implemented:**
- Six product environments plus standalone Settings
- Controller planner, worker registry, persisted plan state, orchestration tests
- `jaeger_local`, `hermes_local`, `claude_local`, `codex_local`, `ollama_local` backends
- Native macOS app + Web UI on port 8788
- SI Settings with JaegerAI bridge v1
- Trust engine, evaluator, response composer, router

**In progress:**
- System Settings: startup destination, preference reset, diagnostic export
- Multi-agent delegation from the primary chat path
- Control Center live visualization
- End-to-end result synthesis and verification

**Known gaps:**
- Automatic delegation from chat is not yet wired end-to-end
- Docker/CI paths reference pre-reorganization layout
- JaegerAI `master` has local commits and is behind remote

## Decisions

### Workers execute out of process
ARES invokes workers through subprocess or network adapters. A worker crash must not take down the controller. Workers own their native execution state; ARES owns the plan and session.

### ARES and workers own separate stores
ARES reads and writes its own journal, tasks, artifacts, and profile state. Each worker owns its native sessions and configuration. ARES may import worker history using read-only access but never writes directly to another application's database.

### Read-only means no write-back
The `read_only` session flag means ARES has no safe append or resume path for that session. Imported sessions remain continuable when their worker exposes a supported resume operation; transcript-only imports remain read-only.

### Clients consume ARES contracts
Framework-native payloads are normalized at the controller or client boundary. React components and native surfaces consume ARES-owned contracts and must not branch on framework display strings.

### Chat streaming uses Server-Sent Events
SSE is the canonical transport for tokens, tool activity, errors, and completion. Starting, cancelling, approving, and clarifying are ordinary authenticated HTTP requests.
