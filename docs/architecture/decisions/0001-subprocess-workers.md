# ADR-0001: Workers run as subprocesses, not in-process

**Status:** Accepted
**Date:** 2026-07-22 (recorded retroactively; the decision predates this record)

## Context

The upstream WebUI, which ARES forked, invokes its agent **in-process**:
`api/streaming.py` constructs `AIAgent(...)` directly and receives tokens through a
`stream_delta_callback`. Conversation history is passed as a Python list
(`conversation_history=`), so there is no serialization and no session-identity
problem.

ARES routes work to many workers — jros/JaegerAI, Claude Code, Codex,
Ollama, cloud providers. FOUNDATION states the Companion does not re-implement or
absorb a worker's execution loop; adapters invoke them.

## Decision

Workers are invoked as **subprocesses** through adapters in `api/backends/`.
Continuation is achieved by asking the worker to resume its own session
(`--resume <session_id>`), not by replaying history across the boundary.

## Consequences

Good:

- Framework-agnostic. Claude Code, Codex, and jros cannot be imported as Python
  objects; in-process would have restricted ARES to one runtime.
- Process isolation. A worker crash, hang, or OOM does not take down the
  controller. Upstream cannot make that claim.
- Version independence. ARES does not pin a worker's Python environment.
- Honest boundaries. The worker writes its own store, which is what makes the
  two-store model (ADR-0002) possible.

Costs:

- Session identity must be re-established every turn, which is why the resume
  path is correctness-critical rather than an optimization. A broken resume
  silently starts a new worker session and loses context — this was a real bug.
- Streaming arrives as parsed stdout/stderr rather than typed callbacks.
- Per-turn process start-up cost.

## Note on efficiency

A common objection is that subprocess invocation must re-send the whole
conversation each turn. **It does not.** Only the new user message crosses the
boundary; the worker reloads its own history from its own store via `--resume`.
The payload is one message regardless of conversation length.

## Revisit if

ARES ever narrows to a single, importable Python runtime — the multi-worker
requirement is the whole justification. Process start-up latency alone is not a
sufficient reason; measure it against a warm-worker daemon before reopening.
