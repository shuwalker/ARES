# Phase 3 Architecture Proposal: Context Store & Agent Delegation

Status: **proposal, not approved** — no code written against this yet.

## The constraint that shapes everything below

`.claude/FOUNDATION.md` (current, uncommitted-but-governing doc in this repo)
is explicit:

> Do not: ... duplicate framework-owned execution or memory without an
> explicit service ...

and:

> JaegerAI is a first-class framework connection for agent execution ...
> ARES never re-implements JaegerAI.

and (CLAUDE.md):

> ARES Agent is an optional addition ARES can call on for coding, terminal
> work, skills, sessions, cron, model/provider routing, **delegation**,
> **memory-backed automation**, and operations.

Both requested Phase 3 pillars — a vector memory store and a LangGraph
multi-agent router — are, in their most obvious form ("ARES runs its own
memory DB," "ARES runs its own agent graph"), exactly the pattern this rule
forbids: JaegerAI already owns runtime memory/persona, and ARES already
advertises delegation and memory-backed automation as its own capabilities.
Building competing ARES-native versions of both would fork the SI's identity
into two disagreeing implementations — the specific failure mode FOUNDATION.md
is written to prevent.

This isn't a reason to drop the pillars. It's the design constraint: **ARES's
job is to be the presentation/coordination layer over these capabilities, not
a second implementation of them.** Every recommendation below is scoped to fit
inside that boundary. Where a genuinely ARES-native piece is unavoidable, it's
called out explicitly as a new, explicit **connection** — first-class in the
existing adapter registry, with its own health/capability contract — never a
hidden internal engine.

## What already exists (read directly from the codebase, not assumed)

- **Adapter contracts** — `webui/fastapi_app/adapters/base.py`:
  `BaseConnectionAdapter` (health + capabilities for any connection),
  `BaseLLMAdapter` (execution: `stream_chat`, `get_models`, stream
  subscribe/replay/cancel), `BaseToolAdapter` (`list_tools`). Concrete
  adapters in `frameworks.py` (`AresAdapter`, `JaegerAdapter`,
  `HybridAdapter`) and `mcp.py` (`McpToolAdapter`), dispatched by
  `AdapterRegistry` (`registry.py`) keyed off the Local Profile's selected
  backend. This is the seam every new "connection" (including anything Phase
  3 adds) must go through — it's already the enforcement mechanism for "no
  competing runtime."
- **Local Profile memory today** — `webui/api/memory_store.py`: flat files
  only. `MEMORY.md` / `USER.md` / `SOUL.md` under the active ARES home, plus
  best-effort discovery of project-context files (`.ares.md`, `AGENTS.md`,
  `CLAUDE.md`, `.cursorrules`) walked up from a workspace's git root. No
  embeddings, no retrieval, no ranking — it's read-whole-file-and-inject.
  Explicitly scoped as "Local Profile files," not runtime memory: "The active
  runtime remains the authority for runtime memory."
- **MCP tool inventory** — `webui/fastapi_app/adapters/mcp.py` +
  `webui/api/mcp_config.py`: MCP servers are configured centrally, status is
  probed without ever auto-starting a server ("inventory reads never start or
  probe MCP servers" is a stated invariant), tools are surfaced as a flat
  list with `server`/`name`/`connected` state.
- **Streaming/run infrastructure** — `webui/api/run_journal.py` +
  `webui/api/streaming.py`: every run already gets a durable, replayable
  event journal keyed by `session_id`/`stream_id`, which is how the
  `subscribe_stream`/`replay_stream`/`stream_status` adapter methods work.
  This is the existing mechanism for "show the user what a long-running,
  possibly-multi-step operation is doing" — any delegation UI should reuse
  it, not invent a second progress-event system.
- **No vector/embedding/LangGraph code exists anywhere in the repo** (grepped
  fresh for `langgraph`, `chromadb`, `faiss`, `pgvector`, `vector.?store`
  across `webui/api` and `webui/fastapi_app` — zero hits). This is genuinely
  greenfield.
- **Canonical vocabulary already has a slot for delegation**:
  `FOUNDATION.md`'s term table maps "work assigned to another process/agent"
  → **Delegation**, and "System status" already lists "delegations" as a
  first-class thing the UI shows. The product concept isn't new — only the
  execution engine behind it is undecided.

## Pillar 1 — Context Store (rescoped from "Persistent Vector Memory")

**Reframe:** this is not memory *for the SI* (JaegerAI/ARES own that). It's
retrieval over the engineering context ARES itself is responsible for —
Local Profile notes, project context files, and (opt-in) past session
transcripts — surfaced to whichever runtime is active, the same way the
current `memory_store.py` injects `MEMORY.md`/`USER.md` today, just with
ranking instead of whole-file dumping.

**Proposed design:**

1. **New adapter capability, not a new adapter kind.** Add a
   `memory.retrieval` capability string (alongside the existing
   `conversation`/`tool.use`/`assistant.identity` capability vocabulary in
   `frameworks.py`'s `capabilities()` mapping) and a small
   `ContextStoreService` (plain service class, not a `BaseConnectionAdapter`
   subclass — it has no health/offline state to report, it's a local
   read/write store like `memory_store.py` already is).
2. **Storage: SQLite + `sqlite-vec`, not Chroma/FAISS/pgvector.** This repo
   already standardizes on SQLite for local state (`state.db`,
   `webui_session_db.py`, session sidecars) and explicitly avoids adding
   service dependencies for local-first operation (see CLAUDE.md: "Cloud-only
   dependencies need local or graceful fallback behavior"). `sqlite-vec` is a
   single-file SQLite extension (no server process, no separate DB to run
   alongside JaegerAI/ARES), matches the existing storage philosophy, and
   is trivial to make optional (if the extension fails to load, fall back to
   the current flat-file behavior — the existing degrade-honestly pattern
   FOUNDATION.md requires). Chroma/FAISS/pgvector are all heavier
   (Chroma/pgvector want a running service; FAISS has no native persistence
   story) for what is, in this deployment, a single-user local store.
3. **Embedding model: local, not a cloud call on every message.** Reuse
   whatever local model path already exists for Ollama (`JROS_COMPATIBLE_MODEL_PROVIDERS`
   in `model_catalog.py` already treats `ollama-local` as a first-class
   provider) — e.g. `nomic-embed-text` via the local Ollama endpoint already
   in play. Cloud embedding (OpenAI/Voyage) as an opt-in upgrade only, same
   pattern as the rest of the provider system (configured, never assumed).
4. **Ingestion sources**, each explicit and user-visible in Settings (not a
   silent background crawl): (a) `MEMORY.md`/`USER.md`/`SOUL.md` on write —
   chunk + embed on the existing `write_memory()` path in `memory_store.py`;
   (b) project-context files, re-embedded on mtime change, reusing
   `project_context_candidates()`'s discovery logic instead of writing a
   second file-walker; (c) session transcripts — **off by default**, opt-in
   per FOUNDATION.md's "must not silently fork... memory" spirit; a user
   explicitly turning this on is different from ARES quietly building a
   shadow transcript store.
5. **Retrieval injection point**: `AdapterRegistry.for_session()` /
   `JournaledFrameworkAdapter.stream_chat()` in `frameworks.py` is where a
   turn currently gets handed to the selected runtime. Retrieval happens
   *before* that call — top-k chunks get formatted into the same kind of
   context block `read_memory()` already produces, so from the runtime's
   point of view nothing changes shape, there's just more relevant context in
   it. **The runtime still owns what it does with that context** — ARES
   supplies it, never injects itself into the runtime's own reasoning loop.
6. **What this explicitly does NOT do**: store or rank JaegerAI's own
   conversation memory, replace `SOUL.md`/persona files, or become a second
   source of truth for "what does the SI remember about this project" if
   JaegerAI/ARES ever expose their own retrieval API — if/when they do,
   this service should prefer delegating to theirs over maintaining a
   parallel index for the same content.

**Risk relative to FOUNDATION.md: low.** This is squarely "ARES-owned Local
Profile / project-context presentation," which the doc already assigns to
ARES explicitly.

## Pillar 2 — Agent Delegation (rescoped from "LangGraph Router + Sub-Agents")

This is the higher-risk pillar. Three options, ordered by how much new
ARES-native execution surface they introduce:

### Option A (recommended v1 scope): Comparison Run — delegation via the existing adapter registry, zero new execution engine

`AdapterRegistry` already holds N `BaseLLMAdapter`s (`ares`, `jros`,
`hybrid`, and any future connection). A "Compare" or "Fan-out" run is: take
one user request, call `stream_chat` on multiple adapters concurrently
(`asyncio.gather` over existing adapter calls — no new execution runtime),
and present results side-by-side with provenance (`connection_id`,
model/provider, run state) — which FOUNDATION.md already requires for any
multi-agent comparison ("Every comparative or synthesized result should
retain provenance"). This delivers real "multiple specialized agents working
in parallel" value using *only* the seam that already exists and is already
governed (adapter health checks, capability contracts, `AdapterRegistry`).
No LangGraph, no new persistence, no new runtime. This is the "Router Agent"
in the loosest useful sense: the router is `AdapterRegistry`, already built.

### Option B: True task decomposition — delegate to ARES, don't reimplement it

If the ask is closer to "one request gets split into a math sub-task and a
code sub-task automatically," CLAUDE.md says ARES *already* advertises this
("delegation... memory-backed automation") as a capability. The correct
integration is an adapter that calls into ARES's delegation surface (once
ARES is installed — it's opt-in, `--with-ARES`, not bundled) and relays
its progress through the existing run-journal/stream-channel pattern
(`run_journal.py`), the same way `JaegerAdapter`/`AresAdapter` already relay
their runtime's events. ARES's job here is strictly: start the delegated
run, observe it, present it with provenance. It does not decide *how* to
split the task — that planning logic belongs to ARES, or it becomes exactly
the "second execution engine" FOUNDATION.md prohibits.

**Blocking question this option can't resolve on its own: is ARES actually
installed in this deployment?** It's opt-in per `CLAUDE.md` — "Not installed
by default." If it isn't, Option B has no runtime to delegate to yet, and
Option A (or waiting) is the only viable v1 path regardless of preference.

### Option C: A genuinely ARES-native LangGraph graph

Only justified if there's a delegation need neither JaegerAI nor ARES cover
(e.g., cross-provider critique/synthesis that isn't really "one runtime's
job"). If pursued, FOUNDATION.md's own escape hatch applies: *"An ARES-native
execution or memory service would need to be explicit and governed by the
same interfaces as every other connection."* Concretely: it would need to be
built as a new `BaseLLMAdapter` (its own `adapter_id`, e.g. `"router"`, its
own health check, its own capability list, registered in
`AdapterRegistry` exactly like `ares`/`jros`/`hybrid`) — never a service that
runs underneath/alongside the adapter layer invisibly. This is the most
architecturally sensitive option and the one most likely to drift into
"competing runtime" if scoped loosely. **Recommend deferring this until
Option A ships and it's clear it doesn't cover the actual need.**

## Sequencing recommendation

1. **Context Store first** (Pillar 1) — low risk, clear scope, extends code
   that already exists (`memory_store.py`), doesn't depend on what's
   installed in a given deployment.
2. **Comparison Run** (Pillar 2, Option A) — low risk, delivers real
   multi-agent value, zero new execution engine, reuses `AdapterRegistry`
   as-is.
3. **ARES-delegated task decomposition** (Pillar 2, Option B) — gated on
   ARES actually being installed; do this before Option C regardless of
   preference, since it's the FOUNDATION-compliant path for real task
   splitting and Option C should only be considered if this turns out to be
   insufficient.
4. **ARES-native LangGraph router** (Pillar 2, Option C) — only if 1–3 leave
   a real gap, and only as an explicit new adapter/connection, not an
   internal engine. This is the one item on this list that would benefit
   from a dedicated FOUNDATION.md amendment discussion before implementation,
   since it's the closest thing to the "explicit ARES-native execution
   service" the doc treats as a special, deliberate case rather than the
   default.

This mirrors how Phase 2.5 got sequenced earlier: the FOUNDATION-compliant,
low-risk option went first (Usage & Cost dashboard, no architecture
conflict), not the flashiest option on the original roadmap.
